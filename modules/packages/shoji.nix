{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    packages.shoji-cli = pkgs.stdenv.mkDerivation {
      pname = "shoji-cli";
      version = "unstable";
      src = "${inputs.shoji}/cli";
      nativeBuildInputs = [pkgs.gnumake];
      buildPhase = "make";
      installPhase = "make install PREFIX=$out";
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
