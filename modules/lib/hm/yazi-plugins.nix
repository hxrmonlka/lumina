{
  flake.homeModules.yazi-plugins = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.lumina.yazi;

    parsePlugin = identifier: let
      parts = lib.splitString ":" identifier;

      repository = builtins.head parts;
      repositoryParts = lib.splitString "/" repository;

      owner =
        if builtins.length repositoryParts == 2
        then builtins.elemAt repositoryParts 0
        else
          throw ''
            lumina.yazi.plugins: invalid repository "${repository}".

            Expected:
              "owner/repo"
            or:
              "owner/repo:plugin"
          '';

      repo = builtins.elemAt repositoryParts 1;

      requestedName =
        if builtins.length parts == 2
        then builtins.elemAt parts 1
        else null;

      pluginName =
        if requestedName != null
        then requestedName
        else if lib.hasSuffix ".yazi" repo
        then lib.removeSuffix ".yazi" repo
        else repo;
    in {
      inherit owner repo pluginName requestedName;
    };

    mkPlugin = identifier: spec: let
      parsed = parsePlugin identifier;

      src = pkgs.fetchFromGitHub {
        inherit (parsed) owner repo;
        rev = spec.rev;
        hash = spec.hash;
      };

      source =
        if parsed.requestedName != null
        then "${src}/${parsed.pluginName}.yazi"
        else src;
    in {
      name = parsed.pluginName;
      value = source;
    };
  in {
    options.lumina.yazi.plugins = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            rev = lib.mkOption {
              type = lib.types.str;
              description = ''
                Git revision to pin the Yazi plugin to.
              '';
            };

            hash = lib.mkOption {
              type = lib.types.str;
              description = ''
                Nix fixed-output hash for the fetched plugin source.
              '';
            };
          };
        }
      );

      default = {};

      example = lib.literalExpression ''
        {
          "dedukun/bookmarks.yazi" = {
            rev = "9ef1254d8afe88aba21cd56a186f4485dd532ab8";
            hash = "sha256-...";
          };

          "yazi-rs/plugins:chmod" = {
            rev = "58c4f4e2f4835cc9bf6751f39e3f7c574fc7f55a";
            hash = "sha256-...";
          };
        }
      '';

      description = ''
        Declaratively managed Yazi plugins.
      '';
    };

    config = lib.mkIf (cfg.plugins != {}) {
      assertions = [
        {
          assertion = config.programs.yazi.enable;
          message = "lumina.yazi.plugins requires programs.yazi.enable.";
        }
      ];

      programs.yazi.plugins =
        lib.mapAttrs' (
          identifier: spec: let
            plugin = mkPlugin identifier spec;
          in
            lib.nameValuePair plugin.name plugin.value
        )
        cfg.plugins;
    };
  };
}
