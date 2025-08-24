#!/usr/bin/env bash
set -euo pipefail

# Setup script for remote builder using Colima on macOS
# This allows building aarch64-linux images from aarch64-darwin (Apple Silicon Macs)

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

check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v colima &> /dev/null; then
        log_error "Colima is not installed. Please install it with: brew install colima"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker CLI is not installed. Please install it with: brew install docker"
        exit 1
    fi
    
    if ! command -v nix &> /dev/null; then
        log_error "Nix is not installed. Please install it from https://nixos.org/download.html"
        exit 1
    fi
    
    log_success "All dependencies are available"
}


start_colima() {
    log_info "Starting Colima..."
    
    # Check if Colima is already running
    if colima status &> /dev/null; then
        log_info "Colima is already running"
        
        # Check if the current instance has compatible settings
        local current_info
        current_info=$(colima status 2>/dev/null) || true
        
        if echo "$current_info" | grep -q "arch: aarch64"; then
            log_success "Existing Colima instance is compatible (aarch64)"
            return 0
        else
            log_warning "Existing Colima instance has incompatible architecture"
            log_info "Stopping existing Colima instance to restart with correct settings..."
            colima stop
            log_info "Waiting for Colima to stop completely..."
            sleep 3
        fi
    fi
    
    # Check if there's a stopped instance that might have incompatible settings
    if colima list 2>/dev/null | grep -q "colima.*Stopped"; then
        log_warning "Found stopped Colima instance. Deleting to ensure clean setup..."
        colima delete --force colima 2>/dev/null || true
        log_info "Waiting after cleanup..."
        sleep 2
    fi
    
    log_info "Starting Colima with aarch64 architecture and adequate resources..."
    log_info "This may take a few minutes on first run..."
    
    # Start Colima with enough resources for Nix builds
    # Use aarch64 architecture to match the target
    # Reduced disk size to avoid resize conflicts
    if colima start --arch aarch64 --cpu 4 --memory 8 --disk 40; then
        log_success "Started Colima successfully"
    else
        log_error "Failed to start Colima"
        log_info "You may need to manually clean up with: colima delete --force colima"
        exit 1
    fi
}

wait_for_colima_ready() {
    local max_wait=60
    local wait_time=0
    
    log_info "Waiting for Colima SSH to be ready..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        # Test if we can connect to Colima via SSH
        # Use the exact same command syntax that works in user's terminal
        if colima ssh -- echo hi >/dev/null 2>&1; then
            log_success "Colima SSH is ready after ${wait_time}s"
            return 0
        fi
        
        # Print status update every 5 seconds to avoid spam
        if [[ $((wait_time % 5)) -eq 0 ]] && [[ $wait_time -gt 0 ]]; then
            log_info "Still waiting for Colima SSH... (${wait_time}s/${max_wait}s)"
            # Add debug output to help diagnose issues
            log_info "Debug: Testing 'colima ssh -- echo hi' command..."
            if colima ssh -- echo hi 2>&1 | head -1 >&2; then
                log_info "Debug: Command succeeded but may have taken too long on first try"
            else
                log_info "Debug: Command failed with exit code $?"
            fi
        fi
        
        sleep 1
        wait_time=$((wait_time + 1))
    done
    
    log_error "Colima SSH failed to become ready within ${max_wait} seconds"
    log_error "Debug: Final manual test..."
    if colima ssh -- echo hi; then
        log_error "Paradox: manual test succeeded but loop failed - possible timing issue"
    else
        log_error "Manual test also failed - connection issue"
    fi
    return 1
}

setup_nix_in_colima() {
    log_info "Setting up Nix in Colima VM..."
    
    # Check if Nix is already installed in Colima
    if colima ssh -- 'command -v nix' &>/dev/null; then
        log_info "Nix is already installed in Colima"
        return 0
    fi
    
    log_info "Installing Nix in Colima VM..."
    log_info "This may take a few minutes..."
    
    # Download the Nix installer first to check network connectivity
    log_info "Downloading Nix installer..."
    if ! colima ssh -- 'curl -f -L --connect-timeout 30 --max-time 300 -o /tmp/nix-install.sh https://nixos.org/nix/install'; then
        log_error "Failed to download Nix installer. Check internet connectivity in Colima VM."
        log_info "Debug: Testing basic connectivity..."
        if colima ssh -- 'curl -f -L --connect-timeout 10 --max-time 30 -o /dev/null https://httpbin.org/status/200'; then
            log_info "Basic internet connectivity works, but nixos.org might be blocked"
        else
            log_error "No internet connectivity in Colima VM"
        fi
        return 1
    fi
    
    log_success "Nix installer downloaded successfully"
    
    # Make the installer executable and run it
    log_info "Running Nix installer with daemon mode..."
    if colima ssh -- 'chmod +x /tmp/nix-install.sh && /tmp/nix-install.sh --daemon --yes'; then
        log_success "Nix installation completed"
        
        # Clean up installer
        colima ssh -- 'rm -f /tmp/nix-install.sh' || true
        
        # Verify Nix is working - try multiple approaches to source the environment
        log_info "Verifying Nix installation..."
        if colima ssh -- 'source /etc/profile && nix --version'; then
            log_success "Nix is working correctly"
        elif colima ssh -- '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && nix --version'; then
            log_success "Nix is working correctly (alternative profile)"
        else
            log_error "Nix installation verification failed"
            log_info "Debug: Checking what got installed..."
            colima ssh -- 'ls -la /nix/ || echo "No /nix directory"'
            colima ssh -- 'cat /etc/profile | grep -i nix || echo "No nix in /etc/profile"'
            return 1
        fi
    else
        log_error "Failed to install Nix in Colima"
        log_info "Debug: Checking installer output..."
        colima ssh -- 'ls -la /tmp/nix-install.sh || echo "Installer not found"'
        return 1
    fi
}

configure_nix_remote_builder() {
    log_info "Configuring Nix remote builder..."
    
    # Get Colima's SSH connection details
    local colima_ssh_config
    colima_ssh_config=$(colima ssh-config 2>/dev/null) || {
        log_error "Failed to get Colima SSH configuration"
        return 1
    }
    
    # Extract SSH details from colima ssh-config
    local ssh_host ssh_port ssh_user ssh_key
    ssh_host=$(echo "$colima_ssh_config" | grep "HostName" | awk '{print $2}')
    ssh_port=$(echo "$colima_ssh_config" | grep "Port" | awk '{print $2}')
    ssh_user=$(echo "$colima_ssh_config" | grep "User" | awk '{print $2}')
    ssh_key=$(echo "$colima_ssh_config" | grep "IdentityFile" | awk '{print $2}')
    
    # Create or update nix.conf
    NIX_CONF_DIR="$HOME/.config/nix"
    NIX_CONF_FILE="$NIX_CONF_DIR/nix.conf"
    
    mkdir -p "$NIX_CONF_DIR"
    
    # Remove existing remote builder configuration
    if [[ -f "$NIX_CONF_FILE" ]]; then
        grep -v "builders.*ssh://" "$NIX_CONF_FILE" > "$NIX_CONF_FILE.tmp" || true
        mv "$NIX_CONF_FILE.tmp" "$NIX_CONF_FILE"
    fi
    
    # Add remote builder configuration using Colima's SSH details
    echo "builders = ssh://${ssh_user}@${ssh_host}:${ssh_port} aarch64-linux ${ssh_key} 10 1 big-parallel,benchmark" >> "$NIX_CONF_FILE"
    
    # Enable builders use
    if ! grep -q "builders-use-substitutes = true" "$NIX_CONF_FILE"; then
        echo "builders-use-substitutes = true" >> "$NIX_CONF_FILE"
    fi
    
    # Test the connection with better error handling
    log_info "Testing remote builder connection..."
    if colima ssh -- 'source /etc/profile && nix --version' 2>/dev/null; then
        log_success "Remote builder connection successful"
    elif colima ssh -- '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && nix --version' 2>/dev/null; then
        log_success "Remote builder connection successful (alternative profile)"
    else
        log_error "Failed to connect to remote builder"
        log_info "Debug: Testing basic SSH connection..."
        if colima ssh -- 'echo "SSH works"'; then
            log_info "SSH connection works, but Nix environment is not properly set up"
            log_info "Debug: Checking Nix installation..."
            colima ssh -- 'ls -la /nix/ 2>/dev/null || echo "No /nix directory found"'
            colima ssh -- 'command -v nix || echo "nix command not found in PATH"'
            colima ssh -- 'echo $PATH'
        else
            log_error "Basic SSH connection failed"
        fi
        return 1
    fi
    
    log_success "Remote builder configured"
}

print_usage_instructions() {
    log_success "Remote builder setup complete!"
    echo ""
    log_info "Usage instructions:"
    echo "1. Build the Raspberry Pi 4 image using the remote builder:"
    echo "   cd $(dirname "$SCRIPT_DIR")"
    echo "   nix build path:\$PWD#images.rpi4"
    echo ""
    echo "2. Alternative build command:"
    echo "   nix build .#packages.aarch64-linux.rpi4-image"
    echo ""
    echo "3. To stop the remote builder when done:"
    echo "   colima stop"
    echo ""
    echo "4. To restart the remote builder later:"
    echo "   $0"
    echo ""
    log_info "The remote builder will automatically be used for aarch64-linux builds."
}

cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        log_error "Setup failed. You may need to restart Colima:"
        log_info "  colima stop && colima start --arch aarch64 --cpu 4 --memory 8 --disk 40"
    fi
}

main() {
    trap cleanup_on_exit EXIT
    
    log_info "Setting up Nix remote builder with Colima..."
    
    check_dependencies
    start_colima
    wait_for_colima_ready
    setup_nix_in_colima
    configure_nix_remote_builder
    print_usage_instructions
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi