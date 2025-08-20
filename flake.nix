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
      
    # Helper to create nixpkgs with cross-compilation support
    mkNixpkgs = system: import nixpkgs {
      inherit system;
      config.allowUnsupportedSystem = true;
    };
  in rec {
    nixosConfigurations.rpi4 = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ./sdimage.nix
        userConfig
        ./configuration.nix
        # Enable cross-compilation support
        { nixpkgs.config.allowUnsupportedSystem = true; }
      ];
    };
    images.rpi4 = nixosConfigurations.rpi4.config.system.build.sdImage;

    # Make packages available for common build systems
    packages.x86_64-linux = {
      # Allow building the RPi4 image from x86_64-linux
      rpi4-image = nixosConfigurations.rpi4.config.system.build.sdImage;
      nixosConfigurations."${hostname}" = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./filesystems.nix
          userConfig
          ./configuration.nix
          { nixpkgs.config.allowUnsupportedSystem = true; }
        ];
      };
    };

    packages.aarch64-linux = {
      # Native aarch64-linux packages
      rpi4-image = nixosConfigurations.rpi4.config.system.build.sdImage;
      nixosConfigurations."${hostname}" = nixpkgs.lib.nixosSystem {
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
