{
  description = "Example bundlers";

  inputs.nix-utils.url = "github:juliosueiras-nix/nix-utils";
  inputs.nix-bundle.url = "github:matthewbauer/nix-bundle";

  outputs = { self, nixpkgs, nix-bundle, nix-utils }: let
      # System types to support.
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });

      # Backwards compatibility helper for previous bundler API
      program = p: with p; "${outPath}/bin/${
        if meta?mainProgram then
          meta.mainProgram
        else
          (builtins.parseDrvName name).name
      }";
  in {

    # defaultBundler.x86_64-linux = forAllSystems (system: self.bundlers.${system}.toArx);
    defaultBundler.x86_64-linux = self.bundlers.x86_64-linux.toArx;

    bundlers = forAllSystems (system: {
      toArx = drv: nix-bundle.bundlers.nix-bundle {inherit system; program=program drv;};

      toRPM = drv: nix-utils.bundlers.rpm {inherit system; program=program drv;};

      toDEB = drv: nix-utils.bundlers.deb {inherit system; program=program drv;};

      toDockerImage = drv:
        nixpkgs.legacyPackages.${system}.dockerTools.buildLayeredImage {
          name = drv.name;
          tag = "latest";
          contents = [ drv ];
      };

      toBuildDerivation = drv:
        (import ./default.nix {
          inherit drv;
          pkgs = nixpkgsFor.${system};}).buildtimeDerivations;

      toReport = drv:
         builtins.trace drv
        (import ./default.nix {
          inherit drv;
          pkgs = nixpkgsFor.${system};}).runtimeReport;

      identity = drv: drv;
    });
  };
}
