{
  description = "Docker image with SSH server and Nix for remote building";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: let
      # Use host system for building tools and scripts
      pkgs = nixpkgs.legacyPackages.${system};
      
      # Always build Docker image for aarch64-linux to match Colima target
      # This prevents "exec format error" when running on macOS with Colima
      targetSystem = "aarch64-linux";
      targetPkgs = nixpkgs.legacyPackages.${targetSystem};
      
      # Create essential system files that Docker needs to find the root user
      # Use target system's bash for the root shell
      passwdFile = targetPkgs.writeTextFile {
        name = "passwd";
        text = ''
          root:x:0:0:root:/root:${targetPkgs.bash}/bin/bash
          sshd:x:74:74:SSH daemon:/var/empty:/bin/false
        '';
        destination = "/etc/passwd";
      };
      
      groupFile = targetPkgs.writeTextFile {
        name = "group";
        text = ''
          root:x:0:
          sshd:x:74:
        '';
        destination = "/etc/group";
      };
      
      shadowFile = targetPkgs.writeTextFile {
        name = "shadow";
        text = ''
          root:!:19000:0:99999:7:::
          sshd:!:19000:0:99999:7:::
        '';
        destination = "/etc/shadow";
      };
      
      # Create minimal SSH config directory structure
      sshDir = targetPkgs.runCommand "ssh-dir" {} ''
        mkdir -p $out/etc/ssh
        # Use OpenSSH defaults - no custom sshd_config needed
      '';
      
      # Nix configuration
      nixConfig = targetPkgs.writeTextFile {
        name = "nix.conf";
        text = ''
          experimental-features = nix-command flakes
          trusted-users = root
          sandbox = false
          substituters = https://cache.nixos.org/
          trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
        '';
        destination = "/root/.config/nix/nix.conf";
      };
      
      # Simplified entrypoint script using SSH defaults with minimal required config
      # Use target system bash to avoid exec format errors
      entrypoint = targetPkgs.writeTextFile {
        name = "entrypoint";
        text = ''
          #!${targetPkgs.bash}/bin/bash
          set -euo pipefail
          
          echo "Starting SSH server setup..."
          
          # Create required directories
          mkdir -p /etc/ssh /var/run/sshd /var/empty /root/.ssh
          
          # Set proper permissions on shadow file
          chmod 640 /etc/shadow
          
          # Generate SSH host keys if they don't exist
          if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
            echo "Generating SSH host keys..."
            ${targetPkgs.openssh}/bin/ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N "" -q
            ${targetPkgs.openssh}/bin/ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N "" -q  
            ${targetPkgs.openssh}/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q
            chmod 600 /etc/ssh/ssh_host_*_key
            chmod 644 /etc/ssh/ssh_host_*_key.pub
          fi
          
          # Create minimal SSH config with only essential settings for container
          cat > /etc/ssh/sshd_config << 'EOF'
# Minimal SSH configuration for container use
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication no
UsePAM no
EOF
          
          # Set proper permissions on SSH directories
          chmod 700 /root/.ssh
          chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true
          
          # Test SSH configuration
          echo "Testing SSH configuration..."
          ${targetPkgs.openssh}/bin/sshd -T
          
          # Start SSH daemon
          echo "SSH server ready, starting daemon..."
          exec ${targetPkgs.openssh}/bin/sshd -D
        '';
        executable = true;
        destination = "/bin/entrypoint";
      };
    in {
      packages = {
        # Docker image with SSH and Nix pre-configured
        nix-remote-builder = pkgs.dockerTools.buildImage {
          name = "nix-remote-builder";
          tag = "latest";
          
          # Copy packages and system files to root filesystem
          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = with targetPkgs; [
              bash
              coreutils
              gnugrep  # Add grep utility for container checks
              openssh
              nix
              git
              gnutar
              gzip
              xz
            ] ++ [
              # System files and scripts built for target system
              entrypoint
              passwdFile
              groupFile
              shadowFile
              nixConfig
              sshDir
            ];
          };
          
          # Configuration for the image
          config = {
            Env = [
              "PATH=/bin:/usr/bin:/nix/var/nix/profiles/default/bin"
              "USER=root"
              "HOME=/root"
            ];
            
            ExposedPorts = {
              "22/tcp" = {};
            };
            
            WorkingDir = "/root";
            User = "root";
            Cmd = [ "/bin/entrypoint" ];
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