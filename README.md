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
./update.sh --check  # verifies the hashes already pinned; writes nothing
nix build .#lightpanda-bin && ./result/bin/lightpanda version
```

Do not hand-edit hashes. `update.sh` derives its platform list from
`passthru.sources` and translates Nix's `-darwin` to upstream's `-macos` asset
naming, so adding a platform is a one-place edit.

`--check` exists because a fixed-output derivation assumes a URL's bytes never
change. If upstream ever replaces a published asset in place, every recorded
hash for that tag silently becomes a lie and users hit `hash mismatch in
fixed-output derivation` on their next build. `--check` re-fetches each pinned
source, exits non-zero on any mismatch, and never rewrites the file — so it
reports the problem instead of papering over it. It makes no GitHub API call,
and it covers `x86_64-darwin` too, which no build job can reach.

## CI

`.github/workflows/ci.yml` runs on push, PR, and a weekly schedule. One job per
failure mode:

| Job      | Runner          | Checks                                              |
| -------- | --------------- | --------------------------------------------------- |
| `linux`  | `ubuntu-latest` | `nix flake check --all-systems`, build, ELF interpreter repointed into the store |
| `darwin` | `macos-14`      | build and **execute** on real Apple Silicon          |
| `hashes` | `ubuntu-latest` | `./update.sh --check`                                |

The schedule trigger is not redundant: asset drift originates upstream, so it
would never surface from push events alone.

The `darwin` job's `lightpanda version` step is the code-signature test. A
stripped or otherwise rewritten Mach-O fails signature validation and is killed
on exec, so a successful run proves the bytes were installed untouched.

`.github/workflows/update.yml` runs `update.sh` weekly and opens a PR. Note that
PRs authored by the default `GITHUB_TOKEN` do **not** trigger `ci.yml` — GitHub
suppresses that to prevent recursion — so those PRs show no checks unless you
supply a PAT as `secrets.UPDATE_PAT`. Do not merge a bump that darwin has not
built.
