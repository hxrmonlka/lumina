{...}: {
  flake.homeModules.yazi-plugins = {
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
        PKG_TOML="''${XDG_CONFIG_HOME:-$HOME/.config}/yazi/package.toml"

        INSTALLED=""
        if [ -f "$PKG_TOML" ]; then
          INSTALLED=$(${pkgs.gnused}/bin/sed -n 's/^use = "\(.*\)"/\1/p' "$PKG_TOML")
        fi

        DESIRED="${lib.concatStringsSep " " cfg.plugins}"

        # Delete plugins no longer desired
        for plugin in $INSTALLED; do
          if ! echo " $DESIRED " | grep -q " $plugin "; then
            echo "lumina-yazi-plugins: removing $plugin"
            ya pkg delete "$plugin" || echo "lumina-yazi-plugins: failed to remove $plugin, will retry next activation" >&2
          fi
        done

        # Add plugins not yet installed
        for plugin in $DESIRED; do
          if ! echo " $INSTALLED " | grep -q " $plugin "; then
            echo "lumina-yazi-plugins: adding $plugin"
            ya pkg add "$plugin" || echo "lumina-yazi-plugins: failed to add $plugin, will retry next activation" >&2
          fi
        done
      '';
    };
  };
}
