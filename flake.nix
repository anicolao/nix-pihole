{
  description = "Build Raspberry PI 4 image";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };
  outputs = {nixpkgs, ...}: let
    hostname = "pihole";
    # Use personal configuration if it exists, otherwise fall back to default
    userConfig = if builtins.pathExists ./personal/alex_users.nix 
      then ./personal/alex_users.nix 
      else ./default-users.nix;
    
    # Support cross-compilation from multiple host systems
    systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    
    # Create the RPI4 image with proper cross-compilation support
    mkRpi4Image = system: let
      pkgs = import nixpkgs {
        inherit system;
        crossSystem = {
          config = "aarch64-unknown-linux-gnu";
          system = "aarch64-linux";
        };
        config = {
          allowUnfree = true;
        };
      };
    in nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      pkgs = pkgs;
      modules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ./sdimage.nix
        userConfig
        ./configuration.nix
      ];
    };
  in rec {
    # For backward compatibility, provide a default rpi4 configuration
    nixosConfigurations.rpi4 = mkRpi4Image "aarch64-linux";

    # Make the image available directly at top level for cross-compilation
    # Use the current system for cross-compilation
    images.rpi4 = (mkRpi4Image builtins.currentSystem).config.system.build.sdImage;

    packages = forAllSystems (system: {
      # Provide the image as a package for easy building
      rpi4-image = (mkRpi4Image system).config.system.build.sdImage;
    }) // {
      aarch64-linux.nixosConfigurations."${hostname}" = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./filesystems.nix
          userConfig
          ./configuration.nix
        ];
      };
    };
  };
}
