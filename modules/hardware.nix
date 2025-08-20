# Hardware-specific configuration module
# Contains hardware settings and optimizations

{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    pihole.hardware = {
      enable = mkEnableOption "hardware-specific configuration";
      
      bluetooth = {
        powerOnBoot = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to power on Bluetooth at boot";
        };
      };
    };
  };

  config = mkIf config.pihole.hardware.enable {
    hardware.bluetooth.powerOnBoot = config.pihole.hardware.bluetooth.powerOnBoot;
  };
}