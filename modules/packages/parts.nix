{...}: {
  perSystem = {pkgs, ...}: {
    packages = {
      spicetify-live-apply = pkgs.writeShellApplication {
        name = "spicetify-live-apply";
        runtimeInputs = with pkgs; [spicetify-cli jq coreutils rsync crudini];
        text = ''
          usage() {
            echo "Usage: spicetify-live-apply --spotify <dir> --theme-src <dir> --theme-name <name> --colors <json> --live-dir <dir> [--extension <src> <name>]... [--patch <key> <value>]..." >&2
            exit 1
          }

          spotify_src=""
          theme_src=""
          theme_name=""
          colors=""
          live_dir=""
          extensions=()
          patches=()

          while [ "$#" -gt 0 ]; do
            case "$1" in
              --spotify) spotify_src="$2"; shift 2 ;;
              --theme-src) theme_src="$2"; shift 2 ;;
              --theme-name) theme_name="$2"; shift 2 ;;
              --colors) colors="$2"; shift 2 ;;
              --live-dir) live_dir="$2"; shift 2 ;;
              --extension) extensions+=("$2" "$3"); shift 3 ;;
              --patch) patches+=("$2" "$3"); shift 3 ;;
              *) usage ;;
            esac
          done

          [ -n "$spotify_src" ] && [ -n "$theme_src" ] && [ -n "$theme_name" ] && [ -n "$colors" ] && [ -n "$live_dir" ] || usage
          [ -f "$colors" ] || { echo "spicetify-live-apply: colors file not found: $colors" >&2; exit 1; }

          config_home="''${XDG_CONFIG_HOME:-$HOME/.config}/spicetify"
          theme_dir="$config_home/Themes/$theme_name"
          ext_dir="$config_home/Extensions"
          first_run=0

          if [ ! -d "$live_dir/Apps" ]; then
            first_run=1
            mkdir -p "$live_dir"
            rsync -a --chmod=Du+w,Fu+w "$spotify_src"/ "$live_dir"/
          fi

          mkdir -p "$theme_dir" "$ext_dir"
          rsync -a --chmod=Du+w,Fu+w --exclude=color.ini "$theme_src"/ "$theme_dir"/

          ext_names=()
          i=0
          while [ "$i" -lt "''${#extensions[@]}" ]; do
            src="''${extensions[$i]}"
            name="''${extensions[$((i + 1))]}"
            cp -f "$src/$name" "$ext_dir/$name"
            ext_names+=("$name")
            i=$((i + 2))
          done

          {
            echo "[custom]"
            jq -r 'to_entries[] | "\(.key) = \(.value)"' "$colors"
          } > "$theme_dir/color.ini"

          if [ "$first_run" -eq 1 ]; then
            spicetify config spotify_path "$live_dir"
            spicetify config current_theme "$theme_name"
            spicetify config color_scheme custom

            if [ "''${#ext_names[@]}" -gt 0 ]; then
              spicetify config extensions "''${ext_names[@]}"
            fi

            i=0
            while [ "$i" -lt "''${#patches[@]}" ]; do
              key="''${patches[$i]}"
              value="''${patches[$((i + 1))]}"
              crudini --set "$config_home/config-xpui.ini" Patch "$key" "$value"
              i=$((i + 2))
            done
          fi

          spicetify apply -n
        '';
      };
    };
  };

  flake.overlays.default = final: prev: {};
}
