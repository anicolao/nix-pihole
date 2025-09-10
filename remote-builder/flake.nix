{
  description = "A remote aarch64-linux builder environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        builderSystem = "aarch64-linux";
      in
      {
        # The development shell is available on all supported host systems.
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
      } // (
        # The builder package is only defined for the aarch64-linux system.
        if system == builderSystem then
          let
            nixosBuilder = nixpkgs.lib.nixosSystem {
              system = builderSystem;
              modules = [
                ./builder.nix
                # We explicitly pass the nixpkgs flake input as a special argument
                # to our modules. This allows us to refer to it in a way that
                # is guaranteed to not depend on `config`, breaking the
                # infinite recursion.
                { _module.args = { flake-nixpkgs = nixpkgs; }; }
              ];
            };
          in
          {
            packages = {
              builder-image = nixosBuilder.config.system.build.dockerImage;
              default = self.packages.${system}.builder-image;
            };
          }
        else {}
      )
    );
}
