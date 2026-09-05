{...}: {
  flake.homeModules.lumina-yazi-plugins = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.lumina.yazi;
  in {
    options.lumina.yazi.plugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of yazi plugins to install imperatively via ya pkg add.";
    };

    config = lib.mkIf (cfg.plugins != []) {
      home.activation.luminaYaziPlugins = config.lib.dag.entryAfter ["writeBoundary"] ''
        YAZI_STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/lumina"
        YAZI_PLUGINS_FILE="$YAZI_STATE_DIR/yazi-plugins.txt"

        mkdir -p "$YAZI_STATE_DIR"

        OLD_PLUGINS=""
        if [ -f "$YAZI_PLUGINS_FILE" ]; then
          OLD_PLUGINS=$(cat "$YAZI_PLUGINS_FILE")
        fi

        NEW_PLUGINS="${lib.concatStringsSep " " cfg.plugins}"

        # Delete removed plugins
        for plugin in $OLD_PLUGINS; do
          if ! echo " $NEW_PLUGINS " | grep -q " $plugin "; then
            echo "lumina-yazi-plugins: removing $plugin"
            ya pkg delete "$plugin" || true
          fi
        done

        # Add new plugins
        for plugin in $NEW_PLUGINS; do
          if ! echo " $OLD_PLUGINS " | grep -q " $plugin "; then
            echo "lumina-yazi-plugins: adding $plugin"
            ya pkg add "$plugin" || true
          fi
        done

        echo "$NEW_PLUGINS" > "$YAZI_PLUGINS_FILE"
      '';
    };
  };
}
