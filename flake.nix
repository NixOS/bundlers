# First draft of this flake include a large amount of cruft to be compatible
# with both pre and post Nix 2.6 APIs.
#
# The expected state is to support bundlers of the form:
# bundlers.<system>.<name> = drv: some-drv;

{
  description = "Example bundlers";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nix-utils.url = "github:juliosueiras-nix/nix-utils";
  inputs.nix-bundle = {
    url = "github:nix-community/nix-bundle";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.nix-appimage = {
    url = "github:ralismark/nix-appimage";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix-bundle, nix-appimage, nix-utils }: let
      inherit (nixpkgs) lib;
      # System types to support.
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });

      # Backwards compatibility helper for pre Nix2.6 bundler API
      # TODO: The upstreams of the bundlers using this should be updated to use the new api like nix-bundle was.
      getExe =
        x:
        lib.getExe' x (
          x.meta.mainProgram or (lib.warn
            "nix-bundle: Package ${
              lib.strings.escapeNixIdentifier x.meta.name or x.pname or x.name
            } does not have the meta.mainProgram attribute. Assuming you want '${lib.getName x}'."
            lib.getName
            x
          )
        );

      protect = drv: if drv?outPath then drv else throw "provided installable is not a derivation and not coercible to an outPath";
  in {
    bundlers =
      (forAllSystems (system: rec {

      default = toArx;
      toArx = nix-bundle.bundlers.${system}.nix-bundle;

      toRPM = drv: nix-utils.bundlers.rpm {inherit system; program=getExe drv;};

      toDEB = drv: nix-utils.bundlers.deb {inherit system; program=getExe drv;};

      toDockerImage = {...}@drv:
        (nixpkgs.legacyPackages.${system}.dockerTools.buildLayeredImage {
          name = drv.name or drv.pname or "image";
          tag = "latest";
          contents = if drv?outPath then drv else throw "provided installable is not a derivation and not coercible to an outPath";
      });

      toBuildDerivation = drv:
        (import ./report/default.nix {
          drv = protect drv;
          pkgs = nixpkgsFor.${system};}).buildtimeDerivations;

      toReport = drv:
        (import ./report/default.nix {
          drv = protect drv;
          pkgs = nixpkgsFor.${system};}).runtimeReport;

      toAppImage = nix-appimage.bundlers.${system}.default;

      identity = drv: drv;
    }
    ));
  };
}
