# SPDX-License-Identifier: copyleft-next-0.3.1
#
# Libvirt disk-image NixOS VM starter.
#
# Create with:
#   nix flake init --template "github:linux-kdevops/nixos-qemu#libvirt"
#   nix build .#nixosConfigurations.vm.config.system.build.toplevel
{
  inputs = {
    # Local checkout preferred: downstream consumers (kdevops and
    # others) pin to a specific revision via a subtree or vendored
    # copy, and should not track upstream HEAD. For upstream, use:
    #   nixos-qemu.url = "github:linux-kdevops/nixos-qemu";
    nixos-qemu.url = "path:/path/to/nixos-qemu";
    nixpkgs.follows = "nixos-qemu/nixpkgs";

    # Local source checkouts (uncomment to use):
    # fio-src = { url = "path:/home/user/src/fio"; flake = false; };
    # kmod-src = { url = "path:/home/user/src/kmod"; flake = false; };
  };

  outputs = { self, nixpkgs, nixos-qemu, ... }@inputs: {
    nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-qemu.nixosModules.libvirt
        nixos-qemu.nixosModules.user
        nixos-qemu.nixosModules.devel
        ({ pkgs, lib, ... }: {
          nixpkgs.overlays = [
            nixos-qemu.overlays.default

            # Build from local source (uncomment input above and line below):
            # (final: prev: { fio = prev.fio.overrideAttrs { src = inputs.fio-src; patches = []; }; })
            # (final: prev: { kmod = prev.kmod.overrideAttrs { src = inputs.kmod-src; }; })
          ];
        })
      ];
    };
  };
}
