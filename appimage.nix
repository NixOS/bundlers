{nixpkgsFor,lib,nixpkgs,nix-bundle,program,system ? "x86_64-linux"}:
    drv: with nixpkgsFor.${system}; let
        closure = closureInfo {rootPaths = [drv];};
        prog = program drv;
        system = drv.system;
        nixpkgs' = nixpkgs.legacyPackages.${system};
        muslPkgs = import nixpkgs {
          localSystem.config = "x86_64-unknown-linux-musl";
        };
        pkgs = nixpkgs.legacyPackages.${system};
        appdir = pkgs.callPackage (nix-bundle + "/appdir.nix") { inherit muslPkgs; };

        env = appdir {
          name = "hello";
          target =
          buildEnv {
            name = "hello";
            paths = [drv (
              runCommand "appdir" {buildInputs = [imagemagick];} ''
                mkdir -p $out/share/applications
                mkdir -p $out/share/icons/hicolor/256x256/apps
                convert -size 256x256 xc:#990000 ${nixpkgs.lib.attrByPath ["meta" "icon"] "$out/share/icons/hicolor/256x256/apps/icon.png" drv}
                cat <<EOF > $out/share/applications/out.desktop
                [Desktop Entry]
                Type=Application
                Version=1.0
                Name=${drv.pname or drv.name}
                Comment=${nixpkgs.lib.attrByPath ["meta" "description"] "Bundled by toAppImage" drv}
                Path=${drv}/bin
                Exec=${prog}
                Icon=icon
                Terminal=true
                Categories=${nixpkgs.lib.attrByPath ["meta" "categories"] "Utility" drv};
                EOF
                ''
              )];
          };
        };
      in
      runCommand drv.name {
        buildInputs = [ patchelfUnstable appimagekit ];
      dontFixup = true;
    } ''
      cp -rL ${env}/*.AppDir out.AppDir
      chmod +w -R ./out.AppDir
      cp out.AppDir/usr/share/applications/out.desktop out.AppDir
      cp out.AppDir/usr/share/icons/hicolor/256x256/apps/icon.png out.AppDir/.DirIcon
      cp out.AppDir/usr/share/icons/hicolor/256x256/apps/icon.png out.AppDir/.
      ARCH=x86_64 appimagetool out.AppDir
      cp *.AppImage $out
      ''
