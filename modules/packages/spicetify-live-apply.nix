{...}: {
  perSystem = {pkgs, ...}: {
    packages.spicetify-live-apply = pkgs.writeShellApplication {
      name = "spicetify-live-apply";
      runtimeInputs = with pkgs; [spicetify-cli jq coreutils gnused gnugrep rsync crudini util-linux];
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
        state_home="''${XDG_STATE_HOME:-$HOME/.local/state}/lumina/spicetify"
        theme_dir="$config_home/Themes/$theme_name"
        ext_dir="$config_home/Extensions"
        config_file="$config_home/config-xpui.ini"
        source_marker="$live_dir.source"
        manifest="$state_home/manifest.json"

        extension_sources=()
        extension_names=()
        patches_keys=()
        patches_values=()

        i=0
        while [ "$i" -lt "''${#extensions[@]}" ]; do
          src="''${extensions[$i]}"
          name="''${extensions[$((i + 1))]}"
          case "$name" in
            ""|.|..|*/*|*'|'*)
              echo "spicetify-live-apply: invalid extension filename: $name" >&2
              exit 1
              ;;
          esac
          [ -f "$src/$name" ] || { echo "spicetify-live-apply: extension not found: $src/$name" >&2; exit 1; }
          extension_sources+=("$src")
          extension_names+=("$name")
          i=$((i + 2))
        done

        i=0
        while [ "$i" -lt "''${#patches[@]}" ]; do
          key="''${patches[$i]}"
          value="''${patches[$((i + 1))]}"
          [ -n "$key" ] || { echo "spicetify-live-apply: patch key cannot be empty." >&2; exit 1; }
          patches_keys+=("$key")
          patches_values+=("$value")
          i=$((i + 2))
        done

        mkdir -p "$state_home"
        exec 9>"$state_home/lock"
        flock 9

        first_run=0
        if [ ! -x "$live_dir/spotify" ] || [ ! -d "$live_dir/Apps" ] || [ ! -f "$source_marker" ] || [ "$(cat "$source_marker")" != "$spotify_src" ]; then
          first_run=1
        fi

        desired_signature="$(
          {
            printf '%s\0' "$spotify_src" "$theme_src" "$theme_name" "$live_dir"
            sha256sum "$colors" | cut -d ' ' -f 1
            for i in "''${!extension_names[@]}"; do
              printf '%s\0' "''${extension_sources[$i]}" "''${extension_names[$i]}"
            done
            for i in "''${!patches_keys[@]}"; do
              printf '%s\0' "''${patches_keys[$i]}" "''${patches_values[$i]}"
            done
          } | sha256sum | cut -d ' ' -f 1
        )"

        previous_signature=""
        if [ -f "$manifest" ]; then
          previous_signature="$(jq -r '.signature // empty' "$manifest" 2>/dev/null || true)"
        fi

        if [ "$first_run" -eq 0 ] && [ "$desired_signature" = "$previous_signature" ]; then
          exit 0
        fi

        mkdir -p "$live_dir" "$theme_dir" "$ext_dir"
        if [ "$first_run" -eq 1 ]; then
          rsync -a --delete --chmod=Du+w,Fu+w "$spotify_src"/ "$live_dir"/
        fi

        [ -x "$live_dir/spotify" ] && [ -x "$live_dir/.spotify-wrapped" ] || {
          echo "spicetify-live-apply: Spotify launcher files are missing from $live_dir." >&2
          exit 1
        }
        sed -i "s|$spotify_src/\.spotify-wrapped|$live_dir/.spotify-wrapped|g" "$live_dir/spotify"
        grep -Fq "$live_dir/.spotify-wrapped" "$live_dir/spotify" || {
          echo "spicetify-live-apply: could not retarget Spotify launcher to writable copy." >&2
          exit 1
        }

        rsync -a --delete --chmod=Du+w,Fu+w --exclude=/color.ini "$theme_src"/ "$theme_dir"/

        if [ -f "$manifest" ]; then
          while IFS= read -r old_name; do
            [ -n "$old_name" ] || continue
            keep=0
            for name in "''${extension_names[@]}"; do
              if [ "$name" = "$old_name" ]; then
                keep=1
                break
              fi
            done
            if [ "$keep" -eq 0 ]; then
              rm -f "$ext_dir/$old_name"
            fi
          done < <(jq -r '.extensions[]? // empty' "$manifest")
        fi

        for i in "''${!extension_names[@]}"; do
          cp -f "''${extension_sources[$i]}/''${extension_names[$i]}" "$ext_dir/''${extension_names[$i]}"
        done

        mkdir -p "$config_home"
        spicetify config spotify_path "$live_dir" current_theme "$theme_name" color_scheme custom

        extension_config=""
        for name in "''${extension_names[@]}"; do
          if [ -n "$extension_config" ]; then
            extension_config+="|"
          fi
          extension_config+="$name"
        done
        crudini --set "$config_file" AdditionalOptions extensions "$extension_config"

        if [ -f "$manifest" ]; then
          while IFS= read -r old_key; do
            [ -n "$old_key" ] || continue
            crudini --del "$config_file" Patch "$old_key" || true
          done < <(jq -r '.patches[]? // empty' "$manifest")
        fi

        for i in "''${!patches_keys[@]}"; do
          crudini --set "$config_file" Patch "''${patches_keys[$i]}" "''${patches_values[$i]}"
        done

        color_backup="$theme_dir/.color.ini.lumina-backup"
        color_tmp="$theme_dir/.color.ini.lumina-tmp"
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
          result=$?
          trap - EXIT
          if [ "$result" -ne 0 ] && [ "$color_update_active" -eq 1 ]; then
            if [ "$had_previous" -eq 1 ]; then
              mv -f "$color_backup" "$theme_dir/color.ini" || true
              spicetify apply --no-restart >/dev/null 2>&1 || true
            else
              rm -f "$theme_dir/color.ini" || true
            fi
            echo "spicetify-live-apply: apply failed; restored the previous color file." >&2
          fi
          exit "$result"
        }
        trap rollback_colors EXIT

        if [ "$first_run" -eq 1 ]; then
          spicetify --no-restart backup apply
        fi
        spicetify apply --no-restart

        extensions_json="$(printf '%s\n' "''${extension_names[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
        patches_json="$(printf '%s\n' "''${patches_keys[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
        manifest_tmp="$manifest.tmp.$$"
        jq -n \
          --arg signature "$desired_signature" \
          --arg spotify "$spotify_src" \
          --argjson extensions "$extensions_json" \
          --argjson patches "$patches_json" \
          '{signature: $signature, spotify: $spotify, extensions: $extensions, patches: $patches}' \
          > "$manifest_tmp"
        mv -f "$manifest_tmp" "$manifest"
        printf '%s\n' "$spotify_src" > "$source_marker.tmp.$$"
        mv -f "$source_marker.tmp.$$" "$source_marker"
        color_update_active=0
        rm -f "$color_backup"
      '';
    };
  };
}
