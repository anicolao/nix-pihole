{
  description = "Docker image with NixOS, SSH server, and remote builder capabilities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages = {
        # Docker image with SSH and Nix pre-configured
        nix-remote-builder = pkgs.dockerTools.buildLayeredImage {
          name = "nix-remote-builder";
          tag = "latest";
          
          # Create image contents with required packages and setup
          contents = with pkgs; [
            # Core system
            bash
            coreutils
            findutils
            gnugrep
            gnused
            gawk
            
            # SSH server
            openssh
            
            # Nix package manager
            nix
            
            # System utilities
            shadow  # for user management
            glibc
            
            # Network tools for debugging
            nettools
            iproute2
            procps
            
            # Create the setup script as a package
            (writeScript "setup-ssh.sh" ''
              #!/bin/bash
              set -euo pipefail
              
              echo "Setting up SSH server..."
              
              # Create required directories
              mkdir -p /etc/ssh /var/run/sshd /var/empty /root/.ssh /root/.config/nix
              
              # Create system users if they don't exist
              if ! getent group sshd > /dev/null; then
                groupadd -r sshd
              fi
              if ! getent passwd sshd > /dev/null; then
                useradd -r -g sshd -d /var/empty -s /sbin/nologin sshd
              fi
              
              # Generate SSH host keys if they don't exist
              if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
                echo "Generating SSH host keys..."
                ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N "" -q
                ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N "" -q  
                ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q
              fi
              
              # Create SSH configuration
              cat > /etc/ssh/sshd_config << 'SSHD_EOF'
              # SSH daemon configuration for Nix remote builder
              Port 22
              PermitRootLogin yes
              PubkeyAuthentication yes
              PasswordAuthentication no
              AuthorizedKeysFile /root/.ssh/authorized_keys
              UsePrivilegeSeparation yes
              UsePAM no
              StrictModes no
              ListenAddress 0.0.0.0
              
              # Host keys
              HostKey /etc/ssh/ssh_host_rsa_key
              HostKey /etc/ssh/ssh_host_ecdsa_key  
              HostKey /etc/ssh/ssh_host_ed25519_key
              
              # Logging
              SyslogFacility AUTH
              LogLevel INFO
              SSHD_EOF
              
              # Set proper permissions
              chmod 600 /etc/ssh/ssh_host_*_key
              chmod 644 /etc/ssh/ssh_host_*_key.pub
              chmod 700 /root/.ssh
              chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true
              
              # Create nix.conf
              cat > /root/.config/nix/nix.conf << 'NIX_EOF'
              experimental-features = nix-command flakes
              trusted-users = root
              sandbox = false
              substituters = https://cache.nixos.org/
              trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
              NIX_EOF
              
              # Test SSH configuration
              echo "Testing SSH configuration..."
              /bin/sshd -T
              
              # Start SSH daemon
              echo "Starting SSH daemon..."
              exec /bin/sshd -D
            '')
          ];
          
          # Configuration for the image
          config = {
            # Set environment variables
            Env = [
              "PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:/bin:/usr/bin"
              "NIX_PATH=nixpkgs=${nixpkgs}"
              "USER=root"
              "HOME=/root"
            ];
            
            # Expose SSH port
            ExposedPorts = {
              "22/tcp" = {};
            };
            
            # Set working directory
            WorkingDir = "/root";
            
            # Set default user
            User = "root";
            
            # Command to run when container starts
            Cmd = [ "/bin/setup-ssh.sh" ];
          };
        };
      };
      
      # Development shell for building the image
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          docker
          nix
        ];
        
        shellHook = ''
          echo "🐳 Docker image builder environment"
          echo "Available commands:"
          echo "  nix build .#nix-remote-builder  - Build the Docker image"
          echo "  docker load < result             - Load the image into Docker"
        '';
      };
    });
}