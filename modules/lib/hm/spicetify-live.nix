{self, ...}: {
  flake.homeModules.spicetify-live = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.lumina.spicetify;
    system = pkgs.stdenv.hostPlatform.system;
    liveApply = self.packages.${system}.spicetify-live-apply;
    fallbackColors = pkgs.writeText "lumina-spicetify-fallback-colors.json" (builtins.toJSON cfg.colors.fallback);
    extensionArgs = lib.concatMapStringsSep "\n" (extension: ''
      args+=(--extension ${lib.escapeShellArg (toString extension.src)} ${lib.escapeShellArg extension.name})
    '') cfg.extensions;
    patchArgs = lib.concatStringsSep "\n" (lib.mapAttrsToList (key: value: ''
      args+=(--patch ${lib.escapeShellArg key} ${lib.escapeShellArg value})
    '') cfg.theme.patches);
    applyCommand = pkgs.writeShellApplication {
      name = "lumina-spicetify-apply";
      runtimeInputs = [liveApply];
      excludeShellChecks = ["SC2016"];
      text = ''
        colors=${lib.escapeShellArg cfg.colors.file}
        if [ ! -f "$colors" ]; then
          colors=${lib.escapeShellArg (toString fallbackColors)}
        fi
        args=(
          --spotify ${lib.escapeShellArg "${cfg.spotifyPackage}/share/spotify"}
          --theme-src ${lib.escapeShellArg (toString cfg.theme.src)}
          --theme-name ${lib.escapeShellArg cfg.theme.name}
          --colors "$colors"
          --live-dir ${lib.escapeShellArg cfg.liveDir}
        )
        ${extensionArgs}
        ${patchArgs}
        exec ${lib.getExe liveApply} "''${args[@]}"
      '';
    };
    spotifyLauncher = pkgs.writeShellApplication {
      name = "spotify";
      runtimeInputs = [applyCommand];
      text = ''
        lumina-spicetify-apply
        exec ${lib.escapeShellArg "${cfg.liveDir}/spotify"} "$@"
      '';
    };
  in {
    options.lumina.spicetify = {
      enable = lib.mkEnableOption "Lumina's runtime Spicetify integration";

      spotifyPackage = lib.mkOption {
        type = lib.types.package;
        default = pkgs.spotify;
        description = "Unmodified Spotify package used as the live installation source.";
      };

      liveDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.xdg.dataHome}/spotify-lumina-live";
        description = "Writable directory used for the Spicetify-managed Spotify installation.";
      };

      theme = {
        name = lib.mkOption {
          type = lib.types.str;
          default = "Default";
          description = "Name of the installed Spicetify theme directory.";
        };

        src = lib.mkOption {
          type = lib.types.nullOr lib.types.pathInStore;
          default = null;
          description = "Store path containing the theme source.";
        };

        patches = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Spicetify XPUI patch entries managed by Lumina.";
        };
      };

      colors = {
        file = lib.mkOption {
          type = lib.types.str;
          default = "${config.xdg.stateHome}/lumina/spicetify/colors.json";
          description = "Runtime JSON file containing six-digit hexadecimal color values.";
        };

        fallback = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Fallback Spicetify palette used before the runtime color file exists.";
        };
      };

      extensions = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            src = lib.mkOption {
              type = lib.types.pathInStore;
              description = "Store path containing the extension file.";
            };
            name = lib.mkOption {
              type = lib.types.str;
              description = "Extension filename copied into the Spicetify Extensions directory.";
            };
          };
        });
        default = [];
        description = "Extensions installed and managed by Lumina.";
      };

      watchColors = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Apply the palette when the runtime color file changes.";
      };

      desktopEntry.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install a Spotify desktop entry that launches the managed installation.";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = pkgs.stdenv.hostPlatform.isLinux;
          message = "lumina.spicetify is supported on Linux only.";
        }
        {
          assertion = !(lib.attrByPath ["programs" "spicetify" "enable"] false config);
          message = "lumina.spicetify cannot be enabled together with programs.spicetify.enable.";
        }
        {
          assertion = cfg.theme.src != null;
          message = "lumina.spicetify.theme.src must be set when the integration is enabled.";
        }
        {
          assertion = cfg.theme.name != "" && cfg.theme.name != "." && cfg.theme.name != ".." && !(lib.hasInfix "/" cfg.theme.name);
          message = "lumina.spicetify.theme.name must be a non-empty directory name.";
        }
        {
          assertion = lib.hasPrefix "/" cfg.colors.file;
          message = "lumina.spicetify.colors.file must be an absolute path.";
        }
        {
          assertion = lib.hasPrefix "/" cfg.liveDir && cfg.liveDir != "/";
          message = "lumina.spicetify.liveDir must be an absolute path other than the filesystem root.";
        }
        {
          assertion = cfg.colors.fallback != {} && lib.all (value: builtins.match "^[0-9A-Fa-f]{6}$" value != null) (lib.attrValues cfg.colors.fallback);
          message = "lumina.spicetify.colors.fallback must contain six-digit hexadecimal color values without #.";
        }
        {
          assertion = lib.length (lib.unique (map (extension: extension.name) cfg.extensions)) == lib.length cfg.extensions;
          message = "lumina.spicetify.extensions must not contain duplicate filenames.";
        }
        {
          assertion = lib.all (extension: extension.name != "" && extension.name != "." && extension.name != ".." && !(lib.hasInfix "/" extension.name) && !(lib.hasInfix "|" extension.name)) cfg.extensions;
          message = "lumina.spicetify.extensions contains an invalid filename.";
        }
      ];

      home.activation.luminaSpicetifyColorsDirectory = lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg (builtins.dirOf cfg.colors.file)}
      '';

      home.packages = [applyCommand spotifyLauncher];

      xdg.desktopEntries.spotify = lib.mkIf cfg.desktopEntry.enable {
        name = "Spotify";
        genericName = "Music Player";
        exec = "${spotifyLauncher}/bin/spotify %U";
        icon = "${cfg.spotifyPackage}/share/spotify/icons/spotify-linux-256.png";
        terminal = false;
        type = "Application";
        categories = ["AudioVideo" "Audio" "Player"];
        mimeType = ["x-scheme-handler/spotify"];
      };

      systemd.user.services.lumina-spicetify-apply = lib.mkIf cfg.watchColors {
        Unit.Description = "Apply the Lumina-managed Spicetify configuration";
        Service = {
          Type = "oneshot";
          ExecStart = "${applyCommand}/bin/lumina-spicetify-apply";
        };
      };

      systemd.user.paths.lumina-spicetify-colors = lib.mkIf cfg.watchColors {
        Unit.Description = "Watch the runtime Spotify color palette";
        Path = {
          PathChanged = [cfg.colors.file (builtins.dirOf cfg.colors.file)];
          Unit = "lumina-spicetify-apply.service";
        };
        Install.WantedBy = ["default.target"];
      };
    };
  };
}
