# Main configuration file - now modularized
# This file imports and configures the various system modules
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Import all modules
  imports = [
    ./modules/base-system.nix
    ./modules/pihole.nix
    ./modules/networking.nix
    ./modules/hardware.nix
    ./modules/users.nix
  ];

  # Enable all modules with default configuration
  pihole = {
    baseSystem.enable = true;
    service.enable = true;
    networking.enable = true;
    hardware.enable = true;
    users.enable = true;
  };

  boot.kernelParams = ["console=ttyAMA0,115200"];
  boot.initrd.compressor = "gzip";

  # Module-specific customizations can be done here
  # For example:
  # pihole.service.interface = "eth0";  # Override default interface
  # pihole.baseSystem.timeZone = "UTC";  # Override default timezone
}
