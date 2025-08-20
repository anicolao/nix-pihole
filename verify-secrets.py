#!/usr/bin/env python3
"""
Verification script for nix-pihole secrets setup
This script checks that the secrets.nix file is properly configured
"""

import os
import sys


def check_secrets_file():
    """Check that secrets.nix exists and has the required structure"""
    if not os.path.exists("secrets.nix"):
        print("❌ secrets.nix file not found!")
        print("   Please copy secrets.nix.example to secrets.nix and customize it")
        return False

    try:
        with open("secrets.nix", "r") as f:
            content = f.read()

        required_sections = ["wifi", "networkName", "password", "sshKeys", "users"]

        missing = [section for section in required_sections if section not in content]

        if missing:
            print(f"❌ secrets.nix missing required sections: {missing}")
            return False

        # Check for template values that need to be replaced
        if "YOUR_WIFI_NETWORK" in content:
            print(
                "❌ Please replace YOUR_WIFI_NETWORK with your actual WiFi network name"
            )
            return False

        if "YOUR_WIFI_PASSWORD" in content:
            print("❌ Please replace YOUR_WIFI_PASSWORD with your actual WiFi password")
            return False

        if "YOUR_SSH_PUBLIC_KEY_HERE" in content:
            print(
                "❌ Please replace YOUR_SSH_PUBLIC_KEY_HERE with your actual SSH public key"
            )
            return False

        print("✅ secrets.nix is properly configured")
        return True

    except Exception as e:
        print(f"❌ Error reading secrets.nix: {e}")
        return False


def check_git_ignore():
    """Check that secrets.nix is in .gitignore"""
    if not os.path.exists(".gitignore"):
        print("❌ .gitignore file not found")
        return False

    try:
        with open(".gitignore", "r") as f:
            content = f.read()

        if "secrets.nix" not in content:
            print("❌ secrets.nix is not in .gitignore!")
            print("   This is a security risk - your secrets could be committed to git")
            return False

        print("✅ secrets.nix is properly ignored by git")
        return True

    except Exception as e:
        print(f"❌ Error reading .gitignore: {e}")
        return False


def check_hardcoded_values():
    """Check that hardcoded values have been removed from config files"""
    files_to_check = ["configuration.nix", "alex_users.nix"]

    for filename in files_to_check:
        if not os.path.exists(filename):
            print(f"❌ {filename} not found")
            return False

        try:
            with open(filename, "r") as f:
                content = f.read()

            # Check for old hardcoded values
            if "airc" in content or "SnoopyNet" in content:
                print(f"❌ {filename} still contains hardcoded WiFi credentials")
                return False

            if "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQ" in content:
                print(f"❌ {filename} still contains hardcoded SSH keys")
                return False

        except Exception as e:
            print(f"❌ Error reading {filename}: {e}")
            return False

    print("✅ No hardcoded credentials found in configuration files")
    return True


def main():
    print("🔍 Verifying nix-pihole secrets configuration...\n")

    checks = [check_secrets_file, check_git_ignore, check_hardcoded_values]

    all_passed = True
    for check in checks:
        if not check():
            all_passed = False
        print()

    if all_passed:
        print("🎉 All security checks passed! Your nix-pihole configuration is secure.")
        return 0
    else:
        print("❌ Some security checks failed. Please fix the issues above.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
