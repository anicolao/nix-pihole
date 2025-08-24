#!/usr/bin/env bash
set -euo pipefail

# Setup script for remote builder using Colima on macOS
# This allows building aarch64-linux images from aarch64-darwin (Apple Silicon Macs)

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

setup_ssh_key() {
    log_info "Setting up SSH key for remote builder..."
    
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "nix-remote-builder"
        log_success "Created SSH key at $SSH_KEY_PATH"
    else
        log_info "SSH key already exists at $SSH_KEY_PATH"
    fi
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

setup_nix_container() {
    log_info "Setting up Nix container..."
    
    # Check if container already exists and is running
    if docker ps | grep -q "$CONTAINER_NAME"; then
        log_info "Nix container is already running"
        return 0
    fi
    
    # Check if container exists but is stopped
    if docker ps -a | grep -q "$CONTAINER_NAME"; then
        log_info "Starting existing Nix container..."
        docker start "$CONTAINER_NAME"
        return 0
    fi
    
    # Use the official nixos/nix image which already has Nix properly configured
    log_info "Creating new Nix container using official nixos/nix image..."
    
    # Start the container with a simple command to keep it running
    docker run -d \
        --name "$CONTAINER_NAME" \
        --platform linux/aarch64 \
        --privileged \
        -p 2222:22 \
        nixos/nix:latest \
        tail -f /dev/null
    
    log_info "Container started, installing and configuring SSH..."
    
    # Install openssh and configure it properly using Nix
    docker exec "$CONTAINER_NAME" sh -c '
        # Install openssh via nix-env
        nix-env -i openssh
        
        # Create necessary directories
        mkdir -p /var/run/sshd /root/.ssh /etc/ssh
        
        # Generate host keys if they do not exist
        if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
            ~/.nix-profile/bin/ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N ""
        fi
        if [ ! -f /etc/ssh/ssh_host_ecdsa_key ]; then
            ~/.nix-profile/bin/ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N ""
        fi
        if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
            ~/.nix-profile/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
        fi
        
        # Create a minimal SSH configuration
        cat > /etc/ssh/sshd_config << EOF
# Basic SSH configuration
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication no
StrictModes no
UsePAM no

# Host key locations
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key  
HostKey /etc/ssh/ssh_host_ed25519_key

# Disable some features for simplicity
UseDNS no
X11Forwarding no
PrintMotd no
EOF
        
        # Test SSH configuration
        if ~/.nix-profile/bin/sshd -T -f /etc/ssh/sshd_config >/dev/null 2>&1; then
            echo "SSH configuration test passed"
        else
            echo "SSH configuration test failed"
            ~/.nix-profile/bin/sshd -T -f /etc/ssh/sshd_config
            exit 1
        fi
        
        # Configure Nix for remote building
        mkdir -p /etc/nix
        cat > /etc/nix/nix.conf << EOF
experimental-features = nix-command flakes
trusted-users = root
sandbox = false
EOF
    '
    
    # Add SSH key to the container
    log_info "Adding SSH public key to container..."
    docker cp "$SSH_KEY_PATH.pub" "$CONTAINER_NAME:/root/.ssh/authorized_keys"
    docker exec "$CONTAINER_NAME" chmod 600 /root/.ssh/authorized_keys
    docker exec "$CONTAINER_NAME" chmod 700 /root/.ssh
    
    # Start SSH daemon
    log_info "Starting SSH daemon..."
    docker exec -d "$CONTAINER_NAME" sh -c '~/.nix-profile/bin/sshd -D -f /etc/ssh/sshd_config'
    
    log_success "NixOS container with SSH is ready"
}

wait_for_container_ready() {
    local max_wait=60
    local wait_time=0
    
    log_info "Waiting for container to be ready..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        # First check if the port is open using netcat
        if command -v nc >/dev/null 2>&1; then
            if nc -z localhost 2222 >/dev/null 2>&1; then
                # Port is open, now test actual SSH connectivity
                if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o BatchMode=yes root@localhost -p 2222 exit >/dev/null 2>&1; then
                    log_success "Container SSH is ready after ${wait_time}s"
                    return 0
                fi
            fi
        else
            # Fallback to SSH test only if netcat is not available
            if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o BatchMode=yes root@localhost -p 2222 exit >/dev/null 2>&1; then
                log_success "Container SSH is ready after ${wait_time}s"
                return 0
            fi
        fi
        
        # Print status update every 5 seconds to avoid spam
        if [[ $((wait_time % 5)) -eq 0 ]] && [[ $wait_time -gt 0 ]]; then
            log_info "Still waiting for container SSH... (${wait_time}s/${max_wait}s)"
        fi
        
        sleep 1
        wait_time=$((wait_time + 1))
    done
    
    log_error "Container SSH failed to become ready within ${max_wait} seconds"
    return 1
}

configure_nix_remote_builder() {
    log_info "Configuring Nix remote builder..."
    
    # Create or update nix.conf
    NIX_CONF_DIR="$HOME/.config/nix"
    NIX_CONF_FILE="$NIX_CONF_DIR/nix.conf"
    
    mkdir -p "$NIX_CONF_DIR"
    
    # Remove existing remote builder configuration for this specific container
    if [[ -f "$NIX_CONF_FILE" ]]; then
        grep -v "builders.*ssh://root@localhost:2222" "$NIX_CONF_FILE" > "$NIX_CONF_FILE.tmp" || true
        mv "$NIX_CONF_FILE.tmp" "$NIX_CONF_FILE"
    fi
    
    # Add remote builder configuration using the Docker container
    echo "builders = ssh://root@localhost:2222 aarch64-linux $SSH_KEY_PATH 10 1 big-parallel,benchmark" >> "$NIX_CONF_FILE"
    
    # Enable builders use
    if ! grep -q "builders-use-substitutes = true" "$NIX_CONF_FILE"; then
        echo "builders-use-substitutes = true" >> "$NIX_CONF_FILE"
    fi
    
    # Test the connection
    log_info "Testing remote builder connection..."
    if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@localhost -p 2222 'nix --version' &> /dev/null; then
        log_success "Remote builder connection successful"
    else
        log_error "Failed to connect to remote builder"
        log_info "Debug: Testing basic SSH connection..."
        if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@localhost -p 2222 'echo "SSH works"'; then
            log_info "SSH connection works, but Nix might not be properly set up"
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
    echo "   docker stop $CONTAINER_NAME"
    echo ""
    echo "4. To restart the remote builder later:"
    echo "   $0"
    echo ""
    log_info "The remote builder will automatically be used for aarch64-linux builds."
}

cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        log_error "Setup failed. Cleaning up..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
    fi
}

main() {
    trap cleanup_on_exit EXIT
    
    log_info "Setting up Nix remote builder with Colima and Ubuntu container..."
    
    check_dependencies
    setup_ssh_key
    start_colima
    setup_nix_container
    wait_for_container_ready
    configure_nix_remote_builder
    print_usage_instructions
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi