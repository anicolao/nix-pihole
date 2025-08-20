{
  pkgs,
  ...
}:
let
  secrets = import ./secrets.nix;
in
{
  nixpkgs.config.allowUnfree = true;
  time.timeZone = "America/Toronto";
  i18n.defaultLocale = "en_US.UTF-8";

  boot = {
    kernelParams = ["console=tty1" "console=ttyS0,115200"];
    loader.grub.enable = false;
    loader.generic-extlinux-compatible.enable = true;
  };
  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    serviceConfig.Restart = "always"; # restart when session is closed
  };

  services = {
    openssh = {
      enable = true;
      settings.PermitUserRC = true;
    };
  };
  programs.zsh.enable = true;
  services.ntp.enable = true;
  systemd.services.pihole-ftl.after = [ "openssh.service" ];
  systemd.services.pihole-ftl-log-deleter = {
    after = [ "pihole-ftl.service" ];
    requires = [ "pihole-ftl.service" ];
    script =
      #let
        #cfg = nixpkgs.config.services.pihole-ftl;
        #database = "${cfg.stateDirectory}/pihole-FTL.db";
      #in 
      pkgs.lib.mkBefore ''
        if [ ! -f "/var/lib/pihole/pihole-FTL.db" ]; then
          exit 0;
        fi
      '';
  };
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
        interface = "end0";
        listeningMode = "BIND";
        upstreams = ["8.8.8.8"];
      };
      dhcp = {
        active = false;
      };
      #dhcp = {
      #active = true;
      #router = "192.168.10.1";
      #start = "192.168.10.2";
      #end = "192.168.10.254";
      #leaseTime = "1d";
      #ipv6 = true;
      #multiDNS = true;
      #hosts = [
      # Static address for the current host
      #"aa:bb:cc:dd:ee:ff,192.168.10.1,${config.networking.hostName},infinite"
      #];
      #rapidCommit = true;
      #};
      #misc.dnsmasq_lines = [
      # This DHCP server is the only one on the network
      #"dhcp-authoritative"
      # Source: https://data.iana.org/root-anchors/root-anchors.xml
      #"trust-anchor=.,38696,8,2,683D2D0ACB8C9B712A1948B27F741219298D0A450D612C483AF444A4C0FB2B16"
      #];
    };
  };
  services.pihole-web = {
    enable = true;
    ports = ["8080"];
  };
  environment.systemPackages = with pkgs; [
    cron
    fzf
    gcc
    gh
    git
    gnumake
    home-manager
    killall
    neovim
    ookla-speedtest
    pihole-ftl
    pihole-web
    pihole
    ripgrep
    tmux
    wireguard-tools
    zsh
  ];
  nix = {
    # Necessary for using flakes on this system.
    settings.experimental-features = "nix-command flakes";
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
  system = {
    stateVersion = "24.11";
  };
  #services.nginx = {
  #    enable = true;
  #};
  networking = {
    wireless = {
      enable = true;
      networks."${secrets.wifi.networkName}".psk = secrets.wifi.password;
      interfaces = ["wlan0"];
    };
    #useDHCP = false;
    firewall.enable = true;
    firewall.allowedTCPPorts = [22 80 443 5173 5174 8080];
    hostName = "pihole";
  };
  hardware.bluetooth.powerOnBoot = false;
}
