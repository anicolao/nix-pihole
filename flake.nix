{
  description = "Build Raspberry PI 4 image";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };
  outputs = {nixpkgs, ...}: let
    hostname = "pihole";
    # Use personal configuration if it exists, otherwise fall back to default
    userConfig = if builtins.pathExists ./personal/alex_users.nix 
      then ./personal/alex_users.nix 
      else ./default-users.nix;
    
    # Support building from multiple host systems via packages interface
    systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    
    # Function to create RPI4 system for any host system with proper cross-compilation
    mkRpi4System = hostSystem: let
      # Import nixpkgs with proper cross-compilation setup
      pkgs = import nixpkgs {
        system = hostSystem;
        crossSystem = nixpkgs.lib.systems.examples.aarch64-multiplatform;
        config = {
          allowUnfree = true;
        };
      };
    in nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = { inherit pkgs; };
      modules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ./sdimage.nix
        userConfig
        ./configuration.nix
        # Use the cross-compiled pkgs
        {
          nixpkgs.pkgs = pkgs;
        }
      ];
    };
  in rec {
    # For backward compatibility, provide a default rpi4 configuration (native build)
    nixosConfigurations.rpi4 = mkRpi4System "aarch64-linux";

    # Make the image available directly at top level for cross-compilation
    # Use a fixed host system for the top-level attribute
    images.rpi4 = (mkRpi4System "x86_64-linux").config.system.build.sdImage;

    # Provide the image as a package on all systems for cross-compilation
    packages = forAllSystems (system: {
      rpi4-image = (mkRpi4System system).config.system.build.sdImage;
    }) // {
      aarch64-linux.nixosConfigurations."${hostname}" = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./filesystems.nix
          userConfig
          ./configuration.nix
        ];
      };
    };
  };
}
