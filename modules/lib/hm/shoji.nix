{self, ...}: {
  flake.homeModules.shoji = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.programs.shoji;
    system = pkgs.stdenv.hostPlatform.system;
    cli = self.packages.${system}.shoji-cli;
    shell = self.packages.${system}.shoji-shell;
  in {
    options.programs.shoji = {
      enable = lib.mkEnableOption "the Shoji desktop shell and command-line interface";

      cli.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the Shoji command-line interface.";
      };

      config = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Deploy the Shoji Quickshell configuration.";
        };

        target = lib.mkOption {
          type = lib.types.str;
          default = "quickshell/shoji";
          description = "Relative path below XDG_CONFIG_HOME where the Shoji configuration is deployed.";
        };
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !cfg.config.enable || (cfg.config.target != "" && !(lib.hasPrefix "/" cfg.config.target) && !(lib.hasInfix ".." cfg.config.target));
          message = "programs.shoji.config.target must be a non-empty relative path without parent-directory components.";
        }
      ];

      home.packages = lib.optionals cfg.cli.enable [cli];

      xdg.configFile = lib.mkIf cfg.config.enable {
        ${cfg.config.target} = {
          source = "${shell}/share/quickshell/shoji";
          recursive = true;
        };
      };
    };
  };
}
