# SPDX-License-Identifier: copyleft-next-0.3.1
#
# Minimal NixOS flake for imageless boot via virtiofs.
#
# Build the system closure:
#   nix build .#nixosConfigurations.vm.config.system.build.toplevel
#
# Build an individual custom package:
#   nix build .#cpupower
#
# The result symlink points to the system closure in /nix/store.
# The NixOS init is at: $(readlink --canonicalize result)/init
{
  description = "NixOS flake for imageless boot via virtiofs";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
  let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
      f (import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      }));
  in {
    nixosModules = {
      default = ./configuration.nix;
      devel = ./modules/devel.nix;
    };

    overlays.default = import ./overlays;

    templates.default = {
      path = ./templates/devel;
      description = "NixOS VM with custom packages for kernel development";
    };

    # Expose the custom packages as direct flake outputs so they can be
    # built without going through a NixOS configuration.
    packages = forAllSystems (pkgs: {
      inherit (pkgs) cpupower damo libbpf-tools nfstest pynfs xnvme;
    });

    nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.default
        { nixpkgs.overlays = [ self.overlays.default ]; }
      ];
    };
  };
}
