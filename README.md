# lightpanda-nix

[![ci](https://github.com/crayonnova/lightpanda-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/crayonnova/lightpanda-nix/actions/workflows/ci.yml)
[![update](https://github.com/crayonnova/lightpanda-nix/actions/workflows/update.yml/badge.svg)](https://github.com/crayonnova/lightpanda-nix/actions/workflows/update.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

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

`.github/workflows/update.yml` runs `update.sh` weekly and opens a PR, which
`ci.yml` then checks like any other. It authenticates with `secrets.UPDATE_PAT`
— a fine-grained token scoped to this repo with `contents: write` and
`pull-requests: write` — rather than the default `GITHUB_TOKEN`, because GitHub
suppresses workflow runs on `GITHUB_TOKEN`-authored events to prevent recursion,
which would leave every bump PR with no checks at all.

If that token expires, the PR step starts failing on a weekly cron, which is
easy to miss. Do not merge a bump that the `darwin` job has not built.

## License

The packaging in this repository — `flake.nix`, `lightpanda.nix`,
`hm-module.nix`, `update.sh` — is MIT licensed, matching nixpkgs so the
expression can be upstreamed without a relicensing question. See [LICENSE](LICENSE).

Lightpanda itself is **AGPL-3.0-only** and is not covered by that. This repo
ships no Lightpanda source; it fetches upstream's prebuilt binaries at build
time, and `meta.license` in `lightpanda.nix` declares their terms.
