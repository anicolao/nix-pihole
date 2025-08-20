# Generic user management module
# This module provides a template for user configuration
# Personal user configurations are imported directly in flake.nix

{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    pihole.users = {
      enable = mkEnableOption "user management";
    };
  };

  config = mkIf config.pihole.users.enable {
    # Default minimal user setup - personal config imported separately in flake.nix
    users.users.root = mkDefault {
      openssh.authorizedKeys.keys = mkDefault [];
    };
  };
}