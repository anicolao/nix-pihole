{
  description = "Pi-hole RPi4 Image Builder with Remote Builder Support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        hostname = "pihole";
        # Use personal configuration if it exists, otherwise fall back to default
        userConfig = if builtins.pathExists ./personal/alex_users.nix 
          then ./personal/alex_users.nix 
          else ./default-users.nix;
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
      }) // {
    # Keep the original nixosConfigurations and images at the top level  
    nixosConfigurations.rpi4 = let
      hostname = "pihole";
      userConfig = if builtins.pathExists ./personal/alex_users.nix 
        then ./personal/alex_users.nix 
        else ./default-users.nix;
    in nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ./sdimage.nix
        userConfig
        ./configuration.nix
      ];
    };
    
    images.rpi4 = nixosConfigurations.rpi4.config.system.build.sdImage;

    packages.aarch64-linux.nixosConfigurations."pihole" = let
      userConfig = if builtins.pathExists ./personal/alex_users.nix 
        then ./personal/alex_users.nix 
        else ./default-users.nix;
    in nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./filesystems.nix
        userConfig
        ./configuration.nix
      ];
    };
  };
}
