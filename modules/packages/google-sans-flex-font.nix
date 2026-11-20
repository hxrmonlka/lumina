{lib, ...}: {
  perSystem = {pkgs, ...}: let
    pname = "google-sans-flex-font";
    version = "5.000";

    src = pkgs.fetchurl {
      url = "https://github.com/googlefonts/googlesans-flex/releases/download/v${version}/GoogleSansFlex-v${version}.zip";
      hash = "sha256-wgsAh43YAdG/wG13FzJEeUDHJVv5TPU4zgECx/sG+oU=";
    };

    licenseFile = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/googlefonts/googlesans-flex/v${version}/OFL.txt";
      hash = "sha256-gxtuBBcFhzw+bvsYxMliArxByL5CpFbT0mxHq/FIFtA=";
    };
  in {
    packages.${pname} = pkgs.stdenvNoCC.mkDerivation {
      inherit pname version src licenseFile;

      nativeBuildInputs = [pkgs.unzip];

      sourceRoot = ".";

      installPhase = ''
        runHook preInstall
        install -Dm444 -t $out/share/fonts/truetype/google-sans-flex *.ttf
        install -Dm444 $licenseFile $out/share/licenses/${pname}/OFL.txt
        runHook postInstall
      '';

      meta = {
        description = "Google Sans Flex, a geometric sans-serif variable font";
        longDescription = ''
          Single variable TTF covering the full design space.

          Axes: opsz 1 to 144, wght 1 to 1000, wdth 25 to 151,
          ROND 0 to 100, slnt -10 to 0.
        '';
        homepage = "https://fonts.google.com/specimen/Google+Sans+Flex";
        changelog = "https://github.com/googlefonts/googlesans-flex/releases/tag/v${version}";
        license = lib.licenses.ofl;
        platforms = lib.platforms.all;
      };
    };
  };
}
