#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash curl jq nix
#
# Bump lightpanda.nix to the newest upstream release.
#
# Out-of-tree stand-in for nixpkgs' `update-source-version`, which needs to
# nix-instantiate an attribute against a package tree and so does not work in a
# standalone flake. When upstreaming, drop this file and use bun's pattern:
#
#   for platform in $platforms; do
#     update-source-version lightpanda-bin "$version" \
#       --source-key="sources.$platform" --ignore-same-version
#   done

set -euo pipefail

# --check verifies the hashes already recorded for the *pinned* version instead
# of bumping to the newest release: it resolves no tag and writes no file, and
# exits non-zero if any recorded hash no longer matches what upstream serves.
# CI runs this to catch assets being replaced in place, which is what turns a
# fixed-output derivation's hash into a lie. Shares this file's parser and
# platform mapping deliberately — a second copy would drift.
check_only=false
drift=false
case "${1-}" in
  --check) check_only=true ;;
  "") ;;
  *) echo "usage: update.sh [--check]" >&2; exit 2 ;;
esac

repo="lightpanda-io/browser"
file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lightpanda.nix"

current="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$file")"
[[ -n "$current" ]] || { echo "update.sh: could not read current version" >&2; exit 1; }

if $check_only; then
  # Stay on the pinned tag: the point is to re-verify what is recorded.
  latest="$current"
  echo "lightpanda-bin: verifying recorded hashes for $current"
else
  # Do NOT use /releases/latest here. Upstream does not mark its rolling
  # `nightly` release as a prerelease, so GitHub reports `nightly` as "latest"
  # and that endpoint will happily pin you to a moving tag whose assets are
  # replaced in place — making every recorded hash a lie on the next rebuild.
  # Require a semver tag instead; the API returns releases newest-first.
  # Unauthenticated api.github.com allows 60 requests/hour per IP, and CI
  # runners share IPs, so honour GITHUB_TOKEN when one is present. Optional:
  # a local run needs no token. (--check makes no API call at all.)
  auth=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi

  latest="$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$repo/releases?per_page=100" | jq -r '
    [ .[]
      | select(.draft == false and .prerelease == false)
      | .tag_name
      | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
    ] | first // ""
  ')"
  [[ -n "$latest" ]] || { echo "update.sh: no semver release found for $repo" >&2; exit 1; }

  if [[ "$latest" == "$current" ]]; then
    echo "lightpanda-bin: already at $current"
    exit 0
  fi
  echo "lightpanda-bin: $current -> $latest"
fi

# Derive the platform list from the file itself, so adding a source to
# passthru.sources is the only edit needed to support a new platform.
platforms="$(sed -n 's/^      "\([^"]*\)" = fetchurl {$/\1/p' "$file")"
[[ -n "$platforms" ]] || { echo "update.sh: no platforms found in passthru.sources" >&2; exit 1; }

for platform in $platforms; do
  # Nix system strings say `-darwin`; upstream names its assets `-macos`. The
  # arch half matches on both sides, so only the OS half needs translating.
  asset="${platform%-darwin}"
  [[ "$asset" == "$platform" ]] || asset="$asset-macos"

  url="https://github.com/$repo/releases/download/$latest/lightpanda-$asset"

  # The hash belonging to this platform: first sha256- literal after its key.
  old="$(awk -v key="\"$platform\" = fetchurl" '
    index($0, key) { found = 1; next }
    found && match($0, /sha256-[A-Za-z0-9+\/=]+/) { print substr($0, RSTART, RLENGTH); exit }
  ' "$file")"
  [[ -n "$old" ]] || { echo "update.sh: no hash found for $platform" >&2; exit 1; }

  echo "  $platform: fetching $url"
  new="$(nix store prefetch-file --json --name "lightpanda-$asset" "$url" | jq -r .hash)"
  [[ -n "$new" && "$new" != "null" ]] || { echo "update.sh: prefetch failed for $platform" >&2; exit 1; }

  if [[ "$old" == "$new" ]]; then
    echo "    unchanged"
  elif $check_only; then
    # Same URL, different bytes: upstream rewrote a published asset. Every
    # recorded hash for this tag is now suspect, so fail loudly rather than
    # silently "fixing" it — the tag itself has stopped being immutable.
    echo "    DRIFT: recorded $old but upstream now serves $new" >&2
    drift=true
  else
    # Base64 never contains '|', so it is safe as the sed delimiter. Each hash
    # is unique within the file, so a global replace touches exactly one line.
    sed -i "s|$old|$new|" "$file"
    echo "    $new"
  fi
done

if $check_only; then
  if $drift; then
    echo "lightpanda-bin: hash drift detected for $current" >&2
    exit 1
  fi
  echo "lightpanda-bin: all recorded hashes match upstream"
  exit 0
fi

sed -i "s|^  version = \"$current\";|  version = \"$latest\";|" "$file"
echo "lightpanda-bin: updated to $latest — review the diff, then build before committing."
