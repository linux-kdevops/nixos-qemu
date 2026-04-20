# Design decisions

This project builds a NixOS system closure for imageless boot via
virtiofs. The operating system runs from the host's `/nix/store`
shared read-only into the guest. Root is tmpfs (ephemeral, lost on
shutdown). This document explains the design choices and the upstream
mechanisms that make this work.

## systemd initramfs

NixOS builds a systemd-based initramfs where systemd runs as
PID 1. systemd's
[fstab-generator](https://github.com/systemd/systemd/blob/main/src/fstab-generator/fstab-generator.c)
reads the NixOS-generated initrd fstab and creates mount units
for `/nix/store` automatically. All upstream code, no custom init
binary.

The NixOS module that implements `boot.initrd.systemd` is
[`nixos/modules/system/boot/systemd/initrd.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/boot/systemd/initrd.nix).
The initrd fstab generation and `SYSTEMD_SYSROOT_FSTAB` wiring is
in
[`nixos/modules/tasks/filesystems.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/tasks/filesystems.nix).

The configuration enables the systemd initramfs and declares
virtiofs filesystems:

```nix
boot.initrd.systemd.enable = true;
boot.initrd.supportedFilesystems = [ "virtiofs" ];

fileSystems."/nix/store" = {
  device = "store";
  fsType = "virtiofs";
};
```

Kernel command line (standard parameters only):
```
root=tmpfs console=ttyS0,115200 console=hvc0 init=/nix/store/<hash>/init
```

## How the systemd initramfs works

The boot sequence uses standard systemd and NixOS mechanisms. Every
step is upstream code.

### NixOS initrd fstab generation

NixOS generates an initrd-specific fstab from `fileSystems`
declarations. The function `fsNeededForBoot` in
`nixos/lib/utils.nix` determines which filesystems go into the
initrd fstab. It returns true for any filesystem where either
`neededForBoot = true` or the mount point is in `pathsNeededForBoot`:

```nix
pathsNeededForBoot = [
  "/"
  "/nix"
  "/nix/store"
  "/var"
  "/var/log"
  "/var/lib"
  "/var/lib/nixos"
  "/etc"
  "/usr"
];
```

`/nix/store` is explicitly in this list. Any `fileSystems."/nix/store"`
declaration is automatically included in the initrd fstab without
requiring `neededForBoot = true`.

The initrd fstab is written to a file and passed to systemd via the
`SYSTEMD_SYSROOT_FSTAB` environment variable. NixOS wires this up in
`nixos/modules/tasks/filesystems.nix` through
`boot.initrd.systemd.managerEnvironment` and the `initrd-parse-etc`
service environment.

### systemd fstab-generator in the initrd

systemd-fstab-generator runs in the initrd and reads the initrd
fstab (from `SYSTEMD_SYSROOT_FSTAB`). For each entry, it generates
a systemd mount unit. The mount points are prefixed with `/sysroot`
because the generator runs in the initrd context
(`src/fstab-generator/fstab-generator.c`, `prefix_sysroot` logic).

For our configuration, the generator creates:
- `sysroot.mount`: tmpfs on `/sysroot` (from `root=tmpfs`)
- `sysroot-nix-store.mount`: virtiofs `store` on `/sysroot/nix/store`

### root=tmpfs handling

systemd-fstab-generator explicitly supports `root=tmpfs` as a
shortcut for a writable tmpfs root (see the `arg_root_what == "tmpfs"`
branch in `src/fstab-generator/fstab-generator.c`):

```c
} else if (streq(arg_root_what, "tmpfs")) {
    /* If root=tmpfs is specified, then take this as shortcut
       for a writable tmpfs mount as root */
    what = strdup("rootfs");
    fstype = arg_root_fstype ?: "tmpfs";
```

This creates a tmpfs mount at `/sysroot` with mode 0755.

### switch-root sequence

After all initrd mounts complete (`initrd-fs.target`), systemd
performs switch-root to `/sysroot`:

1. systemd reaches `initrd.target` (all initrd services done)
2. `initrd-cleanup.service` runs
3. `initrd-switch-root.target` activates
4. `initrd-switch-root.service` calls `systemctl switch-root /sysroot`

After switch-root, `/sysroot` becomes `/`. The virtiofs mount that
was at `/sysroot/nix/store` is now at `/nix/store`. The NixOS
stage-2 init at `/nix/store/<hash>/init` becomes accessible at its
expected path.

### Kernel module matching

When NixOS builds the initramfs, it can include kernel modules
from the NixOS kernel package. These modules must match the
running kernel version exactly. With an external custom kernel
(`boot.kernel.enable = false`), the versions will not match and
module loading in the initramfs will fail.

The solution is to exclude all kernel modules from the initramfs
and provide them via virtiofs instead:

```nix
boot.initrd.availableKernelModules = lib.mkForce [];
boot.initrd.kernelModules = lib.mkForce [];
```

This requires the external kernel to have the boot-critical
drivers built-in: `CONFIG_VIRTIO_FS=y` (mount /nix/store and
/lib/modules in the initramfs), `CONFIG_VIRTIO_PCI=y` (PCI
transport), and `CONFIG_TMPFS=y` (root filesystem). All other
drivers can be kernel modules (`=m`), loaded from `/lib/modules`
after switch-root. The `/lib/modules` directory is mounted via
virtiofs from the external kernel build's module install path.

## Root filesystem: tmpfs

```nix
fileSystems."/" = lib.mkImageMediaOverride {
  fsType = "tmpfs";
  options = [ "mode=0755" ];
};
```

Root is tmpfs. Everything written to `/` is lost on shutdown. This
is the standard NixOS approach for ephemeral systems. The operating
system state comes from `/nix/store` (read-only, shared from host)
and `/etc` (generated by NixOS activation from the store).

`lib.mkImageMediaOverride` sets the NixOS option priority to 60,
overriding the default root filesystem declaration from NixOS
modules. Without this, NixOS expects a persistent root device.
See: `lib/modules.nix` in nixpkgs (`mkImageMediaOverride`).

`systemd.services.systemd-remount-fs.enable = false` is set because
there is nothing to remount. The root is already writable tmpfs.

## /nix/store: virtiofs read-only

```nix
fileSystems."/nix/store" = {
  device = "store";
  fsType = "virtiofs";
};
```

The Nix store is immutable by design. Packages are content-addressed
and never modified in place. Read-only virtiofs mounting enforces
this at the mount level. The `device` field is the virtiofs tag
name that must match the tag configured in the virtiofsd instance
sharing the host's `/nix/store` into the guest.

## External kernel

```nix
boot.kernel.enable = false;
```

NixOS does not build a kernel. The kernel is built separately using
Kconfig fragments and installed to a destdir. This allows rapid
kernel development iteration without rebuilding the NixOS closure.

The kernel command line is passed to QEMU via the `-append` flag
(or equivalent configuration), not by NixOS. `boot.kernelParams`
in the NixOS configuration sets default parameters that are
recorded in `boot.json` but are not automatically applied when
using an external kernel. The QEMU configuration must include
`root=tmpfs` and `init=<closure>/init` explicitly.

## Minimal profile

```nix
imports = [ (modulesPath + "/profiles/minimal.nix") ];
```

The minimal profile disables documentation, fonts, and other
non-essential modules. This reduces the system closure size from
~500MB to ~200MB. The closure contains only systemd, SSH, network
configuration, and coreutils.

## Password authentication

```nix
users.mutableUsers = false;
users.users.root.initialPassword = "root";
services.openssh.settings.PasswordAuthentication = true;
```

Root is tmpfs, so `/etc/shadow` is generated fresh on every boot
from the NixOS configuration. `mutableUsers = false` ensures the
password is always reset to the configured value. SSH key
authentication would require injecting keys into the closure or
mounting them via virtiofs.

## systemd-networkd

```nix
networking.useNetworkd = true;
systemd.network.networks."80-ethernet" = {
  matchConfig.Name = "en*";
  networkConfig.DHCP = "yes";
};
```

systemd-networkd is the standard network manager for systemd-based
systems. NetworkManager is heavier and designed for desktop use.
The network configuration matches all ethernet interfaces (virtio
NIC appears as `enp0s2` in QEMU with q35 machine type) and enables
DHCP.
