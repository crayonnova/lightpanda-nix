# lightpanda-nix

Nix flake packaging the [Lightpanda](https://github.com/lightpanda-io/browser)
headless browser — a prebuilt release binary wrapped with `autoPatchelfHook` so
it runs on NixOS. The upstream binary hardcodes `/lib64/ld-linux-x86-64.so.2`
as its ELF interpreter; on NixOS that path holds only a stub loader that errors
out, so the interpreter is repointed at glibc's real loader in the store.

Pinned to tagged upstream releases, never the moving `nightly` tag, so every
commit here stays buildable. Platforms: `x86_64-linux`, `aarch64-linux`.

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

Do not hand-edit hashes.

## Upstreaming to nixpkgs

`lightpanda.nix` is written in nixpkgs style (`stdenvNoCC`, `passthru.sources`
keyed by system, `sourceProvenance`, `updateScript`) so it can move to
`pkgs/by-name/li/lightpanda-bin/package.nix` largely unchanged. Before
submitting: add your handle to `meta.maintainers`, and swap `update.sh` for
`update-source-version` calls (see the comment at the top of `update.sh`).

The Home Manager module cannot go to nixpkgs — modules live in the
`home-manager` repo and need a separate PR.
