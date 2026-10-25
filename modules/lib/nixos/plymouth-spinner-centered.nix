{
  flake.nixosModules.plymouth-spinner-centered = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.lumina.plymouth.spinnerCentered;
    inherit (cfg) alignment;
    theme = pkgs.runCommand "plymouth-theme-spinner-centered" {} ''
      d=$out/share/plymouth/themes/spinner-centered
      src=${config.boot.plymouth.package}/share/plymouth/themes/spinner
      mkdir -p $d
      cp $src/*.png $d/
      rm -f $d/watermark.png
      cp ${cfg.logo} $d/watermark.png
      sed \
        -e "s,^Name=.*,Name=Spinner Centered," \
        -e "s,^ImageDir=.*,ImageDir=$d," \
        -e "/^\(Watermark\)\?\(Horizontal\|Vertical\)Alignment=/d" \
        -e "/^\[two-step\]/a HorizontalAlignment=${alignment.spinner.horizontal}\nVerticalAlignment=${alignment.spinner.vertical}\nWatermarkHorizontalAlignment=${alignment.watermark.horizontal}\nWatermarkVerticalAlignment=${alignment.watermark.vertical}" \
        $src/spinner.plymouth > $d/spinner-centered.plymouth
    '';
  in {
    options.lumina.plymouth.spinnerCentered = {
      enable = lib.mkEnableOption "the centered Plymouth spinner theme";
      logo = lib.mkOption {
        type = lib.types.path;
        description = "Image used as the Plymouth watermark.";
      };
      alignment = {
        spinner = {
          horizontal = lib.mkOption {
            type = lib.types.str;
            default = ".5";
          };
          vertical = lib.mkOption {
            type = lib.types.str;
            default = ".75";
          };
        };
        watermark = {
          horizontal = lib.mkOption {
            type = lib.types.str;
            default = ".5";
          };
          vertical = lib.mkOption {
            type = lib.types.str;
            default = ".5";
          };
        };
      };
    };

    config = lib.mkIf cfg.enable {
      boot.plymouth = {
        enable = true;
        theme = "spinner-centered";
        themePackages = [theme];
        inherit (cfg) logo;
      };
    };
  };
}
