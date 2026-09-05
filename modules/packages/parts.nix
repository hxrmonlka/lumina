{...}: {
  perSystem = {pkgs, ...}: {
    packages = {
      spicetify-live-apply = pkgs.writeShellApplication {
        name = "spicetify-live-apply";
        runtimeInputs = with pkgs; [spicetify-cli jq coreutils rsync];
        text = ''
          usage() {
            echo "Usage: spicetify-live-apply --base <dir> --colors <json> --live-dir <dir>" >&2
            exit 1
          }

          base=""
          colors=""
          live_dir=""

          while [ "$#" -gt 0 ]; do
            case "$1" in
              --base) base="$2"; shift 2 ;;
              --colors) colors="$2"; shift 2 ;;
              --live-dir) live_dir="$2"; shift 2 ;;
              *) usage ;;
            esac
          done

          [ -n "$base" ] && [ -n "$colors" ] && [ -n "$live_dir" ] || usage
          [ -f "$colors" ] || { echo "spicetify-live-apply: colors file not found: $colors" >&2; exit 1; }

          if [ ! -d "$live_dir/Apps" ]; then
            mkdir -p "$live_dir"
            rsync -a --chmod=Du+w,Fu+w "$base"/ "$live_dir"/
          fi

          theme_dir="$HOME/.config/spicetify/Themes/text"
          mkdir -p "$theme_dir"

          {
            echo "[custom]"
            jq -r 'to_entries[] | "\(.key) = \(.value)"' "$colors"
          } > "$theme_dir/color.ini"

          spicetify config spotify_path "$live_dir"
          spicetify config current_theme text
          spicetify config color_scheme custom
          spicetify apply -n
        '';
      };
    };
  };

  flake.overlays.default = final: prev: {};
}
