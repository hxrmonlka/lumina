{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    packages.grub-theme = pkgs.stdenvNoCC.mkDerivation {
      pname = "grub-theme";
      version = "unstable";
      src = "${inputs.grub-theme}/BlueArchiveGrub";

      installPhase = ''
        bash ./install.sh --generate $out/grub/themes --theme tela --icon color --screen 1080p
      '';
    };
  };
}
