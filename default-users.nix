# default-users.nix 
# Default user configuration when personal/alex_users.nix doesn't exist
# This provides minimal functionality for the system to work

{ pkgs, ... }:

{
  users.users.root = {
    # Default empty password - users should set up their own secrets
    initialHashedPassword = "";
    openssh.authorizedKeys.keys = [];
  };
}