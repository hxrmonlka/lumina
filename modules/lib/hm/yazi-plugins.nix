{
  flake.homeModules.yazi-plugins = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.lumina.yazi;

    mkPlugin = identifier: spec: let
      parts = lib.splitString ":" identifier;

      repo = builtins.head parts;

      pluginName =
        if builtins.length parts > 1
        then builtins.elemAt parts 1
        else lib.last (lib.splitString "/" repo);

      repoParts = lib.splitString "/" repo;

      owner =
        if builtins.length repoParts == 2
        then builtins.elemAt repoParts 0
        else
          throw ''
            lumina.yazi.plugins: invalid repository "${repo}".
            Expected "owner/repo" or "owner/repo:plugin".
          '';

      repoName = builtins.elemAt repoParts 1;

      src = pkgs.fetchFromGitHub {
        inherit owner;
        repo = repoName;
        rev = spec.rev;
        hash = spec.hash;
      };

      pluginSource =
        if builtins.length parts > 1
        then "${src}/${pluginName}.yazi"
        else src;

      targetName = "${pluginName}.yazi";
    in {
      name = "yazi/plugins/${targetName}";
      value.source = pluginSource;
    };
  in {
    options.lumina.yazi.plugins = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          rev = lib.mkOption {
            type = lib.types.str;
            description = "Pinned Git revision of the plugin.";
          };

          hash = lib.mkOption {
            type = lib.types.str;
            description = "Nix hash of the fetched GitHub source.";
          };
        };
      });

      default = {};

      example = lib.literalExpression ''
        {
          "yazi-rs/plugins:git" = {
            rev = "9a1129c";
            hash = "sha256-...";
          };
        }
      '';
    };

    config = lib.mkIf (cfg.plugins != {}) {
      assertions = [
        {
          assertion = config.programs.yazi.enable;
          message = "lumina.yazi.plugins requires programs.yazi.enable.";
        }
      ];

      home.file = lib.listToAttrs (
        lib.mapAttrsToList mkPlugin cfg.plugins
      );
    };
  };
}
