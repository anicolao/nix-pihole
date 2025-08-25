#!/usr/bin/env bash
set -euo pipefail

# Setup script for remote builder using Colima on macOS
# This allows building aarch64-linux images from aarch64-darwin (Apple Silicon Macs)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="nix-remote-builder"
SSH_KEY_PATH="$HOME/.ssh/nix-remote-builder"

# Parse command line arguments
FORCE_REBUILD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --force-rebuild)
            FORCE_REBUILD=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force-rebuild  Force rebuild of Docker image even if it exists"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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
            log_info "This may take up to 30 seconds..."
            
            # Use timeout to prevent hanging on colima stop
            if timeout 30 colima stop; then
                log_info "Successfully stopped Colima"
            else
                log_warning "Colima stop timed out or failed, forcing deletion..."
                log_info "If this continues to hang, press Ctrl+C and run: ./builder/cleanup.sh"
                # Force delete if stop hangs or fails
                if timeout 30 colima delete --force colima 2>/dev/null; then
                    log_info "Successfully force-deleted Colima instance"
                else
                    log_error "Colima delete also timed out. Manual cleanup may be required."
                    log_info "Try running: ./builder/cleanup.sh"
                    log_info "Or manually: rm -rf ~/.colima && pkill -f colima"
                    exit 1
                fi
            fi
            
            log_info "Waiting for cleanup to complete..."
            sleep 3
        fi
    fi
    
    # Check if there's a stopped instance that might have incompatible settings
    if colima list 2>/dev/null | grep -q "colima.*Stopped"; then
        log_warning "Found stopped Colima instance. Deleting to ensure clean setup..."
        if timeout 20 colima delete --force colima 2>/dev/null; then
            log_info "Successfully deleted stopped instance"
        else
            log_warning "Delete operation timed out, continuing anyway..."
        fi
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
        log_info "You may need to manually clean up with:"
        log_info "  ./builder/cleanup.sh"
        log_info "Or manually:"
        log_info "  colima delete --force colima"
        log_info "  rm -rf ~/.colima"
        log_info "Then try again"
        exit 1
    fi
}

ensure_docker_image() {
    log_info "Ensuring Nix remote builder Docker image is available..."
    
    # Force rebuild if requested
    if [[ "$FORCE_REBUILD" == "true" ]]; then
        log_info "Force rebuild requested, removing existing image..."
        docker rmi nix-remote-builder:latest 2>/dev/null || true
    fi
    
    # Check if the image already exists
    if docker images nix-remote-builder:latest --format "table {{.Repository}}:{{.Tag}}" | grep -q "nix-remote-builder:latest"; then
        log_info "Docker image 'nix-remote-builder:latest' already exists"
        
        # Test if the existing image is working by checking if it has the root user
        log_info "Testing existing Docker image..."
        if docker run --rm nix-remote-builder:latest /bin/bash -c 'grep -q "^root:" /etc/passwd && echo "Root user found"' 2>/dev/null | grep -q "Root user found"; then
            log_success "Existing Docker image appears to be working correctly"
            return 0
        else
            log_warning "Existing Docker image appears to be corrupted (missing root user)"
            log_info "Removing corrupted image and rebuilding..."
            docker rmi nix-remote-builder:latest || true
        fi
    fi
    
    log_info "Docker image not found or corrupted. Building it now..."
    log_info "This may take several minutes on first run..."
    
    # Build the image using the container build script
    if [[ -f "$SCRIPT_DIR/container/build-image.sh" ]]; then
        if "$SCRIPT_DIR/container/build-image.sh"; then
            log_success "Docker image built successfully"
            
            # Verify the newly built image
            log_info "Verifying newly built image..."
            if docker run --rm nix-remote-builder:latest /bin/bash -c 'grep -q "^root:" /etc/passwd && echo "Root user found"' 2>/dev/null | grep -q "Root user found"; then
                log_success "New Docker image verified successfully"
            else
                log_error "New Docker image verification failed - root user not found"
                exit 1
            fi
        else
            log_error "Failed to build Docker image"
            exit 1
        fi
    else
        log_error "Docker image build script not found at $SCRIPT_DIR/container/build-image.sh"
        log_info "Please ensure the container build scripts are available"
        exit 1
    fi
}

setup_nix_container() {
    log_info "Setting up Nix container using pre-built Docker image..."
    
    # Ensure the Docker image is available
    ensure_docker_image
    
    # Remove existing container if it exists to ensure clean state
    if docker ps -a --format 'table {{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        log_info "Removing existing container for clean setup..."
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
    
    log_info "Creating new container from pre-built image..."
    
    # Use our pre-built Docker image with SSH and Nix already configured
    docker run -d \
        --name "$CONTAINER_NAME" \
        --platform linux/aarch64 \
        -p 2222:22 \
        nix-remote-builder:latest
    
    # Give the container time to start up and initialize SSH
    log_info "Waiting for container initialization..."
    sleep 10
    
    # Wait for SSH service to be ready and ensure directory exists
    log_info "Waiting for SSH service to start..."
    for i in {1..30}; do
        if docker exec "$CONTAINER_NAME" test -d /root/.ssh; then
            log_success "SSH directory is ready"
            break
        fi
        if [ $i -eq 30 ]; then
            log_error "SSH directory not created after 30 attempts"
            exit 1
        fi
        sleep 1
    done
    
    # Add SSH key to the container with proper ownership
    log_info "Adding SSH public key to container..."
    docker cp "$SSH_KEY_PATH.pub" "$CONTAINER_NAME:/root/.ssh/authorized_keys"
    
    # Set proper ownership and permissions immediately after copying
    docker exec "$CONTAINER_NAME" bash -c '
        chown root:root /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        chmod 700 /root/.ssh
        chown root:root /root/.ssh
    '
    
    # Verify the container is ready
    log_info "Verifying container setup..."
    docker exec "$CONTAINER_NAME" sh -c '
        echo "=== Container Status ==="
        ps aux | grep -E "(sshd|nix)" || echo "No SSH or Nix processes found"
        
        echo "=== Network Status ==="
        netstat -tlnp 2>/dev/null | grep :22 || echo "SSH not listening on port 22"
        
        echo "=== Nix Verification ==="
        nix --version || echo "Nix not available"
        
        echo "=== SSH Config Verification ==="
        # Find and test SSH daemon configuration
        SSHD_PATH=$(which sshd 2>/dev/null || find /nix/store -name sshd -type f 2>/dev/null | head -1)
        if [ -n "$SSHD_PATH" ]; then
            echo "Testing SSH config with: $SSHD_PATH"
            "$SSHD_PATH" -T || echo "SSH configuration test failed"
        else
            echo "Could not find SSH daemon"
        fi
        
        echo "=== SSH Key Setup Check ==="
        ls -la /root/.ssh/ || echo "No SSH directory"
        test -f /root/.ssh/authorized_keys && echo "Authorized keys file exists" || echo "No authorized keys file"
    '
    
    log_success "Container with pre-configured Nix and SSH service is ready"
}

wait_for_ssh_banner() {
    local max_wait=60
    local wait_time=0
    
    log_info "Waiting for SSH service to start (checking banner)..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        # Test SSH banner using netcat or telnet - this is a lower level test
        local ssh_banner=""
        if command -v nc >/dev/null 2>&1; then
            # Use netcat to get SSH banner
            ssh_banner=$(echo "quit" | timeout 3 nc localhost 2222 2>/dev/null | head -1 || true)
        elif command -v telnet >/dev/null 2>&1; then
            # Fallback to telnet if netcat is not available
            ssh_banner=$(echo "quit" | timeout 3 telnet localhost 2222 2>/dev/null | grep "SSH-" || true)
        fi
        
        # Check if we got a valid SSH banner (should start with "SSH-")
        if [[ "$ssh_banner" =~ ^SSH- ]]; then
            log_success "SSH service is responding with banner: $ssh_banner"
            return 0
        fi
        
        # Print status update every 5 seconds to avoid spam
        if [[ $((wait_time % 5)) -eq 0 ]] && [[ $wait_time -gt 0 ]]; then
            log_info "Still waiting for SSH service... (${wait_time}s/${max_wait}s)"
        fi
        
        sleep 1
        wait_time=$((wait_time + 1))
    done
    
    log_error "SSH service failed to start within ${max_wait} seconds"
    return 1
}

fix_ssh_permissions() {
    log_info "Checking and fixing SSH permissions..."
    
    # Ensure proper ownership and permissions for SSH directories and files
    docker exec "$CONTAINER_NAME" bash -c '
        # Fix ownership - everything should be owned by root:root
        chown -R root:root /root/.ssh/ 2>/dev/null || true
        chown root:root /etc/ssh/ssh_host_*key* 2>/dev/null || true
        
        # Fix directory permissions
        chmod 700 /root/.ssh 2>/dev/null || true
        chmod 755 /etc/ssh 2>/dev/null || true
        
        # Fix file permissions
        chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true
        chmod 600 /etc/ssh/ssh_host_*key 2>/dev/null || true
        chmod 644 /etc/ssh/ssh_host_*key.pub 2>/dev/null || true
        
        # Verify critical permissions
        echo "=== SSH Permission Status ==="
        ls -la /root/.ssh/ 2>/dev/null || echo "No /root/.ssh directory"
        ls -la /etc/ssh/ssh_host_*key* 2>/dev/null || echo "No SSH host keys found"
    '
    
    log_success "SSH permissions fixed"
}

capture_sshd_debug_logs() {
    local log_file="/tmp/sshd_debug_$(date +%s).log"
    
    log_info "Temporarily restarting SSH daemon in debug mode to capture authentication logs..."
    
    # Stop the current SSH daemon
    docker exec "$CONTAINER_NAME" bash -c '
        # Find and stop the current SSH daemon
        SSHD_PID=$(ps aux | grep -E "sshd.*listener" | grep -v grep | awk "{print \$2}" | head -1)
        if [ -n "$SSHD_PID" ]; then
            echo "Stopping SSH daemon with PID: $SSHD_PID"
            kill "$SSHD_PID"
            sleep 2
        fi
    ' 2>/dev/null || true
    
    # Start SSH daemon in debug mode in the background
    log_info "Starting SSH daemon in debug mode..."
    docker exec -d "$CONTAINER_NAME" bash -c '
        SSHD_PATH=$(which sshd 2>/dev/null || find /nix/store -name sshd -type f 2>/dev/null | head -1)
        if [ -n "$SSHD_PATH" ]; then
            echo "Starting debug SSH daemon at: $SSHD_PATH"
            "$SSHD_PATH" -D -d -p 22 &> /tmp/sshd_debug.log &
        else
            echo "Could not find SSH daemon binary"
        fi
    ' 2>/dev/null || log_warning "Failed to start debug SSH daemon"
    
    # Give SSH time to start
    sleep 3
    
    # Verify SSH is running in debug mode
    log_info "Verifying debug SSH daemon is running..."
    docker exec "$CONTAINER_NAME" bash -c '
        if ps aux | grep -E "sshd.*-d" | grep -v grep; then
            echo "Debug SSH daemon is running"
        else
            echo "Debug SSH daemon not found, trying to start it..."
            SSHD_PATH=$(which sshd 2>/dev/null || find /nix/store -name sshd -type f 2>/dev/null | head -1)
            if [ -n "$SSHD_PATH" ]; then
                nohup "$SSHD_PATH" -D -d -p 22 &> /tmp/sshd_debug.log &
                sleep 2
                echo "SSH daemon started with debug logging"
            fi
        fi
    ' 2>/dev/null || true
}

test_ssh_authentication() {
    local max_attempts=3
    local attempt=1
    
    log_info "Testing SSH key authentication..."
    
    while [[ $attempt -le $max_attempts ]]; do
        # For the first attempt, enable debug logging
        if [[ $attempt -eq 1 ]]; then
            capture_sshd_debug_logs
        fi
        
        # Capture SSH error output for debugging
        local ssh_output
        log_info "Attempting SSH connection (attempt $attempt/$max_attempts)..."
        ssh_output=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -v root@localhost -p 2222 'echo "SSH authentication successful"' 2>&1)
        local ssh_exit_code=$?
        
        if [[ $ssh_exit_code -eq 0 ]]; then
            log_success "SSH key authentication is working"
            return 0
        fi
        
        log_warning "SSH authentication attempt $attempt/$max_attempts failed (exit code: $ssh_exit_code)"
        
        # Show SSH client error details for debugging
        if [[ $attempt -eq 1 ]]; then
            log_info "SSH client error details:"
            echo "$ssh_output" | grep -E "(debug1|Permission denied|Authentication|Connection|refused)" || echo "No specific SSH client errors found"
        fi
        
        # Capture real-time SSH daemon debug logs
        log_info "Capturing SSH daemon debug logs for this authentication failure..."
        echo "=== SSH Daemon Debug Output ==="
        
        # Get the debug logs from the SSH daemon
        if docker exec "$CONTAINER_NAME" test -f /tmp/sshd_debug.log 2>/dev/null; then
            echo "--- SSH daemon debug log (last 50 lines) ---"
            docker exec "$CONTAINER_NAME" tail -50 /tmp/sshd_debug.log 2>/dev/null || echo "Could not read SSH debug log"
            echo ""
            
            # Look for specific authentication-related messages
            echo "--- Authentication-related entries ---"
            docker exec "$CONTAINER_NAME" grep -i -E "(auth|key|pubkey|denied|refused|failed|error)" /tmp/sshd_debug.log 2>/dev/null | tail -20 || echo "No authentication messages found in debug log"
            echo ""
        else
            log_warning "SSH debug log not found, checking container output instead..."
        fi
        
        # Also check container stdout/stderr for SSH messages
        echo "--- Container logs since last attempt ---"
        docker logs "$CONTAINER_NAME" --since 30s 2>&1 | grep -i -E "(ssh|auth|connection|refused|denied|error)" | tail -10 || echo "No recent SSH messages in container logs"
        echo ""
        
        # Check basic connectivity and permission status
        log_info "Checking SSH setup and permissions..."
        docker exec "$CONTAINER_NAME" bash -c '
            echo "=== SSH Service Status ==="
            ps aux | grep -E "(sshd)" | grep -v grep || echo "No SSH daemon found"
            
            echo "=== Network Status ==="  
            netstat -tlnp 2>/dev/null | grep :22 || echo "SSH not listening on port 22"
            
            echo "=== SSH Key Debug ==="
            echo "Authorized keys file permissions:"
            ls -la /root/.ssh/authorized_keys 2>/dev/null || echo "No authorized_keys file"
            echo "SSH directory permissions:"
            ls -la /root/.ssh/ 2>/dev/null || echo "No SSH directory"
            echo "Authorized keys content (first line, first 80 chars):"
            head -1 /root/.ssh/authorized_keys 2>/dev/null | cut -c1-80 || echo "Cannot read authorized_keys"
            
            echo "=== SSH Key Validation ==="
            if [ -f /root/.ssh/authorized_keys ]; then
                echo "Testing public key format..."
                while read -r key; do
                    if [ -n "$key" ] && [[ ! "$key" =~ ^[[:space:]]*# ]]; then
                        echo "Key fingerprint: $(echo "$key" | ssh-keygen -l -f - 2>/dev/null || echo "Invalid key format")"
                    fi
                done < /root/.ssh/authorized_keys
            fi
            
            echo "=== SSH Configuration Check ==="
            if [ -f /etc/ssh/sshd_config ]; then
                echo "Key authentication settings:"
                grep -E "PubkeyAuthentication|PasswordAuthentication|PermitRootLogin|AuthorizedKeysFile" /etc/ssh/sshd_config 2>/dev/null || echo "No auth settings found in config"
            else
                echo "No sshd_config file found"
            fi
        ' 2>/dev/null || log_warning "Failed to get SSH debug information"
        
        echo "=== End of Authentication Failure Analysis ==="
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_info "Retrying in 2 seconds..."
            sleep 2
        fi
        attempt=$((attempt + 1))
    done
    
    log_error "SSH key authentication failed after $max_attempts attempts"
    
    # Final comprehensive debugging
    log_info "Performing final SSH authentication debugging..."
    
    # Try a manual SSH test with maximum verbosity
    log_info "Testing SSH connection with maximum verbosity..."
    echo "=== Full SSH Debug Output ==="
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -vvv root@localhost -p 2222 'echo "SSH test"' 2>&1 | head -50 || true
    echo ""
    
    # Show complete SSH daemon debug log
    log_info "Complete SSH daemon debug log:"
    docker exec "$CONTAINER_NAME" bash -c '
        if [ -f /tmp/sshd_debug.log ]; then
            echo "=== Complete SSH Daemon Debug Log ==="
            cat /tmp/sshd_debug.log
        else
            echo "No SSH debug log found"
        fi
    ' 2>/dev/null || true
    
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
    
    # Test the connection - simpler approach since Nix is pre-configured in our image
    log_info "Testing remote builder connection..."
    if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@localhost -p 2222 'nix --version' &> /dev/null; then
        log_success "Remote builder connection successful"
    else
        log_error "Failed to connect to remote builder"
        log_info "Debug: Testing basic SSH connection..."
        if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@localhost -p 2222 'echo "SSH works"'; then
            log_info "SSH connection works, checking Nix installation..."
            log_info "Trying Nix command with full path..."
            ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@localhost -p 2222 '/nix/var/nix/profiles/default/bin/nix --version || /root/.nix-profile/bin/nix --version || which nix'
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
    echo "5. To force rebuild the Docker image:"
    echo "   $0 --force-rebuild"
    echo ""
    echo "6. If you encounter issues, clean up completely and try again:"
    echo "   ./builder/cleanup.sh"
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
    
    log_info "Setting up Nix remote builder with Colima and NixOS container..."
    
    check_dependencies
    setup_ssh_key
    start_colima
    setup_nix_container
    wait_for_ssh_banner
    fix_ssh_permissions
    
    # Test SSH authentication - handle failure gracefully to show logs
    if ! test_ssh_authentication; then
        log_error "SSH authentication failed. Please check the logs above for details."
        exit 1
    fi
    
    configure_nix_remote_builder
    print_usage_instructions
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi