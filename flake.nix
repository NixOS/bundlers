{
  description = "nix-generators";

  inputs.nix-utils.url = "github:juliosueiras-nix/nix-utils";
  outputs = { self, nixpkgs, nix-utils }: {

    defaultBundler = self.bundlers.toReport;

    bundlers = let
      prog = program: with program; "${outPath}/bin/${if meta?mainProgram then meta.mainProgram else (builtins.parseDrvName name).name}";
    in {

      toRPM = {program,system}: nix-utils.bundlers.rpm {inherit system; program=prog program;};

      toDEB = {program,system}: nix-utils.bundlers.deb {inherit system; program=prog program;};

      toDockerImage = {program, system}: nixpkgs.legacyPackages.${system}.dockerTools.buildLayeredImage {
        name = program.name;
        tag = "latest";
        contents = [ program ];
      };

      toReport = {program, system}:
        import ./default.nix {
          inherit program system;
          pkgs = nixpkgs.legacyPackages.${system};};
        };
    };
}
