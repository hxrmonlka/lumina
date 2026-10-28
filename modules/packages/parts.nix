{...}: {
  perSystem = {pkgs, ...}: {
    packages = {
      spicetify-live-apply = pkgs.writeShellApplication {
        name = "spicetify-live-apply";
        runtimeInputs = with pkgs; [spicetify-cli jq coreutils gnused rsync crudini];
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
          [ -d "$spotify_src" ] || { echo "spicetify-live-apply: Spotify source directory not found: $spotify_src" >&2; exit 1; }
          [ -d "$theme_src" ] || { echo "spicetify-live-apply: theme source directory not found: $theme_src" >&2; exit 1; }
          [ -f "$colors" ] || { echo "spicetify-live-apply: colors file not found: $colors" >&2; exit 1; }
          jq -e 'type == "object" and length > 0 and all(.[]; type == "string" and test("^[0-9A-Fa-f]{6}$"))' "$colors" >/dev/null || {
            echo "spicetify-live-apply: color values must be six-digit hexadecimal strings without #." >&2
            exit 1
          }

          config_home="''${XDG_CONFIG_HOME:-$HOME/.config}/spicetify"
          theme_dir="$config_home/Themes/$theme_name"
          ext_dir="$config_home/Extensions"
          source_marker="$live_dir.source"
          first_run=0
          source_changed=1
          if [ -f "$source_marker" ] && [ "$(cat "$source_marker")" = "$spotify_src" ]; then
            source_changed=0
          fi

          if [ ! -x "$live_dir/spotify" ] || [ ! -d "$live_dir/Apps" ] || [ "$source_changed" -eq 1 ]; then
            first_run=1
            mkdir -p "$live_dir"
            if [ -f "$source_marker" ]; then
              rsync -a --delete --chmod=Du+w,Fu+w "$spotify_src"/ "$live_dir"/
            else
              rsync -a --chmod=Du+w,Fu+w "$spotify_src"/ "$live_dir"/
            fi
          fi

          [ -x "$live_dir/spotify" ] && [ -x "$live_dir/.spotify-wrapped" ] || {
            echo "spicetify-live-apply: Spotify launcher files are missing from $live_dir." >&2
            exit 1
          }
          sed -i "s|$spotify_src/\\.spotify-wrapped|$live_dir/.spotify-wrapped|g" "$live_dir/spotify"
          grep -Fq "$live_dir/.spotify-wrapped" "$live_dir/spotify" || {
            echo "spicetify-live-apply: could not retarget Spotify launcher to writable copy." >&2
            exit 1
          }

          mkdir -p "$theme_dir" "$ext_dir"
          rsync -a --chmod=Du+w,Fu+w --exclude=color.ini "$theme_src"/ "$theme_dir"/

          ext_names=()
          i=0
          while [ "$i" -lt "''${#extensions[@]}" ]; do
            src="''${extensions[$i]}"
            name="''${extensions[$((i + 1))]}"
            [ -f "$src/$name" ] || { echo "spicetify-live-apply: extension not found: $src/$name" >&2; exit 1; }
            cp -f "$src/$name" "$ext_dir/$name"
            ext_names+=("$name")
            i=$((i + 2))
          done

          color_tmp="$theme_dir/color.ini.tmp"
          color_backup="$theme_dir/color.ini.previous"
          had_previous=0
          color_update_active=0
          if [ -f "$theme_dir/color.ini" ]; then
            cp -f "$theme_dir/color.ini" "$color_backup"
            had_previous=1
          fi
          {
            echo "[custom]"
            jq -r 'to_entries[] | "\(.key) = \(.value)"' "$colors"
          } > "$color_tmp"
          mv -f "$color_tmp" "$theme_dir/color.ini"
          color_update_active=1
          rollback_colors() {
            rc=$?
            trap - EXIT
            if [ "$rc" -ne 0 ] && [ "$color_update_active" -eq 1 ]; then
              if [ "$had_previous" -eq 1 ]; then
                mv -f "$color_backup" "$theme_dir/color.ini" || true
              else
                rm -f "$theme_dir/color.ini" || true
              fi
              spicetify apply -n >/dev/null 2>&1 || true
              echo "spicetify-live-apply: Spicetify update failed; restored the previous color file." >&2
            fi
            exit "$rc"
          }
          trap rollback_colors EXIT

          if [ "$first_run" -eq 1 ]; then
            spicetify config spotify_path "$live_dir"
            spicetify config current_theme "$theme_name"
            spicetify config color_scheme custom

            if [ "''${#ext_names[@]}" -gt 0 ]; then
              old_ifs="$IFS"
              IFS='|'
              extension_config="''${ext_names[*]}"
              IFS="$old_ifs"
              spicetify config extensions "$extension_config"
            fi

            i=0
            while [ "$i" -lt "''${#patches[@]}" ]; do
              key="''${patches[$i]}"
              value="''${patches[$((i + 1))]}"
              crudini --set "$config_home/config-xpui.ini" Patch "$key" "$value"
              i=$((i + 2))
            done
            spicetify backup apply
          fi

          if spicetify apply -n; then
            color_update_active=0
            rm -f "$color_backup" || true
            printf '%s\n' "$spotify_src" > "$source_marker"
          else
            exit 1
          fi
        '';
      };
    };
  };

  flake.overlays.default = final: prev: {};
}
