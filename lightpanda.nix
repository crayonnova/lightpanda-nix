# Prebuilt Lightpanda release binaries, patched to run on NixOS and Darwin.
#
# Deliberately shaped to match nixpkgs conventions for binary redistributions
# (see pkgs/by-name/bu/bun/package.nix) so this file can be submitted upstream
# as `lightpanda-bin` with little more than a path change.
#
# To bump the pinned release, run ./update.sh — do not hand-edit hashes.
{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "lightpanda-bin";
  version = "0.3.7";

  src =
    finalAttrs.passthru.sources.${stdenvNoCC.hostPlatform.system}
      or (throw "Unsupported system: ${stdenvNoCC.hostPlatform.system}");

  # src is a bare executable (ELF on Linux, Mach-O on Darwin), not an archive.
  dontUnpack = true;
  strictDeps = true;

  # Linux only: upstream hardcodes /lib64/ld-linux-x86-64.so.2 as the ELF
  # interpreter. On NixOS that path holds only a stub loader that prints an
  # error, so autoPatchelfHook repoints it at glibc's real loader in the store
  # and fills in RUNPATH for anything else the binary needs.
  #
  # The Mach-O binaries need no equivalent: `llvm-otool -L` shows only absolute
  # system paths (CoreFoundation, SystemConfiguration, Security, libSystem,
  # libobjc), all resolved from the dyld shared cache. No @rpath, no /usr/local.
  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];

  # No buildInputs: V8 and libcurl are linked in statically (hence the ~150 MB
  # binary), leaving only libm/libc/ld-linux, which all come from glibc and are
  # always in scope. autoPatchelfHook fails the build if that stops being true.
  # Re-check with: patchelf --print-needed result/bin/lightpanda

  # Darwin only: the Mach-O binaries ship an LC_CODE_SIGNATURE (Zig ad-hoc signs
  # them). Stripping rewrites the file and invalidates that signature, after
  # which the arm64 kernel refuses to exec it. Copy the bytes through untouched.
  dontStrip = stdenvNoCC.hostPlatform.isDarwin;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/lightpanda
    runHook postInstall
  '';

  passthru = {
    # Keyed by Nix system string. Note that this does NOT match upstream's asset
    # naming on Darwin: Nix says `-darwin`, upstream says `-macos`, so each URL
    # spells its asset name out in full rather than interpolating the key.
    # Lives in passthru (rather than a let binding) so update tooling can reach
    # each source as `lightpanda-bin.sources.<system>`.
    sources = {
      "x86_64-linux" = fetchurl {
        url = "https://github.com/lightpanda-io/browser/releases/download/${finalAttrs.version}/lightpanda-x86_64-linux";
        hash = "sha256-iVM5sCIFFxoYHd50OuAGi7RWSIQHb+rISCusqcISqlo=";
      };
      "aarch64-linux" = fetchurl {
        url = "https://github.com/lightpanda-io/browser/releases/download/${finalAttrs.version}/lightpanda-aarch64-linux";
        hash = "sha256-TA7LKLT8+21bzoLshuFfxs3onOoWjPOEBJTw7iZ1WFI=";
      };
      "x86_64-darwin" = fetchurl {
        url = "https://github.com/lightpanda-io/browser/releases/download/${finalAttrs.version}/lightpanda-x86_64-macos";
        hash = "sha256-XhGLbpHCzMsc5/DTT8OdqyYrlH5N6impCxp1uTmdeGI=";
      };
      "aarch64-darwin" = fetchurl {
        url = "https://github.com/lightpanda-io/browser/releases/download/${finalAttrs.version}/lightpanda-aarch64-macos";
        hash = "sha256-rplULYGvIwhyluwDersNV6VwAlAvX/TBsLBd+khLebg=";
      };
    };

    updateScript = ./update.sh;
  };

  meta = {
    description = "Headless browser designed for AI and automation";
    homepage = "https://github.com/lightpanda-io/browser";
    changelog = "https://github.com/lightpanda-io/browser/releases/tag/${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    # Prebuilt upstream artifacts, not compiled from source here.
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "lightpanda";
    # Single source of truth: adding a source above adds the platform.
    # The Darwin binaries carry LC_BUILD_VERSION minos 14.8.7, so they will not
    # run on older macOS. Nix has no way to express that, hence this note.
    platforms = builtins.attrNames finalAttrs.passthru.sources;
    # Add your nixpkgs maintainer handle here before upstreaming.
    maintainers = [ ];
  };
})
