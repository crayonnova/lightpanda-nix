# lightpanda-nix

Nix flake packaging the [Lightpanda](https://github.com/lightpanda-io/browser)
headless browser — a prebuilt nightly binary wrapped with `autoPatchelfHook` so
it runs on NixOS (the upstream binary hardcodes `/lib64/ld-linux-x86-64.so.2`,
which does not exist on NixOS).

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

## Updating the pinned nightly

`nightly` is a moving tag. To bump: in `lightpanda.nix`, update `version` (date)
and set `hash = lib.fakeHash;`, rebuild, then copy the `got:` value Nix prints
back into `hash`.
