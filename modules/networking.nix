# Network configuration module
# Handles WiFi, firewall, and network interface settings

{ config, lib, pkgs, ... }:

with lib;

let
  # Import secrets if available, otherwise use empty defaults  
  secrets = if builtins.pathExists ../personal/secrets.nix 
    then import ../personal/secrets.nix 
    else if builtins.pathExists ../secrets.nix
    then import ../secrets.nix
    else {
      wifi = { networkName = ""; password = ""; };
    };
in

{
  options = {
    pihole.networking = {
      enable = mkEnableOption "network configuration";
      
      hostName = mkOption {
        type = types.str;
        default = "pihole";
        description = "System hostname";
      };
      
      wifi = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable WiFi networking";
        };
        
        interface = mkOption {
          type = types.str;
          default = "wlan0";
          description = "WiFi interface name";
        };
      };
      
      firewall = {
        allowedTCPPorts = mkOption {
          type = types.listOf types.int;
          default = [22 80 443 5173 5174 8080];
          description = "List of allowed TCP ports";
        };
      };
    };
  };

  config = mkIf config.pihole.networking.enable {
    networking = {
      hostName = config.pihole.networking.hostName;
      firewall = {
        enable = true;
        allowedTCPPorts = config.pihole.networking.firewall.allowedTCPPorts;
      };
    } // optionalAttrs (config.pihole.networking.wifi.enable && secrets.wifi.networkName != "") {
      wireless = {
        enable = true;
        networks."${secrets.wifi.networkName}".psk = secrets.wifi.password;
        interfaces = [config.pihole.networking.wifi.interface];
      };
    };
  };
}