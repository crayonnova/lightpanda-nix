{
  description = "Lightpanda headless browser (prebuilt nightly), packaged for Nix";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
    in
    {
      # Consumers can add this overlay to get `pkgs.lightpanda` everywhere.
      overlays.default = final: prev: {
        lightpanda = final.callPackage ./lightpanda.nix { };
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
          lightpanda = pkgs.callPackage ./lightpanda.nix { };
          default = self.packages.${system}.lightpanda;
        }
      );
    };
}
