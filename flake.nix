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
    
    # Create a function to build the RPI4 image with proper cross-compilation support
    mkRpi4Image = hostSystem: let
      pkgs = import nixpkgs {
        system = hostSystem;
        crossSystem = nixpkgs.lib.systems.examples.aarch64-multiplatform;
        config = {
          allowUnfree = true;
        };
      };
    in nixpkgs.lib.nixosSystem {
      inherit pkgs;
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

    # Make the image available directly with cross-compilation support
    # Use the current system for cross-compilation
    images.rpi4 = (mkRpi4Image (builtins.currentSystem or "x86_64-linux")).config.system.build.sdImage;

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
