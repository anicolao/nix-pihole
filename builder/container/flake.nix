{
  description = "Docker container with SSH server and Nix using NixOS-style configuration";

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
      
      # SSH configuration using canonical NixOS services.openssh structure
      # Generate sshd_config with same format as NixOS services.openssh would create
      # Place in non-conflicting location to avoid collision with openssh package
      sshdConfigFile = pkgs.writeTextFile {
        name = "sshd_config";
        text = ''
          Protocol 2
          
          # Host keys
          HostKey /etc/ssh/ssh_host_ed25519_key
          HostKey /etc/ssh/ssh_host_rsa_key
          HostKey /etc/ssh/ssh_host_ecdsa_key
          
          # Ciphers and keying
          KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256
          Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
          MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
          
          # Network settings
          Port 22
          AddressFamily any
          ListenAddress 0.0.0.0
          ListenAddress ::
          
          # Authentication settings
          LoginGraceTime 120
          PermitRootLogin yes
          PubkeyAuthentication yes
          PasswordAuthentication no
          PermitEmptyPasswords no
          ChallengeResponseAuthentication no
          UsePAM no
          
          # Access control
          StrictModes yes
          MaxAuthTries 6
          MaxSessions 10
          
          # Features
          X11Forwarding no
          PrintMotd no
          PrintLastLog yes
          TCPKeepAlive yes
          
          # Logging
          SyslogFacility AUTH
          LogLevel INFO
          
          # Subsystems
          Subsystem sftp ${targetPkgs.openssh}/libexec/sftp-server
          
          # File locations
          AuthorizedKeysFile .ssh/authorized_keys
          PidFile /var/run/sshd.pid
        '';
        destination = "/etc/ssh/sshd_config.nixos";
      };
      
      # SSH host key configuration matching NixOS services.openssh defaults
      sshHostKeys = [
        { path = "/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
        { path = "/etc/ssh/ssh_host_rsa_key"; type = "rsa"; bits = 4096; }
        { path = "/etc/ssh/ssh_host_ecdsa_key"; type = "ecdsa"; bits = 521; }
      ];
      
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
          root:*:19000:0:99999:7:::
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
      
      # Generate SSH host key commands from the canonical NixOS configuration
      hostKeyCommands = builtins.concatStringsSep "\n" (map (key: 
        let 
          keyPath = key.path; 
          keyType = key.type; 
          keyBits = if key ? bits then toString key.bits else ""; 
        in
        ''
          if [ ! -f ${keyPath} ]; then
            echo "Generating ${keyType} host key at ${keyPath}..."
            ${targetPkgs.openssh}/bin/ssh-keygen -t ${keyType} ${if keyBits != "" then "-b ${keyBits}" else ""} -f ${keyPath} -N "" -q
            chmod 600 ${keyPath}
            chmod 644 ${keyPath}.pub
          fi
        ''
      ) sshHostKeys);

      # Entrypoint script that uses SSH configuration following NixOS services.openssh patterns  
      entrypoint = pkgs.writeTextFile {
        name = "entrypoint";
        text = ''
#!${targetPkgs.bash}/bin/bash
set -euo pipefail

echo "Starting SSH server with NixOS-style services.openssh configuration..."

# Create required directories
mkdir -p /etc/ssh /var/run/sshd /var/empty /root/.ssh

# Set proper permissions on shadow file
chmod 640 /etc/shadow

# Ensure root account is unlocked for SSH access
# The shadow file should already have * instead of ! but ensure it's unlocked
if command -v passwd >/dev/null 2>&1; then
  passwd -u root >/dev/null 2>&1 || true
fi

# Copy NixOS-style SSH configuration to correct location
echo "Installing NixOS-style services.openssh configuration..."
cp /etc/ssh/sshd_config.nixos /etc/ssh/sshd_config

# Generate SSH host keys using NixOS services.openssh specification
echo "Generating SSH host keys using NixOS services.openssh specification..."
${hostKeyCommands}

# Set proper permissions on SSH directories
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true

# Test SSH configuration using NixOS-style config
echo "Testing NixOS-style services.openssh configuration..."
${targetPkgs.openssh}/bin/sshd -T -f /etc/ssh/sshd_config

# Start SSH daemon with NixOS-style services.openssh configuration
echo "SSH server ready, starting daemon with NixOS-style services.openssh configuration..."
exec ${targetPkgs.openssh}/bin/sshd -D -f /etc/ssh/sshd_config
        '';
        executable = true;
        destination = "/bin/entrypoint";
      };
    in {
      packages = {
        # Docker image with SSH and Nix configured using NixOS-style services.openssh approach
        nix-remote-builder = pkgs.dockerTools.buildImage {
          name = "nix-remote-builder";
          tag = "latest";
          
          # Copy packages and system files to root filesystem
          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = with targetPkgs; [
              bash
              coreutils
              gnugrep  
              procps   
              nettools 
              netcat   
              openssh
              nix
              git
              gnutar
              gzip
              xz
              shadow  # For passwd command to unlock accounts
            ] ++ [
              # System files and SSH config following NixOS services.openssh patterns
              entrypoint
              passwdFile
              groupFile
              shadowFile
              nixConfig
              sshdConfigFile  # Custom SSH config placed at non-conflicting path
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
          echo "🐳 Docker container builder with NixOS-style SSH configuration"
          echo "Available commands:"
          echo "  nix build .#nix-remote-builder  - Build the Docker container"
          echo "  docker load < result             - Load the container into Docker"
          echo ""
          echo "This container uses SSH configuration following NixOS services.openssh"
          echo "patterns to generate SSH configuration, host keys, and daemon settings."
        '';
      };
    });
}