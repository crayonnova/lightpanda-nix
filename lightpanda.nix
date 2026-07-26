{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "lightpanda";
  # `nightly` is a moving tag: bump `version` (date) and `src.hash` together
  # when you want a newer build. To refresh the hash, set it to
  # lib.fakeHash, rebuild, and copy the "got:" value Nix prints.
  version = "nightly-2026-07-26";

  src = fetchurl {
    url = "https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-x86_64-linux";
    hash = "sha256-uaew+sXDkkxuaHgfzEGA5bXJHmEdw7WCr3qThdhaMqE=";
  };

  # src is a bare ELF binary, not an archive.
  dontUnpack = true;

  # autoPatchelfHook rewrites the /lib64/ld-linux interpreter (which does not
  # exist on NixOS) to the one in the Nix store, and fixes the rpath.
  nativeBuildInputs = [ autoPatchelfHook ];

  # The binary only dynamically needs glibc (libc.so.6 / libm.so.6); V8 and
  # libcurl are statically linked in (hence the ~150 MB size).
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/lightpanda
    runHook postInstall
  '';

  meta = {
    description = "Headless browser designed for AI and automation (prebuilt nightly)";
    homepage = "https://github.com/lightpanda-io/browser";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "lightpanda";
  };
})
