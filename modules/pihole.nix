# Pi-hole DNS filtering configuration
# This module contains all Pi-hole specific settings
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options = {
    pihole.service = {
      enable = mkEnableOption "Pi-hole DNS filtering service";

      interface = mkOption {
        type = types.str;
        default = "eth0";
        description = "Network interface for Pi-hole to bind to";
      };

      upstreamDNS = mkOption {
        type = types.listOf types.str;
        default = ["8.8.8.8"];
        description = "Upstream DNS servers";
      };

      webPort = mkOption {
        type = types.str;
        default = "8080";
        description = "Port for Pi-hole web interface";
      };
    };
  };

  config = mkIf config.pihole.service.enable {
    # Custom systemd service for Pi-hole log management
    systemd.services.pihole-ftl.after = ["sshd.service"];
    systemd.services.pihole-ftl-log-deleter = {
      after = ["pihole-ftl.service"];
      requires = ["pihole-ftl.service"];
      script = pkgs.lib.mkBefore ''
        if [ ! -f "/var/lib/pihole/pihole-FTL.db" ]; then
          exit 0;
        fi
      '';
    };

    # Pi-hole FTL service configuration
    services.pihole-ftl = {
      enable = true;
      openFirewallDNS = true;
      openFirewallDHCP = true;
      queryLogDeleter.enable = true;
      lists = [
        {
          url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
          # Alternatively, use the file from nixpkgs. Note its contents won't be
          # automatically updated by Pi-hole, as it would with an online URL.
          # url = "file://${pkgs.stevenblack-blocklist}/hosts";
          description = "Steven Black's unified adlist";
        }
      ];
      settings = {
        dns = {
          domainNeeded = true;
          expandHosts = true;
          interface = config.pihole.service.interface;
          listeningMode = "BIND";
          upstreams = config.pihole.service.upstreamDNS;
        };
        dhcp = {
          active = false;
        };
      };
    };

    # Pi-hole web interface
    services.pihole-web = {
      enable = true;
      ports = [config.pihole.service.webPort];
    };

    # Pi-hole related packages
    environment.systemPackages = with pkgs; [
      pihole-ftl
      pihole-web
      pihole
    ];
  };
}
