# CLAUDE.md

## Project Overview

NixOS flake for imageless boot via virtiofs. Builds a NixOS system
closure and systemd initramfs that run from the host's /nix/store
shared read-only into the guest. Root is tmpfs (ephemeral). The
kernel is provided externally. NixOS builds the initramfs.

**License**: copyleft-next-0.3.1

## Project Structure

```
nixos-qemu/
├── flake.nix              Flake (nixosModules, overlays, templates, vm)
├── configuration.nix      NixOS module (tmpfs root, SSH, networkd)
├── flake.lock             Pinned nixpkgs revision
├── docs/
│   ├── usage.md             Configurations, overlays, packages, updating
│   └── design-decisions.md  Hardcoded choices and upstream references
├── modules/
│   └── devel.nix          Development profile (kernel testing tools)
├── pkgs/
│   ├── default.nix        Custom packages via callPackage
│   ├── cpupower.nix       Standalone cpupower from kernel source tree
│   ├── damo.nix           DAMON user-space tool
│   ├── libbpf-tools.nix   CO-RE BPF tracing tools from BCC
│   ├── nfstest.nix        NFS test suite
│   ├── pynfs.nix          Python NFSv4 conformance tests
│   └── xnvme.nix          Cross-platform NVMe library and tools
├── overlays/
│   ├── default.nix        Composes per-package overlays + pkgs/
│   ├── fio.nix            fio with liburing + test suite + examples
│   └── xfstests.nix       Bump xfstests to 2026.03.20
├── templates/
│   └── devel/flake.nix    Template for nix flake init --template
├── LICENSES/
│   └── preferred/copyleft-next-0.3.1
├── COPYING                License overview and dual-licensing guidance
├── LICENSE                Copyright and license reference
└── README.md
```

## Critical Rules

### Never fabricate facts

Every NixOS option must be verified against the NixOS options search
(search.nixos.org/options) or the nixpkgs source.

### Long-form command options

NEVER use short flags when a long-form alternative exists.
`--template` not `-t`, `--recursive` not `-r`, `--parents` not
`-p`. Exception: tools without long-form options (`ssh -p`).

## Rules

### External kernel, NixOS-built initramfs

`boot.kernel.enable = false` tells NixOS not to build a kernel.
`boot.initrd.systemd.enable = true` tells NixOS to build a systemd
initramfs that mounts root (tmpfs), /nix/store, and /lib/modules
via virtiofs before switch-root into the system closure.

### Tmpfs root

`fileSystems."/" = lib.mkImageMediaOverride { fsType = "tmpfs"; }`
declares root as tmpfs. `mkImageMediaOverride` has higher priority
than default NixOS filesystem declarations. Changes are lost on
shutdown.

### Minimal profile

`imports = [ (modulesPath + "/profiles/minimal.nix") ]` reduces the
closure size by excluding unnecessary packages.

### Password auth

`users.users.root.initialPassword = "root"` with
`users.mutableUsers = false` sets the root password on every boot
(tmpfs root resets it). SSH allows password auth for development
convenience.

### Overlays

Each file in `overlays/` overrides one nixpkgs package using
`overrideAttrs`. The `overlays/default.nix` composes all per-package
overlays and merges custom packages from `pkgs/` into a single
overlay exported as `overlays.default`.

### Custom packages (pkgs/)

Packages not available in nixpkgs are defined in `pkgs/` using the
`callPackage` pattern from nix.dev. Each package is a file declaring
a function whose arguments are its dependencies. The overlay imports
`pkgs/default.nix` and merges them into the nixpkgs set.

### Templates

`templates/devel/` is copied by `nix flake init --template`. It contains
a standalone `flake.nix` that imports `nixosModules.default` and
`overlays.default` from nixos-qemu. Users add their own packages
and NixOS options there.

## Build

```shell
nix build .#nixosConfigurations.vm.config.system.build.toplevel
readlink --canonicalize result
```

The `result` symlink points to the system closure. The NixOS init
is at `<closure>/init`. The init= path changes on every rebuild.

## Git Commit Guidelines

### One commit per change

Atomic commits. Spell fixes go in separate commits from code changes.

### Commit message format

```
subsystem: brief description in imperative mood

Plain English explanation of the change. NEVER use bullet points
or itemized lists in commit messages.

Generated-by: Claude AI
Signed-off-by: Your Name <your.email@example.org>
```

### Use Signed-off-by and Generated-by tags

Generated-by MUST be immediately followed by Signed-off-by with NO
empty lines between them. No Co-Authored-By trailer.

### No shopping cart lists

NEVER use bullet points or itemized lists in commit messages. Use
plain English paragraphs.

### Subsystem prefix

Use `configuration:` for NixOS config changes, `flake:` for flake
changes, `overlays:` for package overlays, `pkgs:` for custom
packages, `templates:` for template changes, `docs:` for
documentation in docs/, `README:` for README changes. Use
`nixos-qemu:` for cross-cutting changes.

## Related work

- [run-kernel](https://github.com/metaspace/run-kernel). Rust init + NixOS boot via virtiofs. The direct inspiration for this project's boot model.
- [nixos-shell](https://github.com/Mic92/nixos-shell). Nix-based lightweight QEMU VMs with host mounts.
- [kernel-development-flake](https://github.com/jordanisaacs/kernel-development-flake). Nix flake for Linux kernel development with QEMU.
