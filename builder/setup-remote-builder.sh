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
    
    # Create and start new container
    log_info "Creating new Nix container..."
    
    # Use NixOS container for a full Nix environment
    # Start container with a simple command that keeps it running
    docker run -d \
        --name "$CONTAINER_NAME" \
        --platform linux/aarch64 \
        --privileged \
        -p 2222:22 \
        nixos/nix:latest \
        tail -f /dev/null
    
    # Wait a moment for container to start
    sleep 2
    
    # Verify container is still running
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        log_error "Container failed to start or exited immediately"
        log_info "Container logs:"
        docker logs "$CONTAINER_NAME" 2>&1 | head -20
        return 1
    fi
    
    # Set up SSH server inside the running container
    log_info "Installing SSH server and diagnostic tools in container..."
    if ! docker exec "$CONTAINER_NAME" nix-env -iA nixpkgs.openssh nixpkgs.git nixpkgs.netcat nixpkgs.procps; then
        log_error "Failed to install SSH server packages"
        return 1
    fi
    
    log_info "Configuring SSH server..."
    docker exec "$CONTAINER_NAME" mkdir -p /etc/ssh /root/.ssh
    
    # Generate host keys
    if ! docker exec "$CONTAINER_NAME" ssh-keygen -A; then
        log_error "Failed to generate SSH host keys"
        return 1
    fi
    
    # Create a minimal SSH configuration that should work
    docker exec "$CONTAINER_NAME" sh -c 'cat > /etc/ssh/sshd_config << EOF
# Basic SSH configuration for container
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication no
UsePAM no
StrictModes no
# Use default host key locations
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
EOF'
    
    # Copy SSH public key to container
    docker cp "$SSH_KEY_PATH.pub" "$CONTAINER_NAME:/root/.ssh/authorized_keys"
    docker exec "$CONTAINER_NAME" chmod 600 /root/.ssh/authorized_keys
    docker exec "$CONTAINER_NAME" chmod 700 /root/.ssh
    
    # Find the correct path for sshd and test it
    log_info "Finding SSH daemon binary..."
    local sshd_path
    sshd_path=$(docker exec "$CONTAINER_NAME" sh -c 'find /nix/store -name sshd -type f -executable 2>/dev/null | head -1')
    
    if [[ -z "$sshd_path" ]]; then
        log_error "SSH daemon not found in container after installation"
        log_info "Available SSH-related binaries:"
        docker exec "$CONTAINER_NAME" sh -c 'find /nix/store -name "*ssh*" -type f -executable 2>/dev/null | head -10' || true
        return 1
    fi
    
    log_info "Found SSH daemon at: $sshd_path"
    
    # Test SSH daemon configuration
    log_info "Testing SSH daemon configuration..."
    if ! docker exec "$CONTAINER_NAME" "$sshd_path" -T; then
        log_error "SSH daemon configuration test failed"
        log_info "SSH configuration:"
        docker exec "$CONTAINER_NAME" cat /etc/ssh/sshd_config || true
        return 1
    fi
    
    log_info "Starting SSH daemon..."
    # Start SSH daemon with better error handling
    if ! docker exec -d "$CONTAINER_NAME" sh -c "
        echo 'Starting SSH daemon...' >&2
        exec '$sshd_path' -D -e -f /etc/ssh/sshd_config
    "; then
        log_error "Failed to start SSH daemon"
        return 1
    fi
    
    # Give SSH daemon a moment to start
    sleep 3
    
    # Verify container is still running after SSH setup
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        log_error "Container exited after SSH daemon setup"
        log_info "Container logs:"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -20
        return 1
    fi
    
    # Check if SSH daemon process is running
    log_info "Verifying SSH daemon is running..."
    if docker exec "$CONTAINER_NAME" pgrep sshd >/dev/null 2>&1; then
        log_success "SSH daemon is running"
    else
        log_error "SSH daemon is not running"
        log_info "Checking for SSH daemon processes:"
        docker exec "$CONTAINER_NAME" ps aux | grep -E "(ssh|SSH)" || true
        log_info "Recent container logs:"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -10
        return 1
    fi
    
    # Test if SSH port is accessible from inside container
    log_info "Testing SSH port accessibility..."
    if docker exec "$CONTAINER_NAME" nc -z localhost 22 >/dev/null 2>&1; then
        log_success "SSH port 22 is accessible inside container"
    else
        log_warning "SSH port 22 is not accessible inside container"
        log_info "Checking listening ports:"
        docker exec "$CONTAINER_NAME" netstat -tlnp 2>/dev/null | grep :22 || true
    fi
    
    log_success "Nix container is ready"
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
    
    log_info "Setting up Nix remote builder with Colima and Docker container..."
    
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