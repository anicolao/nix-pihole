#!/usr/bin/env bash
set -euo pipefail

# Test script to validate remote builder setup and functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

test_remote_builder_config() {
    log_info "Testing remote builder configuration..."
    
    local nix_conf="$HOME/.config/nix/nix.conf"
    
    if [[ -f "$nix_conf" ]] && grep -q "ssh://.*aarch64-linux" "$nix_conf"; then
        log_success "Remote builder is configured in nix.conf"
        return 0
    else
        log_warning "Remote builder is not configured in nix.conf"
        return 1
    fi
}

test_nix_in_colima() {
    log_info "Testing Nix installation in Colima..."
    
    if colima ssh -- 'source /etc/profile && nix --version' &> /dev/null; then
        log_success "Nix is installed and working in Colima"
        return 0
    else
        log_warning "Nix is not working in Colima"
        return 1
    fi
}

test_colima_ssh_connection() {
    log_info "Testing SSH connection to Colima..."
    
    if colima ssh -- 'echo "SSH test successful"' &> /dev/null; then
        log_success "SSH connection to Colima is working"
        return 0
    else
        log_warning "SSH connection to Colima failed"
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
    
    # Test remote builder config
    total_tests=$((total_tests + 1))
    if test_remote_builder_config; then
        passed_tests=$((passed_tests + 1))
    fi
    echo ""
    
    # Test Nix in Colima
    total_tests=$((total_tests + 1))
    if test_nix_in_colima; then
        passed_tests=$((passed_tests + 1))
    fi
    echo ""
    
    # Test Colima SSH connection
    total_tests=$((total_tests + 1))
    if test_colima_ssh_connection; then
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