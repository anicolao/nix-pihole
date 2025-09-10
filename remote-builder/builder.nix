# remote-builder/builder.nix
# We accept `docker-image-module-path` as a special argument passed from our flake.
{ config, pkgs, docker-image-module-path, ... }:

{
  # This configuration defines a minimal NixOS system that will run inside
  # a Docker container. It's designed to be a remote builder.

  # Import container-specific settings from nixpkgs.
  # We import the module using the path passed as a special argument,
  # which is the most robust way to avoid dependency cycles.
  imports = [
    docker-image-module-path
  ];

  system.stateVersion = "23.11"; # Or a more recent version if available.

  # === Docker Image Configuration ===
  # Set a predictable name and tag for the Docker image.
  dockerImage.name = "nixos-remote-builder";
  dockerImage.tag = "latest";

  # === SSH Server Configuration ===
  services.openssh = {
    enable = true;
    # Allow password authentication for simplicity.
    passwordAuthentication = true;
    # For security, we don't allow root to log in via SSH.
    permitRootLogin = "no";
  };

  # === User Configuration ===
  # Create a 'nixos' user that we can ssh into.
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # For sudo access.
    initialPassword = "nixos"; # Set a simple password.
  };

  # === Nix Daemon Configuration ===
  nix = {
    # The 'nixos' user needs to be a trusted user to perform builds.
    settings.trusted-users = [ "root" "nixos" ];
    # Add necessary experimental features.
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # === System Packages ===
  # It's good practice to have some basic tools available.
  environment.systemPackages = with pkgs; [
    vim
    git
  ];

  # === Firewall ===
  # Ensure the SSH port is open inside the container.
  networking.firewall.allowedTCPPorts = [ 22 ];
}
