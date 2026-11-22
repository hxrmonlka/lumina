{inputs, ...}: {
  perSystem = {pkgs, ...}: let
    system = pkgs.stdenv.hostPlatform.system;
    m3shapes = inputs.m3shapes.packages.${system}.m3shapes;
    qmlImportPath = "${m3shapes}/${pkgs.qt6.qtbase.qtQmlPrefix}";
  in {
    packages.m3shapes = m3shapes;

    packages.shoji-cli = pkgs.stdenv.mkDerivation {
      pname = "shoji-cli";
      version = "unstable";
      src = "${inputs.shoji}/cli";
      nativeBuildInputs = [pkgs.gnumake pkgs.makeWrapper];
      buildPhase = "make";
      # installPhase = "make install PREFIX=$out";
      installPhase = ''
        runHook preInstall
        make install PREFIX=$out
        runHook postInstall
      '';
      postInstall = ''
        wrapProgram "$out/bin/shoji" \
          --prefix QML_IMPORT_PATH : "${qmlImportPath}"
      '';
      meta = {
        description = "Command-line interface for the Shoji Quickshell desktop environment";
        mainProgram = "shoji";
        platforms = pkgs.lib.platforms.linux;
      };
    };

    packages.shoji-shell = pkgs.stdenvNoCC.mkDerivation {
      pname = "shoji-shell";
      version = "unstable";
      src = inputs.shoji;
      dontBuild = true;
      installPhase = ''
        mkdir -p "$out/share/quickshell/shoji"
        cp -R . "$out/share/quickshell/shoji/"
      '';
      meta = {
        description = "Shoji Quickshell configuration";
        platforms = pkgs.lib.platforms.linux;
      };
    };
  };
}
