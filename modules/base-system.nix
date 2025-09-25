# Base system configuration module
# Contains fundamental system settings like boot, locale, services, and packages
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options = {
    pihole.baseSystem = {
      enable = mkEnableOption "base system configuration";

      timeZone = mkOption {
        type = types.str;
        default = "America/Toronto";
        description = "System timezone";
      };

      locale = mkOption {
        type = types.str;
        default = "en_US.UTF-8";
        description = "System locale";
      };

      packages = {
        essential = mkOption {
          type = types.listOf types.package;
          default = with pkgs; [
            git
            neovim
            tmux
            zsh
          ];
          description = "Essential system packages";
        };

        development = mkOption {
          type = types.listOf types.package;
          default = with pkgs; [
            gcc
            gnumake
            gh
            ripgrep
            fzf
            home-manager
          ];
          description = "Development packages";
        };

        utilities = mkOption {
          type = types.listOf types.package;
          default = with pkgs; [
            cron
            killall
            ookla-speedtest
            wireguard-tools
          ];
          description = "System utility packages";
        };
      };
    };
  };

  config = mkIf config.pihole.baseSystem.enable {
    # Allow unfree packages
    nixpkgs.config.allowUnfree = true;

    # System locale and timezone
    time.timeZone = config.pihole.baseSystem.timeZone;
    i18n.defaultLocale = config.pihole.baseSystem.locale;

    # Boot configuration for ARM devices
    boot = {
      kernelParams = ["console=tty1" "console=ttyS0,115200" "net.ifnames=0"];
      loader.grub.enable = false;
      loader.generic-extlinux-compatible.enable = true;
    };

    # Serial console support
    systemd.services."serial-getty@ttyS0" = {
      enable = true;
      serviceConfig.Restart = "always"; # restart when session is closed
    };

    # Essential services
    services = {
      openssh = {
        enable = true;
        settings.PermitUserRC = true;
      };
      ntp.enable = true;
    };

    # Enable zsh globally
    programs.zsh.enable = true;

    # System packages
    environment.systemPackages =
      config.pihole.baseSystem.packages.essential
      ++ config.pihole.baseSystem.packages.development
      ++ config.pihole.baseSystem.packages.utilities;

    # Nix configuration
    nix = {
      # Necessary for using flakes on this system.
      settings.experimental-features = "nix-command flakes";
      extraOptions = ''
        experimental-features = nix-command flakes
      '';
    };

    # System state version
    system = {
      stateVersion = "24.11";
    };
  };
}

