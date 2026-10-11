{lib, ...}: {
  perSystem = {pkgs, ...}: let
    pname = "libron-font";
    version = "0.30";
  in {
    packages.libron-font = pkgs.stdenvNoCC.mkDerivation {
      inherit pname version;

      src = pkgs.fetchurl {
        url = "https://github.com/nicoverbruggen/libron/releases/download/v${version}/Libron.zip";
        hash = "sha256-lEGTe52r2c3/yeDtMpaFu3MPIU/nnlyK50mxdMPgXh0=";
      };

      nativeBuildInputs = [pkgs.unzip];

      sourceRoot = ".";

      installPhase = ''
        runHook preInstall
        install -Dm444 -t $out/share/fonts/truetype/libron *.ttf
        runHook postInstall
      '';

      meta = {
        description = "Manually tuned revision of Readerly with reduced serifs, optimized for digital reading";
        homepage = "https://github.com/nicoverbruggen/libron";
        changelog = "https://github.com/nicoverbruggen/libron/releases/tag/v${version}";
        license = lib.licenses.ofl;
        platforms = lib.platforms.all;
      };
    };
  };
}
