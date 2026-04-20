# nixos-qemu

NixOS flake for imageless boot via virtiofs. The host shares
/nix/store read-only into the guest via virtiofsd. NixOS builds a
systemd initramfs that mounts the store and switch-roots into the
system closure. Root is tmpfs: ephemeral, lost on shutdown.

**License**: copyleft-next-0.3.1

## Features

- **No disk image**: root is tmpfs, operating system from /nix/store
- **External kernel**: `boot.kernel.enable = false`, no kernel in the closure
- **Minimal closure**: imports `profiles/minimal.nix`, ~200 MB
- **Declarative**: rebuild with `nix build`, get a new system closure
- **Extensible**: overlays for package customization, template for new configurations

## Prerequisites

The [Nix package manager](https://nixos.org/download/) with flake
support enabled:

```shell
mkdir --parents ~/.config/nix
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
```

## Quick start

Build the NixOS system closure:

```shell
nix build .#nixosConfigurations.vm.config.system.build.toplevel
readlink --canonicalize result
```

The `result` symlink points to the system closure. The `boot.json`
file inside the closure contains the `init` and `initrd` paths
needed to configure QEMU:

```shell
cat result/boot.json
```

To create a custom configuration with additional packages or NixOS
options, see [docs/usage.md](docs/usage.md).

## How it boots

This project builds two artifacts: a NixOS system closure and a
systemd initramfs. Booting requires an external kernel and QEMU
with virtiofsd sharing the host's `/nix/store` and `/lib/modules`
into the guest.

The external kernel must have the boot-critical virtio drivers
built-in (`CONFIG_VIRTIO_FS=y`, `CONFIG_VIRTIO_PCI=y`,
`CONFIG_TMPFS=y`). All other drivers can be kernel modules loaded
from `/lib/modules` after switch-root.

QEMU needs two virtiofsd instances sharing host directories into
the guest with these tags:

- `store`: the host's `/nix/store` (read-only)
- `modules`: the kernel build's `/lib/modules` directory

The kernel command line:

```
root=tmpfs console=ttyS0,115200 console=hvc0 init=/nix/store/<hash>/init
```

systemd in the initramfs reads the NixOS-generated fstab, mounts
root (tmpfs), `/nix/store` (virtiofs tag `store`), and
`/lib/modules` (virtiofs tag `modules`), then switch-roots into
the system closure. The `init=` and `initrd` paths change on
every rebuild and are available in `result/boot.json`.

## Documentation

| Document | Content |
|---|---|
| [docs/usage.md](docs/usage.md) | Configurations, overlays, packages, home overlay, NVMe filesystems |
| [docs/design-decisions.md](docs/design-decisions.md) | Initramfs approaches, systemd initrd, tmpfs root, virtiofs |

## Related work

- [run-kernel](https://github.com/metaspace/run-kernel). Rust init + NixOS boot via virtiofs. The direct inspiration for this project's boot model.
- [nixos-shell](https://github.com/Mic92/nixos-shell). Nix-based lightweight QEMU VMs with host mounts.
- [kernel-development-flake](https://github.com/jordanisaacs/kernel-development-flake). Nix flake for Linux kernel development with QEMU.
