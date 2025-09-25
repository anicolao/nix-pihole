{
  description = "Build Raspberry Pi images for Pi 3B+ and Pi 4";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };
  outputs = {nixpkgs, ...}: let
    hostname = "pihole";
    # Use personal configuration if it exists, otherwise fall back to default
    userConfig =
      if builtins.pathExists ./personal/users.nix
      then ./personal/users.nix
      else ./default-users.nix;
  in rec {
    nixosConfigurations.pihole = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ./sdimage.nix
        userConfig
        ./configuration.nix
      ];
    };
    images.pihole = nixosConfigurations.pihole.config.system.build.sdImage;

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
