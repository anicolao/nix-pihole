# Secrets Management

This repository now uses a `secrets.nix` file to manage sensitive configuration
like WiFi credentials and SSH keys, preventing them from being accidentally
committed to version control.

## Setup Instructions

1. **Copy the template file:**

   ```bash
   cp secrets.nix.example secrets.nix
   ```

2. **Edit the secrets file with your actual values:**

   ```bash
   nano secrets.nix  # or your preferred editor
   ```

3. **Update the following values:**

   - `wifi.networkName`: Your WiFi network name
   - `wifi.password`: Your WiFi password
   - `sshKeys.users`: Your SSH public key(s)

4. **Verify your configuration:**
   ```bash
   python3 verify-secrets.py
   ```

## Generating SSH Keys

If you don't have SSH keys yet:

```bash
# Generate a new SSH key
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy the public key content
cat ~/.ssh/id_ed25519.pub
```

## Security Notes

- The `secrets.nix` file is automatically ignored by git
- Never commit the `secrets.nix` file to version control
- Use the provided `secrets.nix.example` as a template for others
- Run `python3 verify-secrets.py` to check your configuration
- Consider using more advanced secret management tools like `agenix` or
  `sops-nix` for production deployments

## Migration from Hardcoded Values

This change removes the following hardcoded values:

- WiFi password `"****"` for network `"SnoopyNet"`
- SSH public keys embedded in `alex_users.nix`

These values now come from the `secrets.nix` file, making the configuration more
secure and reusable.
