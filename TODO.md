# TODO: Nix Configuration Cleanup

This document outlines suggested improvements and cleanup tasks for the
nix-pihole repository to make it more maintainable, secure, and reusable.

## Configuration Structure Improvements

### 🟡 Modularization and Reusability

- [ ] **Separate Personal Configuration from System Configuration**

  - Issue: `alex_users.nix` contains personal user account and SSH keys
  - Solution: Create a generic `users.nix` template and move personal config to
    `personal/` directory
  - Files to create:
    - `modules/users.nix` (generic user management)
    - `personal/alex_users.nix` (personal configuration)
    - `personal/secrets.nix` (personal secrets - gitignored)

- [ ] **Create a Configuration Template System**

  - Create `template/` directory with:
    - `template/users.nix.example`
    - `template/wifi.nix.example`
    - `template/secrets.nix.example`
  - Add instructions for copying and customizing templates

- [ ] **Split `configuration.nix` into Logical Modules**
  - `modules/pihole.nix` - Pi-hole specific configuration
  - `modules/networking.nix` - Network and firewall settings
  - `modules/base-system.nix` - Basic system configuration
  - `modules/hardware.nix` - Hardware-specific settings

### 🟡 Network Configuration Issues

- [ ] **Make Network Interface Name Configurable**

  - Currently: `interface = "end0";` in DNS settings (hardcoded for Orange Pi
    Zero 3)
  - Solution: Make interface name configurable to support different hardware
    platforms
  - Impact: Better hardware compatibility and flexibility

- [ ] **Make Network Configuration Flexible**
  - Add options for ethernet vs WiFi-only setups
  - Make WiFi network selection configurable
  - Add option to disable WiFi if using ethernet only

## Code Quality and Maintenance

### 🟡 Remove Dead Code

- [ ] **Clean Up Commented Code Blocks**

  - Large commented DHCP configuration block (lines 67-86 in
    `configuration.nix`)
  - Commented nginx configuration (lines 122-124)
  - Commented DNS anchor configuration (lines 84-86)
  - Decision: Either remove or move to examples/documentation

- [ ] **Use Variables in systemd Service Paths**
  - `systemd.services.pihole-ftl-log-deleter` is working but uses hardcoded
    paths
  - Solution: Replace hardcoded database directory path with variables
  - Impact: Better maintainability and configuration flexibility

### 🟡 Configuration Improvements

- [ ] **Fix Duplicate Nix Settings**

  - Lines 114-117 in `configuration.nix` duplicate experimental-features
  - Consolidate into single configuration block

- [ ] **Improve Package Management**

  - Many packages in `environment.systemPackages` may not be necessary for a
    Pi-hole server
  - Separate into categories: essential, development, optional
  - Consider making some packages optional via configuration flags

- [ ] **Add Configuration Validation**
  - Add assertions to validate network interface exists
  - Validate WiFi configuration completeness
  - Check for required secrets before building

## Documentation and Examples

### 🟢 Documentation Improvements

- [ ] **Add Inline Documentation**

  - Document why specific packages are needed
  - Explain custom systemd services
  - Add comments for non-obvious configuration choices

- [ ] **Create Configuration Examples**

  - `examples/ethernet-only.nix`
  - `examples/multiple-wifi-networks.nix`
  - `examples/dhcp-enabled.nix`
  - `examples/custom-blocklists.nix`

- [ ] **Add Build and Deployment Scripts**
  - `scripts/build-image.sh` - Automate SD card image creation
  - `scripts/deploy.sh` - Deploy configuration updates to running system
  - `scripts/setup-secrets.sh` - Help users set up secret management

## Advanced Features and Improvements

### 🟢 Enhancement Opportunities

- [ ] **Implement Proper Secrets Management**

  - Use `agenix` or `sops-nix` for encrypting secrets
  - Add secret rotation capabilities
  - Document secret management workflow

- [ ] **Add Configuration Options**

  - Create a `options.nix` file defining configurable parameters
  - Allow enabling/disabling features via options
  - Make the configuration more declarative and less hardcoded

- [ ] **Add Monitoring and Alerting**
  - Integrate Prometheus metrics
  - Add Grafana dashboard configuration
  - Set up log aggregation

## File Structure Reorganization

### 🟢 Proposed New Structure

```
nix-pihole/
├── flake.nix
├── README.md
├── TODO.md
├── modules/
│   ├── pihole.nix
│   ├── networking.nix
│   ├── base-system.nix
│   ├── hardware/
│   │   ├── raspberry-pi-4.nix
│   │   └── filesystems.nix
│   └── users.nix
├── examples/
│   ├── ethernet-only.nix
│   ├── multiple-wifi.nix
│   └── custom-blocklists.nix
├── templates/
│   ├── personal-config.nix.example
│   ├── wifi-config.nix.example
│   └── secrets.nix.example
├── scripts/
│   ├── build-image.sh
│   ├── deploy.sh
│   └── setup-secrets.sh
└── personal/          # gitignored directory
    ├── users.nix
    ├── wifi.nix
    └── secrets.nix
```

## Migration Steps

1. **Phase 1: Security** - Address hardcoded credentials
2. **Phase 2: Modularization** - Split configuration into logical modules
3. **Phase 3: Documentation** - Add examples and improve docs
4. **Phase 4: Enhancement** - Add advanced features and monitoring

## Priority Legend

- 🔴 High Priority (Security/Critical)
- 🟡 Medium Priority (Maintenance/Quality)
- 🟢 Low Priority (Enhancement/Nice-to-have)
