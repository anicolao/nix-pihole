#!/usr/bin/env bash
set -euo pipefail

# Test script to validate remote builder setup and functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="nix-remote-builder"
SSH_KEY_PATH="$HOME/.ssh/nix-remote-builder"

# Configure Docker to use Colima
export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

test_dependencies() {
    log_info "Testing dependencies..."
    
    local failed=0
    
    if ! command -v colima &> /dev/null; then
        log_error "Colima is not installed"
        failed=1
    else
        log_success "Colima is available"
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker CLI is not installed"
        failed=1
    else
        log_success "Docker CLI is available"
    fi
    
    if ! command -v nix &> /dev/null; then
        log_error "Nix is not installed"
        failed=1
    else
        log_success "Nix is available"
    fi
    
    return $failed
}

test_colima_status() {
    log_info "Testing Colima status..."
    
    if colima status &> /dev/null; then
        log_success "Colima is running"
        return 0
    else
        log_warning "Colima is not running"
        return 1
    fi
}

test_docker_container() {
    log_info "Testing Docker container status..."
    
    if docker ps | grep -q "$CONTAINER_NAME"; then
        log_success "Docker container is running"
        return 0
    else
        log_warning "Docker container is not running"
        return 1
    fi
}

test_remote_builder_config() {
    log_info "Testing remote builder configuration..."
    
    local nix_conf="$HOME/.config/nix/nix.conf"
    
    if [[ -f "$nix_conf" ]] && grep -q "ssh://root@localhost:2222" "$nix_conf"; then
        log_success "Remote builder is configured in nix.conf"
        return 0
    else
        log_warning "Remote builder is not configured in nix.conf"
        return 1
    fi
}

test_ssh_banner() {
    log_info "Testing SSH service banner..."
    
    local ssh_banner=""
    if command -v nc >/dev/null 2>&1; then
        # Use netcat to get SSH banner
        ssh_banner=$(echo "quit" | timeout 3 nc localhost 2222 2>/dev/null | head -1 || true)
    elif command -v telnet >/dev/null 2>&1; then
        # Fallback to telnet if netcat is not available
        ssh_banner=$(echo "quit" | timeout 3 telnet localhost 2222 2>/dev/null | grep "SSH-" || true)
    fi
    
    if [[ "$ssh_banner" =~ ^SSH- ]]; then
        log_success "SSH service is responding with banner: $ssh_banner"
        return 0
    else
        log_warning "SSH service banner test failed"
        return 1
    fi
}

test_ssh_permissions() {
    log_info "Testing SSH permissions and configuration..."
    
    # Test if we can check the permissions inside the container
    local perm_check
    perm_check=$(docker exec "$CONTAINER_NAME" bash -c '
        echo "=== SSH Permission Check ==="
        
        # Check /root/.ssh directory
        if [[ -d /root/.ssh ]]; then
            perm=$(stat -c "%a" /root/.ssh 2>/dev/null)
            owner=$(stat -c "%U:%G" /root/.ssh 2>/dev/null)
            echo "/root/.ssh: permissions=$perm, owner=$owner"
            if [[ "$perm" != "700" || "$owner" != "root:root" ]]; then
                echo "ERROR: /root/.ssh has incorrect permissions or ownership"
                exit 1
            fi
        else
            echo "ERROR: /root/.ssh directory not found"
            exit 1
        fi
        
        # Check authorized_keys file
        if [[ -f /root/.ssh/authorized_keys ]]; then
            perm=$(stat -c "%a" /root/.ssh/authorized_keys 2>/dev/null)
            owner=$(stat -c "%U:%G" /root/.ssh/authorized_keys 2>/dev/null)
            echo "/root/.ssh/authorized_keys: permissions=$perm, owner=$owner"
            if [[ "$perm" != "600" || "$owner" != "root:root" ]]; then
                echo "ERROR: authorized_keys has incorrect permissions or ownership"
                exit 1
            fi
        else
            echo "ERROR: /root/.ssh/authorized_keys file not found"
            exit 1
        fi
        
        # Check SSH host keys
        for key in /etc/ssh/ssh_host_*key; do
            if [[ -f "$key" ]]; then
                perm=$(stat -c "%a" "$key" 2>/dev/null)
                if [[ "$perm" != "600" ]]; then
                    echo "ERROR: $key has incorrect permissions: $perm (should be 600)"
                    exit 1
                fi
            fi
        done
        
        echo "All SSH permissions are correct"
    ' 2>&1)
    
    if [[ $? -eq 0 ]]; then
        log_success "SSH permissions are correct"
        echo "$perm_check" | grep -v "^===" >&2
        return 0
    else
        log_warning "SSH permissions check failed"
        echo "$perm_check" >&2
        return 1
    fi
}

test_ssh_authentication() {
    log_info "Testing SSH key authentication..."
    
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log_warning "SSH key not found at $SSH_KEY_PATH"
        return 1
    fi
    
    if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes root@localhost -p 2222 'echo "SSH authentication successful"' &> /dev/null; then
        log_success "SSH key authentication is working"
        return 0
    else
        log_warning "SSH key authentication failed"
        
        # Provide some debugging info
        log_info "Debugging SSH authentication failure..."
        ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -v root@localhost -p 2222 'echo "test"' 2>&1 | head -10 >&2 || true
        return 1
    fi
}

test_nix_in_container() {
    log_info "Testing Nix installation in container..."
    
    if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@localhost -p 2222 'source /root/.nix-profile/etc/profile.d/nix.sh && nix --version' &> /dev/null; then
        log_success "Nix is installed and working in container"
        return 0
    else
        log_warning "Nix is not working in container"
        return 1
    fi
}

test_simple_build() {
    log_info "Testing simple Nix build on remote builder..."
    
    if nix build 'nixpkgs#hello' --system aarch64-linux &> /dev/null; then
        log_success "Simple aarch64-linux build successful"
        return 0
    else
        log_warning "Simple aarch64-linux build failed"
        return 1
    fi
}

run_all_tests() {
    log_info "Running remote builder tests..."
    echo ""
    
    local total_tests=0
    local passed_tests=0
    
    # Test dependencies
    total_tests=$((total_tests + 1))
    if test_dependencies; then
        passed_tests=$((passed_tests + 1))
    fi
    echo ""
    
    # Test Colima status
    total_tests=$((total_tests + 1))
    if test_colima_status; then
        passed_tests=$((passed_tests + 1))
    fi
    echo ""
    
    # Test Docker container
    total_tests=$((total_tests + 1))
    if test_docker_container; then
        passed_tests=$((passed_tests + 1))
    fi
    echo ""
    
    # Test SSH banner (low-level test)
    total_tests=$((total_tests + 1))
    if test_ssh_banner; then
        passed_tests=$((passed_tests + 1))
    fi
    echo ""
    
    # Test SSH permissions
    total_tests=$((total_tests + 1))
    if test_ssh_permissions; then
        passed_tests=$((passed_tests + 1))
    fi
    echo ""
    
    # Test remote builder config
    total_tests=$((total_tests + 1))
    if test_remote_builder_config; then
        passed_tests=$((passed_tests + 1))
    fi
    echo ""
    
    # Test SSH authentication
    total_tests=$((total_tests + 1))
    if test_ssh_authentication; then
        passed_tests=$((passed_tests + 1))
    fi
    echo ""
    
    # Test Nix in container
    total_tests=$((total_tests + 1))
    if test_nix_in_container; then
        passed_tests=$((passed_tests + 1))
    fi
    echo ""
    
    # Test simple build
    total_tests=$((total_tests + 1))
    if test_simple_build; then
        passed_tests=$((passed_tests + 1))
    fi
    echo ""
    
    # Summary
    log_info "Test Results: $passed_tests/$total_tests tests passed"
    
    if [[ $passed_tests -eq $total_tests ]]; then
        log_success "All tests passed! Remote builder is ready for use."
        echo ""
        log_info "You can now build the Raspberry Pi image with:"
        echo "  cd $(dirname "$SCRIPT_DIR")"
        echo "  nix build path:\$PWD#images.rpi4"
        return 0
    else
        log_warning "Some tests failed. Run './setup-remote-builder.sh' to fix issues."
        return 1
    fi
}

main() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_info "This test is designed for macOS systems using Colima"
        log_info "On other platforms, cross-compilation should work directly"
        exit 0
    fi
    
    run_all_tests
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi