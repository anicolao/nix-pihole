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
            sshpass
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
            echo "  ./make-image.sh   - Build the RPi4 image using remote builder"
            echo "  ./setup-remote-builder.sh - Set up Colima remote builder"
            echo "  ./test-remote-builder.sh  - Test remote builder functionality"
            echo
            echo "Quick start:"
            echo "  ./make-image.sh"
            echo
          '';
        };
      });
}
