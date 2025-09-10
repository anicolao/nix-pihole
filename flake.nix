{
  description = "Pi-hole RPi4 Image Builder with Remote Builder Support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      hostname = "pihole";
      # Use personal configuration if it exists, otherwise fall back to default
      userConfig = if builtins.pathExists ./personal/alex_users.nix 
        then ./personal/alex_users.nix 
        else ./default-users.nix;
    in
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Core dependencies for remote builder
            colima
            docker
            docker-compose

            # Nix tools
            nix

            # Utilities
            coreutils  # includes timeout command
            bash
            curl
            jq
            netcat
            openssh

            # Process management utilities
            procps    # includes pgrep, pkill
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            # macOS specific packages if needed
          ];

          shellHook = ''
            # Point the Docker CLI to the socket managed by Colima
            export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
            echo "✅ DOCKER_HOST automatically set to Colima's socket."
            echo
            echo "Pi-hole RPi4 Image Builder Environment"
            echo "======================================"
            echo
            echo "Available commands:"
            echo "  ./builder/make-image.sh   - Build the RPi4 image using remote builder"
            echo "  ./builder/setup-remote-builder.sh - Set up Colima remote builder"
            echo "  ./builder/test-remote-builder.sh  - Test remote builder functionality"
            echo
            echo "Quick start:"
            echo "  ./builder/make-image.sh"
            echo
          '';
        };
      })) // rec {
    # Keep the original nixosConfigurations and images at the top level  
    nixosConfigurations.rpi4 = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ./sdimage.nix
        userConfig
        ./configuration.nix
      ];
    };
    
    images.rpi4 = nixosConfigurations.rpi4.config.system.build.sdImage;

    # Docker image for the remote builder using nixpkgs.dockerTools
    images.remote-builder = 
      let
        pkgs-aarch64 = import nixpkgs { 
          system = "aarch64-linux"; 
          config = { allowUnfree = true; };
        };
      in
      pkgs-aarch64.dockerTools.buildImage {
        name = "nix-remote-builder";
        tag = "latest";
        
        contents = with pkgs-aarch64; [
          # Essential system packages
          busybox  # Provides basic shell and utilities
          nix
          openssh
          shadow   # For user management
          systemd  # For service management
          
          # Development tools commonly needed for building
          git
          curl
          bash
          coreutils
          findutils
          gnugrep
          gnused
          gawk
          which
        ];

        # Set up the basic container configuration
        config = {
          Env = [
            "PATH=/run/wrappers/bin:/root/.nix-profile/bin:/etc/profiles/per-user/root/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
            "NIX_SSL_CERT_FILE=${pkgs-aarch64.cacert}/etc/ssl/certs/ca-bundle.crt"
          ];
          ExposedPorts = {
            "22/tcp" = {};
          };
          Cmd = [ "/bin/init-container.sh" ];
        };

        # Create the initialization script
        runAsRoot = ''
          #!${pkgs-aarch64.runtimeShell}
          
          # Create essential directories
          mkdir -p /root/.ssh /etc/ssh /run/sshd /var/log /var/empty /nix/var/nix/daemon-socket
          
          # Generate SSH host keys
          ${pkgs-aarch64.openssh}/bin/ssh-keygen -t rsa -b 2048 -f /etc/ssh/ssh_host_rsa_key -N ""
          ${pkgs-aarch64.openssh}/bin/ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N ""
          ${pkgs-aarch64.openssh}/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
          
          # Create sshd_config
          cat > /etc/ssh/sshd_config << 'EOF'
          Port 22
          AddressFamily any
          ListenAddress 0.0.0.0
          
          HostKey /etc/ssh/ssh_host_rsa_key
          HostKey /etc/ssh/ssh_host_ecdsa_key
          HostKey /etc/ssh/ssh_host_ed25519_key
          
          PermitRootLogin yes
          PasswordAuthentication no
          PubkeyAuthentication yes
          AuthorizedKeysFile .ssh/authorized_keys
          
          UsePAM no
          X11Forwarding no
          PrintMotd no
          AcceptEnv LANG LC_*
          Subsystem sftp ${pkgs-aarch64.openssh}/libexec/sftp-server
          EOF
          
          # Create nix.conf with remote builder settings
          mkdir -p /etc/nix
          cat > /etc/nix/nix.conf << 'EOF'
          experimental-features = nix-command flakes
          trusted-users = root
          auto-optimise-store = true
          substituters = https://cache.nixos.org/
          trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
          EOF
          
          # Create the container initialization script
          cat > /bin/init-container.sh << 'EOF'
          #!/bin/sh
          set -e
          
          echo "Starting Nix Remote Builder Container..."
          
          # Start the Nix daemon in the background
          echo "Starting Nix daemon..."
          ${pkgs-aarch64.nix}/bin/nix-daemon &
          
          # Wait a moment for the daemon to start
          sleep 2
          
          # Start SSH daemon
          echo "Starting SSH daemon..."
          exec ${pkgs-aarch64.openssh}/bin/sshd -D -e
          EOF
          
          chmod +x /bin/init-container.sh
        '';
      };

    packages.aarch64-linux.nixosConfigurations."${hostname}" = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./filesystems.nix
        userConfig
        ./configuration.nix
      ];
    };
  };
}
