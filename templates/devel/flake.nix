# SPDX-License-Identifier: copyleft-next-0.3.1
#
# NixOS VM with custom packages for kernel development.
#
# Inherits the nixos-qemu base configuration, devel module (kernel
# testing and storage tools), and package overlays. Add your own
# packages or NixOS options below.
#
# To build a package from a local source checkout, uncomment its
# input and the matching overlay line below. See docs/usage.md
# for the full list of supported packages.
#
# Created with:
#   mkdir --parents configurations/my-vm && cd configurations/my-vm
#   nix flake init --template "path:$PWD/../.."
#   $EDITOR flake.nix    # set the nixos-qemu.url path below
#   git init && git add flake.nix
#   nix build .#nixosConfigurations.vm.config.system.build.toplevel
#   readlink --canonicalize result
{
  inputs = {
    # Set this to the absolute path of your nixos-qemu checkout, or
    # use the remote URL for upstream:
    #   nixos-qemu.url = "github:your-org/nixos-qemu";
    nixos-qemu.url = "path:/path/to/nixos-qemu";
    nixpkgs.follows = "nixos-qemu/nixpkgs";

    # Local source checkouts. Uncomment and set the path to use.
    # fio-src = { url = "path:/home/user/src/fio"; flake = false; };
    # kmod-src = { url = "path:/home/user/src/kmod"; flake = false; };
  };

  outputs = { self, nixpkgs, nixos-qemu, ... }@inputs: {
    nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-qemu.nixosModules.default
        nixos-qemu.nixosModules.devel
        ({ pkgs, lib, ... }: {
          nixpkgs.overlays = [
            nixos-qemu.overlays.default

            # Build from local source: uncomment input above and line below.
            # (final: prev: { fio = prev.fio.overrideAttrs { src = inputs.fio-src; patches = []; }; })
            # (final: prev: { kmod = prev.kmod.overrideAttrs { src = inputs.kmod-src; }; })
          ];
        })
      ];
    };
  };
}
