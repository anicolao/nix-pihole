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
  in rec {
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
