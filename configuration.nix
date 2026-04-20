# SPDX-License-Identifier: copyleft-next-0.3.1
#
# Minimal NixOS configuration for imageless boot via virtiofs.
#
# Root is tmpfs. /nix/store and /lib/modules are mounted via virtiofs
# from the host. The kernel is built externally with all boot-critical
# drivers built-in (CONFIG_VIRTIO_FS=y, CONFIG_TMPFS=y). NixOS builds
# a systemd initramfs that mounts root (tmpfs), /nix/store, and
# /lib/modules before switch-root.
#
# Password auth and networkd DHCP for development convenience.
{ pkgs, lib, modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/minimal.nix") ];

  system.stateVersion = "25.11";

  # Root as tmpfs: ephemeral, no disk image. systemd in the initramfs
  # creates this from root=tmpfs on the kernel command line.
  fileSystems."/" = lib.mkImageMediaOverride {
    fsType = "tmpfs";
    options = [ "mode=0755" ];
  };

  # /nix/store via virtiofs (read-only, shared from host).
  # Automatically included in initrd fstab (pathsNeededForBoot).
  fileSystems."/nix/store" = {
    device = "store";
    fsType = "virtiofs";
  };

  # Kernel modules via virtiofs (from the external kernel build).
  # neededForBoot puts it in the initrd fstab since /lib/modules
  # is not in pathsNeededForBoot.
  fileSystems."/lib/modules" = {
    device = "modules";
    fsType = "virtiofs";
    neededForBoot = true;
  };

  # Disable systemd-remount-fs. Nothing to remount on tmpfs.
  systemd.services.systemd-remount-fs.enable = lib.mkForce false;

  # No bootloader. Kernel is external, but NixOS builds the initramfs.
  boot.loader.grub.enable = false;
  boot.kernel.enable = false;

  # Workaround: boot.kernel.enable = false does not define
  # system.build.kernel, but boot.initrd.systemd accesses
  # kernel.config.isYes and kernel.config.isSet to decide whether
  # to include kernel modules in the initramfs.
  #
  # The initrd module uses: isSet "MODULES" -> isYes "MODULES"
  # (Nix implication). To exclude modules, isSet must return true
  # and isYes must return false (true -> false = false).
  # https://github.com/NixOS/nixpkgs/issues/467069
  system.build.kernel.config = {
    isYes = _: false;
    isSet = _: true;
  };

  # systemd initramfs: systemd runs as PID 1, reads the initrd fstab,
  # mounts root + /nix/store + /lib/modules, then switch-roots.
  boot.initrd.systemd.enable = true;
  boot.initrd.supportedFilesystems = [ "virtiofs" ];

  # Passwordless emergency shell in the initramfs. Without this,
  # sulogin blocks on "root account is locked" when boot fails.
  boot.initrd.systemd.emergencyAccess = true;

  # No kernel modules in the initramfs. The external kernel has all
  # boot-critical drivers built-in (CONFIG_VIRTIO_FS=y, CONFIG_TMPFS=y,
  # CONFIG_VIRTIO_PCI=y). Runtime modules come from /lib/modules via
  # virtiofs after switch-root.
  boot.initrd.availableKernelModules = lib.mkForce [];
  boot.initrd.kernelModules = lib.mkForce [];

  # Serial console on ttyS0 (journal) and hvc0 (interactive).
  # ttyS0 captures all output to the systemd journal via -serial
  # mon:stdio. hvc0 is a virtio console on a unix socket for
  # interactive access (socat). Last console= gets kernel messages.
  boot.kernelParams = [ "console=ttyS0,115200" "console=hvc0" ];

  # Serial getty on hvc0 for interactive login via the console socket.
  # hvc0 is a virtio console, handled by systemd's serial-getty@ template
  # (the plain getty@ template is VT-only, gated on /dev/tty0).
  # Requires CONFIG_VIRTIO_CONSOLE=y (or =m) in the guest kernel.
  systemd.services."serial-getty@hvc0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
  };

  # SSH with password auth (root:root).
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Root password. Reset to "root" on every boot (tmpfs root).
  users.mutableUsers = false;
  users.users.root.initialPassword = "root";

  # Networking: systemd-networkd with DHCP on all ethernet interfaces.
  networking.useNetworkd = true;
  networking.hostName = "nixos";
  networking.firewall.enable = false;
  systemd.network.networks."80-ethernet" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "yes";
  };

  # Disable unnecessary services.
  systemd.oomd.enable = false;
  nix.enable = false;
  services.lvm.enable = false;

  environment.systemPackages = with pkgs; [ coreutils ];
}
