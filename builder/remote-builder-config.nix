# Declarative container configuration for remote builder
# This file configures a proper container using nixpkgs.dockerTools
# instead of complex NixOS system modules to avoid infinite recursion

# The configuration is now moved to flake.nix using dockerTools.buildImage
# This approach:
# - Avoids module system complexity and infinite recursion
# - Provides explicit dependency management
# - Creates a lightweight but complete Nix build environment
# - Includes SSH daemon with proper configuration
# - Includes Nix daemon for remote building

# Key components included:
# - busybox for basic shell utilities
# - openssh for SSH daemon
# - nix for building packages
# - shadow for user management
# - Essential development tools (git, curl, bash, etc.)

# The container is built with:
# - Proper SSH host key generation
# - Complete sshd_config
# - Nix daemon configuration
# - Initialization script for service startup

# Usage: The image is built via flake.nix as images.remote-builder