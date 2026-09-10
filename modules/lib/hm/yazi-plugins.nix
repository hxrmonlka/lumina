{...}: {
  flake.homeModules.yazi-plugins = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.lumina.yazi;
    desiredPlugins = lib.unique cfg.plugins;
    yaziPackage =
      if config.programs.yazi.package != null
      then config.programs.yazi.finalPackage
      else pkgs.yazi;
  in {
    options.lumina.yazi.plugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Authoritative list of Yazi plugins to reconcile with ya pkg.";
    };

    config = lib.mkIf (cfg.plugins != []) {
      assertions = [
        {
          assertion = config.programs.yazi.enable && config.programs.yazi.package != null;
          message = "lumina.yazi.plugins requires programs.yazi.enable and a non-null programs.yazi.package.";
        }
      ];

      home.activation.luminaYaziPlugins = config.lib.dag.entryAfter ["installPackages"] ''
        export PATH="${lib.makeBinPath [pkgs.git]}:$PATH"

        YA=${lib.escapeShellArg "${yaziPackage}/bin/ya"}
        if [[ -n "''${YAZI_CONFIG_HOME:-}" && "$YAZI_CONFIG_HOME" = /* ]]; then
          YAZI_CONFIG_DIR="$YAZI_CONFIG_HOME"
        elif [[ -n "''${XDG_CONFIG_HOME:-}" && "$XDG_CONFIG_HOME" = /* ]]; then
          YAZI_CONFIG_DIR="$XDG_CONFIG_HOME/yazi"
        else
          YAZI_CONFIG_DIR="$HOME/.config/yazi"
        fi
        PKG_TOML="$YAZI_CONFIG_DIR/package.toml"

        INSTALLED=()
        if [ -f "$PKG_TOML" ]; then
          while IFS= read -r plugin; do
            INSTALLED+=("$plugin")
          done < <(
            ${pkgs.gawk}/bin/awk '
              /^\[\[plugin\.deps\]\]$/ { in_plugin = 1; next }
              /^\[/ { in_plugin = 0 }
              in_plugin && match($0, /^[[:space:]]*use[[:space:]]*=[[:space:]]*"([^"]+)"[[:space:]]*$/, value) {
                print value[1]
                in_plugin = 0
              }
            ' "$PKG_TOML"
          )
        fi

        DESIRED=(${lib.escapeShellArgs desiredPlugins})

        contains_plugin() {
          local needle="$1"
          shift

          local plugin
          for plugin in "$@"; do
            if [ "$plugin" = "$needle" ]; then
              return 0
            fi
          done
          return 1
        }

        plugin_target() {
          local plugin="$1"
          local name

          if [[ "$plugin" == *:* ]]; then
            name="''${plugin#*:}"
          else
            name="''${plugin#*/}"
          fi

          printf '%s/plugins/%s.yazi' "$YAZI_CONFIG_DIR" "$name"
        }

        # Refuse to overwrite plugin directories that are not tracked by ya.
        unmanaged=0
        for plugin in "''${DESIRED[@]}"; do
          if ! contains_plugin "$plugin" "''${INSTALLED[@]}"; then
            target="$(plugin_target "$plugin")"
            if [ -e "$target" ] || [ -L "$target" ]; then
              echo "lumina-yazi-plugins: $plugin is declared but $target is not tracked in package.toml" >&2
              printf 'lumina-yazi-plugins: move it aside with: mv -- %q %q\n' "$target" "$target.lumina-backup" >&2
              unmanaged=1
            fi
          fi
        done

        if [ "$unmanaged" -ne 0 ]; then
          echo "lumina-yazi-plugins: refusing to overwrite unmanaged plugin files; move or remove them, then reactivate" >&2
          exit 1
        fi

        # Delete plugins no longer desired
        for plugin in "''${INSTALLED[@]}"; do
          if ! contains_plugin "$plugin" "''${DESIRED[@]}"; then
            echo "lumina-yazi-plugins: removing $plugin"
            if ! "$YA" pkg delete "$plugin"; then
              echo "lumina-yazi-plugins: failed to remove $plugin" >&2
              exit 1
            fi
          fi
        done

        # Add plugins not yet installed
        for plugin in "''${DESIRED[@]}"; do
          if ! contains_plugin "$plugin" "''${INSTALLED[@]}"; then
            echo "lumina-yazi-plugins: adding $plugin"
            if ! "$YA" pkg add "$plugin"; then
              echo "lumina-yazi-plugins: failed to add $plugin" >&2
              exit 1
            fi
          fi
        done
      '';
    };
  };
}
