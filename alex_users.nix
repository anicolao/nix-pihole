{pkgs, ...}: let
  secrets = import ./secrets.nix;
in {
  users.users.root = {
    initialHashedPassword = secrets.rootPassword;
    openssh.authorizedKeys.keys = secrets.sshKeys.users;
  };
  users.extraUsers.anicolao = {
    createHome = true;
    home = "/home/anicolao";
    description = "anicolao";
    group = "users";
    extraGroups = ["wheel" "dialout"];
    shell = pkgs.zsh;
    isSystemUser = true;
    initialHashedPassword = secrets.rootPassword;
    openssh.authorizedKeys.keys = secrets.sshKeys.users;
  };
}
