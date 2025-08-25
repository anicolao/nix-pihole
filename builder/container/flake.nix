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
            
            # SSH server and related tools
            openssh
            shadow
            
            # Nix package manager
            nix
            
            # Network tools
            inetutils
            procps
          ];
          
          # Configuration for the image
          config = {
            # Set environment variables
            Env = [
              "PATH=/bin:/usr/bin:/nix/var/nix/profiles/default/bin"
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
            Cmd = [ "/bin/bash" "-c" ''
              set -euo pipefail
              
              echo "Setting up SSH server..."
              
              # Create required directories
              mkdir -p /etc/ssh /var/run/sshd /var/empty /root/.ssh /root/.config/nix
              
              # Create system users
              echo "sshd:x:74:" >> /etc/group
              echo "sshd:x:74:74:SSH daemon:/var/empty:/bin/false" >> /etc/passwd
              
              # Generate SSH host keys
              if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
                echo "Generating SSH host keys..."
                ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N "" -q
                ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N "" -q  
                ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q
                chmod 600 /etc/ssh/ssh_host_*_key
                chmod 644 /etc/ssh/ssh_host_*_key.pub
              fi
              
              # Create SSH configuration
              cat > /etc/ssh/sshd_config << 'EOF'
              Port 22
              PermitRootLogin yes
              PubkeyAuthentication yes
              PasswordAuthentication no
              AuthorizedKeysFile /root/.ssh/authorized_keys
              UsePrivilegeSeparation no
              UsePAM no
              StrictModes no
              ListenAddress 0.0.0.0
              HostKey /etc/ssh/ssh_host_rsa_key
              HostKey /etc/ssh/ssh_host_ecdsa_key  
              HostKey /etc/ssh/ssh_host_ed25519_key
              SyslogFacility AUTH
              LogLevel INFO
              EOF
              
              # Set proper permissions
              chmod 700 /root/.ssh
              chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true
              
              # Create nix.conf
              cat > /root/.config/nix/nix.conf << 'EOF'
              experimental-features = nix-command flakes
              trusted-users = root
              sandbox = false
              substituters = https://cache.nixos.org/
              trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
              EOF
              
              # Test SSH configuration
              echo "Testing SSH configuration..."
              /bin/sshd -T
              
              # Start SSH daemon
              echo "Starting SSH daemon..."
              exec /bin/sshd -D
            '' ];
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