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

repo="lightpanda-io/browser"
file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lightpanda.nix"

current="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$file")"
[[ -n "$current" ]] || { echo "update.sh: could not read current version" >&2; exit 1; }

# Do NOT use /releases/latest here. Upstream does not mark its rolling
# `nightly` release as a prerelease, so GitHub reports `nightly` as "latest"
# and that endpoint will happily pin you to a moving tag whose assets are
# replaced in place — making every recorded hash a lie on the next rebuild.
# Require a semver tag instead; the API returns releases newest-first.
latest="$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=100" | jq -r '
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

  # Base64 never contains '|', so it is safe as the sed delimiter. Each hash is
  # unique within the file, so a global replace touches exactly one line.
  if [[ "$old" == "$new" ]]; then
    echo "    unchanged"
  else
    sed -i "s|$old|$new|" "$file"
    echo "    $new"
  fi
done

sed -i "s|^  version = \"$current\";|  version = \"$latest\";|" "$file"
echo "lightpanda-bin: updated to $latest — review the diff, then build before committing."
