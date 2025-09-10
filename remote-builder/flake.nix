{
  description = "A remote aarch64-linux builder environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # The system architecture for our remote builder.
      builderSystem = "aarch64-linux";

      # Create a NixOS system configuration for our builder.
      nixosBuilder = nixpkgs.lib.nixosSystem {
        system = builderSystem;
        modules = [ ./builder.nix ];
      };
    in
    {
      # The package that builds the Docker image for our builder.
      packages.${builderSystem}.builder-image = nixosBuilder.config.system.build.dockerImage;

      # A default alias for convenience.
      packages.${builderSystem}.default = self.packages.${builderSystem}.builder-image;
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # The development shell for the host machine.
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            colima
            docker
            docker-compose
            nix
            coreutils
            bash
            curl
            jq
            netcat
            openssh
            procps
            sshpass
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            # macOS specific packages if needed
          ];

          shellHook = ''
            export DOCKER_HOST="unix://$HOME/.colima/remote-builder/docker.sock"
            echo "✅ DOCKER_HOST automatically set to the 'remote-builder' profile's socket."
            echo
            echo "Remote Builder Environment"
            echo "=========================="
            echo
            echo "Available commands:"
            echo "  ./setup-remote-builder.sh - Build and set up the remote builder"
            echo "  ./test-remote-builder.sh  - Test remote builder functionality"
            echo "  ./make-image.sh   - Build the RPi4 image using the remote builder"
            echo
            echo "Quick start:"
            echo "  ./setup-remote-builder.sh"
            echo
          '';
        };
      });
}
