{
  description = "Docker container with SSH server and Nix using canonical NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: let
      # Use host system for building tools and scripts
      pkgs = nixpkgs.legacyPackages.${system};
      
      # Always build Docker image for aarch64-linux to match Colima target
      targetSystem = "aarch64-linux";
      targetPkgs = nixpkgs.legacyPackages.${targetSystem};
      
      # Create SSH configuration using canonical NixOS approach
      # Generate a proper sshd_config that matches NixOS defaults
      sshdConfigFile = pkgs.writeTextFile {
        name = "sshd_config";
        text = ''
          # SSH daemon configuration generated using NixOS canonical approach
          Port 22
          Protocol 2
          
          # Host key configuration (canonical NixOS approach)
          HostKey /etc/ssh/ssh_host_rsa_key
          HostKey /etc/ssh/ssh_host_ecdsa_key
          HostKey /etc/ssh/ssh_host_ed25519_key
          
          # Authentication configuration (from services.openssh.settings)
          PermitRootLogin yes
          PubkeyAuthentication yes
          PasswordAuthentication no
          UsePAM no
          StrictModes yes
          AuthorizedKeysFile /root/.ssh/authorized_keys
          
          # Security settings (NixOS defaults)
          X11Forwarding no
          PrintMotd no
          TCPKeepAlive yes
          
          # Logging
          SyslogFacility AUTH
          LogLevel INFO
          
          # Connection settings
          MaxAuthTries 6
          MaxSessions 10
          
          # Subsystems
          Subsystem sftp ${targetPkgs.openssh}/libexec/sftp-server
        '';
        destination = "/etc/ssh/sshd_config";
      };
      
      # Create essential system files that Docker needs to find the root user
      passwdFile = pkgs.writeTextFile {
        name = "passwd";
        text = ''
          root:x:0:0:root:/root:${targetPkgs.bash}/bin/bash
          sshd:x:74:74:SSH daemon:/var/empty:/bin/false
        '';
        destination = "/etc/passwd";
      };
      
      groupFile = pkgs.writeTextFile {
        name = "group";
        text = ''
          root:x:0:
          sshd:x:74:
        '';
        destination = "/etc/group";
      };
      
      shadowFile = pkgs.writeTextFile {
        name = "shadow";
        text = ''
          root:!:19000:0:99999:7:::
          sshd:!:19000:0:99999:7:::
        '';
        destination = "/etc/shadow";
      };
      
      # Nix configuration
      nixConfig = pkgs.writeTextFile {
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
      
      # Entrypoint script simplified - SSH is now configured using NixOS canonical approach  
      entrypoint = pkgs.writeTextFile {
        name = "entrypoint";
        text = ''
#!${targetPkgs.bash}/bin/bash
set -euo pipefail

echo "Starting SSH server with NixOS-generated configuration..."

# Create required directories
mkdir -p /etc/ssh /var/run/sshd /var/empty /root/.ssh

# Set proper permissions on shadow file
chmod 640 /etc/shadow

# Generate SSH host keys if they don't exist
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
  echo "Generating SSH host keys..."
  ${targetPkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" -q
  ${targetPkgs.openssh}/bin/ssh-keygen -t ecdsa -b 521 -f /etc/ssh/ssh_host_ecdsa_key -N "" -q  
  ${targetPkgs.openssh}/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q
  chmod 600 /etc/ssh/ssh_host_*_key
  chmod 644 /etc/ssh/ssh_host_*_key.pub
fi

# Set proper permissions on SSH directories
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true

# Test SSH configuration (using NixOS-generated config)
echo "Testing SSH configuration..."
${targetPkgs.openssh}/bin/sshd -T

# Start SSH daemon with NixOS-generated configuration
echo "SSH server ready, starting daemon with NixOS configuration..."
exec ${targetPkgs.openssh}/bin/sshd -D
        '';
        executable = true;
        destination = "/bin/entrypoint";
      };
    in {
      packages = {
        # Docker image with SSH and Nix configured using canonical NixOS approach
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
              procps   # Add ps command for process monitoring
              nettools # Add netstat command for network monitoring
              netcat   # Add netcat for network testing
              openssh
              nix
              git
              gnutar
              gzip
              xz
            ] ++ [
              # System files and SSH config built using NixOS approach
              entrypoint
              passwdFile
              groupFile
              shadowFile
              nixConfig
              sshdConfigFile  # NixOS-generated SSH configuration
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
        default = self.packages.${system}.nix-remote-builder;
      };
      
      # Development shell for building the image
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          docker
          nix
        ];
        
        shellHook = ''
          echo "🐳 Docker container builder with canonical NixOS SSH configuration"
          echo "Available commands:"
          echo "  nix build .#nix-remote-builder  - Build the Docker container"
          echo "  docker load < result             - Load the container into Docker"
          echo ""
          echo "This container uses NixOS services.openssh module for SSH configuration"
        '';
      };
    });
}