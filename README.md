# lightpanda-nix

Nix flake packaging the [Lightpanda](https://github.com/lightpanda-io/browser)
headless browser from upstream's prebuilt release binaries.

On Linux the binary is wrapped with `autoPatchelfHook`: upstream hardcodes
`/lib64/ld-linux-x86-64.so.2` as its ELF interpreter, and on NixOS that path
holds only a stub loader that errors out, so the interpreter is repointed at
glibc's real loader in the store.

On Darwin no patching happens. The Mach-O binaries reference only absolute
system paths (CoreFoundation, SystemConfiguration, Security, `libSystem`,
`libobjc`) resolved from the dyld shared cache, and they carry an ad-hoc code
signature that stripping would invalidate — so the bytes are installed as-is.

Pinned to tagged upstream releases, never the moving `nightly` tag, so every
commit here stays buildable.

| Platform         | Flake output | Notes                                |
| ---------------- | ------------ | ------------------------------------ |
| `x86_64-linux`   | yes          |                                      |
| `aarch64-linux`  | yes          |                                      |
| `aarch64-darwin` | yes          | requires macOS 14.8.7+               |
| `x86_64-darwin`  | no           | overlay only — see below             |

`x86_64-darwin` has a source entry in `passthru.sources`, so it still works
through `overlays.default` on a nixpkgs that supports it, but it is absent from
`packages.*`: nixpkgs 26.11 dropped the platform, and evaluating it throws.

## Use as a flake input

```nix
{
  inputs.lightpanda = {
    url = "github:crayonnova/lightpanda-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then either add the overlay:

```nix
pkgs = import nixpkgs {
  inherit system;
  overlays = [ inputs.lightpanda.overlays.default ];
};
# ... pkgs.lightpanda
```

or reference the package directly: `inputs.lightpanda.packages.${system}.default`.

## Run

```bash
nix run github:crayonnova/lightpanda-nix -- version
```

## Updating

```bash
./update.sh          # resolves the latest release, refetches every platform hash
nix build .#lightpanda-bin && ./result/bin/lightpanda version
```

Do not hand-edit hashes. `update.sh` derives its platform list from
`passthru.sources` and translates Nix's `-darwin` to upstream's `-macos` asset
naming, so adding a platform is a one-place edit.

## Upstreaming to nixpkgs

`lightpanda.nix` is written in nixpkgs style (`stdenvNoCC`, `passthru.sources`
keyed by system, `sourceProvenance`, `updateScript`) so it can move to
`pkgs/by-name/li/lightpanda-bin/package.nix` largely unchanged. Before
submitting: add your handle to `meta.maintainers`, and swap `update.sh` for
`update-source-version` calls (see the comment at the top of `update.sh`).

The Home Manager module cannot go to nixpkgs — modules live in the
`home-manager` repo and need a separate PR.
