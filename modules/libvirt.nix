# SPDX-License-Identifier: copyleft-next-0.3.1
#
# Disk-image NixOS boot for libvirt-managed VMs. Expects a qcow2
# virtio-blk disk at /dev/vda.
#
# Ported from kdevops commit 3089c3fec57 by Luis Chamberlain
# (playbooks/templates/nixos/configuration.nix.j2). Per-node content
# (hostname, keys, 9p, cache) stays in kdevops as additional modules.
{ pkgs, lib, ... }: {

  system.stateVersion = "25.11";

  # Key-only SSH. Password below is serial-console break-glass.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkDefault "yes";
      PubkeyAuthentication = true;
      PasswordAuthentication = lib.mkDefault false;
    };
  };

  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };
  boot.loader.timeout = lib.mkDefault 1;
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  # libvirt's default network hands out 192.168.122.0/24 via DHCP.
  networking.useDHCP = lib.mkDefault true;

  virtualisation.libvirtd.enable = lib.mkDefault false;

  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "weekly";
    options = lib.mkDefault "--delete-older-than 7d";
  };
}
