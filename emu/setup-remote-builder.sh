#!/usr/bin/env bash
set -euo pipefail

# Setup script for remote builder using Colima on macOS
# This allows building aarch64-linux images from aarch64-darwin (Apple Silicon Macs)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="nix-remote-builder"
SSH_KEY_PATH="$HOME/.ssh/nix-remote-builder"

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
    else
        # Start Colima with enough resources for Nix builds
        # Use aarch64 architecture to match the target
        colima start --arch aarch64 --cpu 4 --memory 8 --disk 60
        log_success "Started Colima"
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
    
    # Create and start new container
    log_info "Creating new Nix container..."
    
    # Use NixOS container for a full Nix environment
    docker run -d \
        --name "$CONTAINER_NAME" \
        --platform linux/aarch64 \
        --privileged \
        -p 2222:22 \
        nixos/nix:latest \
        sh -c '
            # Install SSH server and other needed packages
            nix-env -iA nixpkgs.openssh nixpkgs.git
            
            # Setup SSH
            mkdir -p /etc/ssh /root/.ssh
            ssh-keygen -A
            
            # Configure SSH to allow root login
            echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
            echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
            echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
            
            # Start SSH daemon and keep container running
            /usr/bin/sshd -D
        '
    
    # Wait for container to be ready
    log_info "Waiting for container to be ready..."
    sleep 10
    
    # Copy SSH public key to container
    docker exec "$CONTAINER_NAME" mkdir -p /root/.ssh
    docker cp "$SSH_KEY_PATH.pub" "$CONTAINER_NAME:/root/.ssh/authorized_keys"
    docker exec "$CONTAINER_NAME" chmod 600 /root/.ssh/authorized_keys
    docker exec "$CONTAINER_NAME" chmod 700 /root/.ssh
    
    log_success "Nix container is ready"
}

configure_nix_remote_builder() {
    log_info "Configuring Nix remote builder..."
    
    # Create or update nix.conf
    NIX_CONF_DIR="$HOME/.config/nix"
    NIX_CONF_FILE="$NIX_CONF_DIR/nix.conf"
    
    mkdir -p "$NIX_CONF_DIR"
    
    # Remove existing remote builder configuration
    if [[ -f "$NIX_CONF_FILE" ]]; then
        grep -v "builders.*ssh://root@localhost:2222" "$NIX_CONF_FILE" > "$NIX_CONF_FILE.tmp" || true
        mv "$NIX_CONF_FILE.tmp" "$NIX_CONF_FILE"
    fi
    
    # Add remote builder configuration
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
    
    log_info "Setting up Nix remote builder with Colima..."
    
    check_dependencies
    setup_ssh_key
    start_colima
    setup_nix_container
    configure_nix_remote_builder
    print_usage_instructions
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi