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

If the build fails, try:

1. Check that Colima and Docker are installed and working
2. Run the test script: `./builder/test-remote-builder.sh`
3. Restart Colima: `colima stop && colima start --arch aarch64`
4. Check the Nix remote builder configuration in `~/.config/nix/nix.conf`