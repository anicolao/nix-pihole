# Pi-hole RPi4 Image Builder

This directory contains a Nix-based build environment with remote builder support for building Pi-hole RPi4 images, especially useful for cross-compilation from macOS to aarch64-linux.

## Prerequisites

On macOS, install the required dependencies:

```bash
brew install colima docker
```

## Usage

### Quick Start

Enter the Nix development environment and build the image in one command:

```bash
nix develop ./builder -c ./builder/make-image.sh
```

This will:
1. Set up the Nix development environment with all required dependencies
2. Automatically configure a Colima-based remote builder
3. Build the Pi-hole RPi4 image using the remote builder

### Manual Steps

If you prefer to run the steps manually:

```bash
# Enter the development environment
nix develop ./builder

# Set up the remote builder (one-time setup)
./builder/setup-remote-builder.sh

# Build the image
cd .. && nix build path:$PWD#images.rpi4

# Test the remote builder (optional)
./builder/test-remote-builder.sh
```

## How It Works

The builder uses Colima to create an aarch64-linux container that acts as a remote builder for Nix. This approach:

- Avoids complex cross-compilation issues
- Provides native aarch64-linux builds instead of cross-compilation
- Works reliably on Apple Silicon Macs
- Maintains compatibility with the original flake structure

## Scripts

- `make-image.sh` - Main build script that handles everything automatically
- `setup-remote-builder.sh` - Sets up the Colima remote builder
- `test-remote-builder.sh` - Tests the remote builder functionality
- `flake.nix` - Nix development environment with all dependencies

## Troubleshooting

If the build fails or gets stuck, try these steps in order:

### 1. Quick Diagnosis

Run the test script to check the remote builder status:
```bash
./builder/test-remote-builder.sh
```

### 2. Common Issues

**Colima disk resize conflicts:**
If you see warnings about disk resizing (e.g., "unable to resize disk"), you likely have an existing Colima instance with incompatible settings.

**Solution:**
```bash
# Clean up everything and start fresh
./builder/cleanup.sh

# Then try building again
nix develop ./builder -c ./builder/make-image.sh
```

**Container startup issues:**
If the Nix container fails to start or become ready:

```bash
# Check if Docker is running
docker ps

# Restart Colima with correct settings
colima stop
colima start --arch aarch64 --cpu 4 --memory 8 --disk 40

# Try setup again
./builder/setup-remote-builder.sh
```

### 3. Manual Cleanup

If automatic cleanup doesn't work, manually clean up:

```bash
# Stop and remove containers
docker stop nix-remote-builder
docker rm nix-remote-builder

# Stop and delete Colima
colima stop
colima delete --force colima

# Remove Nix remote builder config
grep -v "ssh://root@localhost:2222" ~/.config/nix/nix.conf > ~/.config/nix/nix.conf.tmp
mv ~/.config/nix/nix.conf.tmp ~/.config/nix/nix.conf
```

### 4. Verify Dependencies

Make sure all required tools are installed and working:

```bash
# Check installations
brew list colima docker

# Verify Nix is working
nix --version

# Check Colima can start
colima start --arch aarch64
colima status
```

### 5. Getting Help

If issues persist, check:
1. The container logs: `docker logs nix-remote-builder`
2. Colima status: `colima status`
3. Nix configuration: `cat ~/.config/nix/nix.conf`

## Scripts

- `make-image.sh` - Main build script that handles everything automatically
- `setup-remote-builder.sh` - Sets up the Colima remote builder
- `test-remote-builder.sh` - Tests the remote builder functionality
- `cleanup.sh` - Completely cleans up the remote builder environment
- `flake.nix` - Nix development environment with all dependencies