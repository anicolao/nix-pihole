# NixOS Pi-hole Configuration

A NixOS configuration for setting up a Pi-hole DNS sinkhole on a Raspberry Pi 4, providing network-wide ad blocking and DNS filtering.

## Overview

This repository contains a complete NixOS configuration that transforms a Raspberry Pi 4 into a dedicated Pi-hole server. Pi-hole acts as a DNS sinkhole, blocking advertisements and tracking domains at the network level, providing faster browsing and enhanced privacy for all devices on your network.

## Features

- **Pi-hole DNS Filtering**: Blocks ads and trackers using curated blocklists
- **Web Interface**: Accessible on port 8080 for management and statistics
- **SSH Access**: Remote administration with key-based authentication
- **WiFi Connectivity**: Wireless network configuration included
- **Automatic Updates**: Configured to use NixOS unstable channel
- **Optimized for Pi**: Serial console support and ARM64 optimization

## Repository Structure

```
├── flake.nix           # Main Nix flake configuration with build targets
├── configuration.nix   # Main system configuration (imports modules)
├── default-users.nix   # Default user configuration fallback
├── filesystems.nix     # Filesystem mount configuration
├── sdimage.nix         # SD card image build settings
├── modules/            # Modular configuration components
│   ├── base-system.nix # Basic system settings (boot, locale, packages)
│   ├── pihole.nix      # Pi-hole specific configuration
│   ├── networking.nix  # Network and firewall settings  
│   ├── hardware.nix    # Hardware-specific settings
│   └── users.nix       # User management module
├── templates/          # Configuration templates for customization
│   ├── secrets.nix.example  # WiFi credentials and SSH keys template
│   ├── users.nix.example    # User accounts template
│   └── wifi.nix.example     # WiFi configuration template
├── personal/           # Personal configurations (gitignored)
│   └── README.md       # Instructions for personal configuration
└── flake.lock          # Dependency lock file
```

## Prerequisites

- **Hardware**: Raspberry Pi 4 with microSD card (8GB+ recommended)
- **Software**: NixOS system with flakes enabled
- **Network**: WiFi credentials or ethernet connection

## Quick Start

### 1. Configuration Setup

Before building the image, you need to set up your personal configuration:

```bash
# Clone the repository
git clone https://github.com/anicolao/nix-pihole.git
cd nix-pihole

# Copy templates to create your personal configuration
cp templates/secrets.nix.example personal/secrets.nix
cp templates/users.nix.example personal/alex_users.nix

# Edit the secrets file with your actual values
nano personal/secrets.nix  # Add your WiFi credentials and SSH keys

# Optionally customize your user configuration
nano personal/alex_users.nix  # Modify usernames and settings as needed
```

**Important**: Edit `personal/secrets.nix` to include:
- Your WiFi network name and password
- Your SSH public key for secure access
- A hashed password for the root user

### 2. Building an SD Card Image

To create a bootable SD card image for your Raspberry Pi 4:

```bash
# Build the SD card image
nix build path:$PWD#images.rpi4

# Flash the image to your SD card
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress
```

### 3. Initial Setup

1. Insert the SD card into your Raspberry Pi 4
2. Power on the device
3. The system will automatically connect to the configured WiFi network
4. Find the Pi's IP address on your network
5. SSH into the device: `ssh root@<pi-ip-address>`

### 4. Pi-hole Configuration

After boot, Pi-hole will be available at:
- **Web Interface**: `http://<pi-ip-address>:8080/admin`
- **DNS Server**: Configure your router to use `<pi-ip-address>` as the primary DNS

## Configuration Details

### DNS Settings

The Pi-hole is configured with:
- **Upstream DNS**: Google DNS (8.8.8.8)
- **Interface Binding**: Binds to `end0` interface
- **Blocklists**: Steven Black's unified hosts file for ad blocking

### Network Configuration

- **Hostname**: `pihole`
- **WiFi**: Configured for "SnoopyNet" network (update in `configuration.nix`)
- **Firewall**: Opens ports 22 (SSH), 80/443 (HTTP/HTTPS), 8080 (Pi-hole web)
- **DNS Ports**: 53 (UDP/TCP) automatically opened by Pi-hole service

### User Accounts

- **root**: System administrator with SSH key access
- **anicolao**: Additional user account with sudo privileges

## Customization

### Module-Based Configuration

The configuration is now organized into modules that can be customized through options in `configuration.nix`:

```nix
pihole = {
  # Pi-hole service options
  service = {
    enable = true;
    interface = "end0";           # Network interface for Pi-hole
    upstreamDNS = ["8.8.8.8"];   # DNS servers
    webPort = "8080";             # Web interface port
  };
  
  # Networking options
  networking = {
    enable = true;
    hostName = "pihole";
    wifi.enable = true;           # Set to false for ethernet-only
    firewall.allowedTCPPorts = [22 80 443 8080];
  };
  
  # Base system options
  baseSystem = {
    enable = true;
    timeZone = "America/Toronto";
    locale = "en_US.UTF-8";
  };
};
```

### Personal Configuration

Personal settings like users and WiFi credentials are stored in the `personal/` directory:

1. **WiFi and Secrets**: Edit `personal/secrets.nix`
   ```nix
   {
     wifi = {
       networkName = "YOUR_NETWORK";
       password = "YOUR_PASSWORD";
     };
     # ... SSH keys and passwords
   }
   ```

2. **User Accounts**: Edit `personal/alex_users.nix` or copy from `templates/users.nix.example`

### Advanced Customization

#### Adding Custom Blocklists

Edit the Pi-hole lists in `modules/pihole.nix` or override in `configuration.nix`:

```nix
services.pihole-ftl.lists = [
  {
    url = "https://example.com/custom-blocklist.txt";
    description = "My custom blocklist";
  }
];
```

#### Ethernet-Only Setup

For wired-only deployments, disable WiFi:

```nix
pihole.networking.wifi.enable = false;
```

#### Different Hardware Platforms

Change the network interface for different hardware:

```nix
pihole.service.interface = "eth0";  # For Raspberry Pi ethernet
```

## Building and Testing

### Local Development

```bash
# Check flake configuration
nix flake check

# Build the system configuration
nix build .#nixosConfigurations.rpi4.config.system.build.toplevel

# Build just the SD image
nix build path:$PWD#images.rpi4
```

### Updating Dependencies

```bash
# Update flake inputs
nix flake update

# Rebuild with new dependencies
nix build path:$PWD#images.rpi4
```

## Troubleshooting

### Common Issues

1. **WiFi not connecting**: Verify network name and password in `configuration.nix`
2. **Pi-hole web interface not accessible**: Check firewall settings and port 8080
3. **DNS not resolving**: Ensure Pi-hole service is running and ports 53 are open
4. **SSH connection refused**: Verify SSH service is enabled and port 22 is open

### Logs and Diagnostics

```bash
# Check Pi-hole service status
systemctl status pihole-ftl

# View Pi-hole logs
journalctl -u pihole-ftl -f

# Check network connectivity
ping 8.8.8.8

# Verify DNS resolution
nslookup google.com localhost
```

## Security Considerations

- SSH is configured with key-based authentication only
- WiFi credentials are stored in plain text (see TODO.md for improvements)
- Firewall is enabled with minimal required ports open
- Regular NixOS updates recommended for security patches

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test the configuration builds successfully
5. Submit a pull request

## License

This configuration is provided as-is for educational and personal use. Please review and customize according to your specific needs and security requirements.

## Related Resources

- [Pi-hole Documentation](https://docs.pi-hole.net/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [NixOS on ARM](https://nixos.wiki/wiki/NixOS_on_ARM)
- [Raspberry Pi 4 Setup](https://nixos.wiki/wiki/NixOS_on_ARM/Raspberry_Pi_4)