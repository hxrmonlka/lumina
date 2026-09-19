{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    packages.fastfetch-source = pkgs.stdenvNoCC.mkDerivation {
      pname = "fastfetch-source";
      version = "unstable";
      src = inputs.fastfetch;

      installPhase = ''
        mkdir -p $out
        cp fastfetch-source.jpg $out/fastfetch-source.jpg
      '';
    };
  };
}
