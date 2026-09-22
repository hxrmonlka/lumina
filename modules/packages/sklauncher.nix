{
  inputs,
  lib,
  ...
}: {
  perSystem = {system, ...}: let
    pname = "sklauncher";
    version = "4.0.52";

    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfreePredicate = pkg:
        builtins.elem (lib.getName pkg) [pname];
    };

    src = pkgs.fetchurl {
      url = "https://github.com/sklauncher/binaries/releases/download/v${version}/SKlauncher-${version}-x86_64.AppImage";
      hash = "sha256-yCSguMTxVEsQ9OzOGLoG1MKo0S/zsiRjgzY2Hg3KzEc=";
    };

    appimageContents = pkgs.appimageTools.extract {inherit pname version src;};
  in {
    packages.sklauncher = pkgs.appimageTools.wrapType2 {
      inherit pname version src;

      extraInstallCommands = ''
        install -Dm444 ${appimageContents}/pl.skmedix.sklauncher.desktop \
          $out/share/applications/pl.skmedix.sklauncher.desktop
        install -Dm444 ${appimageContents}/usr/share/icons/hicolor/512x512/apps/sklauncher.png \
          $out/share/icons/hicolor/512x512/apps/sklauncher.png

        substituteInPlace $out/share/applications/pl.skmedix.sklauncher.desktop \
          --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=${pname} %U'
      '';

      meta = {
        description = "Minecraft: Java Edition launcher with instance and mod management";
        homepage = "https://skmedix.pl/";
        downloadPage = "https://next.skmedix.pl/downloads/linux";
        changelog = "https://github.com/sklauncher/binaries/releases/tag/v${version}";
        license = lib.licenses.unfree;
        sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
        mainProgram = pname;
        platforms = ["x86_64-linux"];
      };
    };
  };
}
