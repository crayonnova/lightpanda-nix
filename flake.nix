{
  description = "Lightpanda headless browser (prebuilt nightly), packaged for Nix";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # Subset of passthru.sources in lightpanda.nix that this flake's pinned
      # nixpkgs can evaluate. x86_64-darwin is deliberately absent: nixpkgs
      # 26.11 dropped it, so `legacyPackages.x86_64-darwin` throws and would
      # take every other output down with it. The source stays in
      # passthru.sources for overlay consumers on an older nixpkgs.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAll = nixpkgs.lib.genAttrs systems;
    in
    {
      # Consumers can add this overlay to get `pkgs.lightpanda-bin` everywhere.
      overlays.default = final: prev: {
        # `-bin` matches the nixpkgs convention for prebuilt redistributions,
        # leaving the plain name free for a future source build. The alias
        # keeps `pkgs.lightpanda` working.
        lightpanda-bin = final.callPackage ./lightpanda.nix { };
        lightpanda = final.lightpanda-bin;
      };

      # Home Manager module providing `services.lightpanda.enable = true;`.
      homeModules.default = import ./hm-module.nix { inherit self; };

      # Or reference the package directly: inputs.lightpanda.packages.<system>.default
      packages = forAll (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          lightpanda-bin = pkgs.callPackage ./lightpanda.nix { };
          lightpanda = self.packages.${system}.lightpanda-bin;
          default = self.packages.${system}.lightpanda-bin;
        }
      );
    };
}
