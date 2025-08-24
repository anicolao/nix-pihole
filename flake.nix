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
    
    # Support building from multiple host systems via packages interface
    systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    
    # Create the RPI4 NixOS system (always aarch64-linux for Raspberry Pi)
    rpi4System = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ./sdimage.nix
        userConfig
        ./configuration.nix
        # Configure nixpkgs to allow unfree packages
        {
          nixpkgs.config.allowUnfree = true;
        }
      ];
    };
  in rec {
    # For backward compatibility, provide a default rpi4 configuration
    nixosConfigurations.rpi4 = rpi4System;

    # Make the image available directly at top level for cross-compilation
    # Nix will handle cross-compilation automatically when building from different host systems
    images.rpi4 = rpi4System.config.system.build.sdImage;

    # Provide the image as a package on all systems for cross-compilation
    packages = forAllSystems (system: {
      rpi4-image = rpi4System.config.system.build.sdImage;
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
