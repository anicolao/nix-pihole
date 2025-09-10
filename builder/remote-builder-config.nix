# NixOS configuration for remote builder container
{ config, pkgs, ... }:

{
  imports = [
    # Import the container base configuration
    "${pkgs.path}/nixos/modules/virtualisation/docker-image.nix"
  ];

  # Enable the OpenSSH daemon
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
    };
    ports = [ 22 ];
  };

  # Enable nix daemon and configure it for remote building
  nix = {
    enable = true;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" ];
      auto-optimise-store = true;
    };
  };

  # Create the root user with an empty password (key-based auth only)
  users.users.root = {
    openssh.authorizedKeys.keys = [
      # This will be replaced at runtime with the actual public key
      "ssh-ed25519 PLACEHOLDER_KEY nix-remote-builder"
    ];
  };

  # Required packages for the remote builder
  environment.systemPackages = with pkgs; [
    nix
    git
    curl
    openssh
    bashInteractive
  ];

  # Network configuration
  networking = {
    hostName = "nix-remote-builder";
    firewall.allowedTCPPorts = [ 22 ];
  };

  # System configuration
  system.stateVersion = "23.11";

  # Container-specific configuration
  virtualisation.docker = {
    enable = false; # We don't need docker inside the container
  };

  # Make sure essential services start
  systemd.services.sshd.wantedBy = [ "multi-user.target" ];
}