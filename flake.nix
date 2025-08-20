{
  description = "Build Raspberry PI 4 image";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };
  outputs = {nixpkgs, ...}: let
    hostname = "pihole";
  in rec {
    nixosConfigurations.rpi4 = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ./sdimage.nix
        ./alex_users.nix
        ./configuration.nix
      ];
    };
    images.rpi4 = nixosConfigurations.rpi4.config.system.build.sdImage;

    packages.aarch64-linux.nixosConfigurations."${hostname}" = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./filesystems.nix
        ./alex_users.nix
        ./configuration.nix
      ];
    };
  };
}
