{self, ...}: {
  flake.homeModules.lumina-cli = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.programs.lumina-cli;
  in {
    options.programs.lumina-cli = {
      enable = lib.mkEnableOption "the Lumina command line tool";

      configPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/home/alice/alice";
        description = ''
          Path to the local copy of Alice.
          Sets the ALICE_DOTFILES variable for the Lumina CLI.
          Use a string. A Nix path would copy the directory into the Nix store.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [self.packages.${pkgs.stdenv.hostPlatform.system}.lumina-cli];

      home.sessionVariables = lib.mkIf (cfg.configPath != null) {
        ALICE_DOTFILES = cfg.configPath;
      };
    };
  };
}
