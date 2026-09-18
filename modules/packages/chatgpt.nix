{
  inputs,
  lib,
  ...
}: {
  perSystem = {system, ...}:
    let
      pname = "chatgpt";
      version = "26.915.31029";
      arch = if system == "aarch64-linux" then "arm64" else "amd64";

      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg:
          builtins.elem (lib.getName pkg) [pname];
      };

      src = pkgs.fetchurl {
        url =
          "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_"
          + version
          + "_"
          + arch
          + ".deb";
        hash =
          if arch == "arm64"
          then "sha256-XAHONezOqeldFt4FLHTxbe7TgUCJMegrEG19vu7Y3ko="
          else "sha256-kyglt2pB6AZDIEqaqcz9HLJHH/v8vh0xSZQ2D8qv+zU=";
      };

      package = pkgs.stdenv.mkDerivation {
        pname = pname;
        inherit version src;

        nativeBuildInputs = with pkgs; [
          dpkg
          autoPatchelfHook
          auto-patchelf
          inotify-tools
          python3
        ];

        buildInputs = with pkgs; [
          alsa-lib
          at-spi2-atk
          at-spi2-core
          atk
          cairo
          cups
          dbus
          expat
          fontconfig
          freetype
          gdk-pixbuf
          glib
          gtk3
          libGL
          libdrm
          libgbm
          libnotify
          libpulseaudio
          libsecret
          libusb1
          libxkbcommon
          nspr
          nss
          pango
          pipewire
          stdenv.cc.cc.lib
          systemd
          wayland
          libx11
          libxcomposite
          libxdamage
          libxext
          libxfixes
          libxrandr
          libxcb
        ];

        dontStrip = true;

        autoPatchelfIgnoreMissingDeps = [
          "libc++_shared.so"
          "libc.musl-x86_64.so.1"
          "liblog.so"
          "libQt5Core.so.5"
          "libQt5Gui.so.5"
          "libQt5Widgets.so.5"
          "libQt6Core.so.6"
          "libQt6Gui.so.6"
          "libQt6Widgets.so.6"
        ];

        unpackPhase = ''
          runHook preUnpack
          dpkg-deb -x "$src" .
          runHook postUnpack
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p "$out/bin" "$out/lib" "$out/share/applications" "$out/share/pixmaps" "$out/libexec"
          cp -r usr/lib/chatgpt "$out/lib/"
          cp -r usr/share/applications/. "$out/share/applications/"
          cp -r usr/share/pixmaps/. "$out/share/pixmaps/"

          install -Dm755 "$(command -v auto-patchelf)" "$out/libexec/auto-patchelf"
          install -Dm755 "$(command -v inotifywait)" "$out/libexec/inotifywait"

          python3 - "$out/lib/chatgpt/resources/app.asar" <<'PY'
          import hashlib
          import json
          import re
          import struct
          import sys
          from pathlib import Path

          asar = Path(sys.argv[1])
          data = asar.read_bytes()

          matches = list(re.finditer(rb"isLinux\(\) && process\.report", data))
          if len(matches) != 1:
              raise SystemExit(f"expected exactly one process.report match, got {len(matches)}")

          match = matches[0]
          original = match.group(0)
          replacement = b"false /* nix:skip report */"
          if len(replacement) > len(original):
              raise SystemExit("process.report replacement is larger than the original")
          data = data[:match.start()] + replacement.ljust(len(original), b" ") + data[match.end():]

          header_pickle_size = struct.unpack_from("<I", data, 4)[0]
          header_size = struct.unpack_from("<I", data, 12)[0]
          header_start = 16
          content_start = 8 + header_pickle_size
          header = json.loads(data[header_start:header_start + header_size])

          def refresh_files(files: dict) -> None:
              for entry in files.values():
                  nested = entry.get("files")
                  if isinstance(nested, dict):
                      refresh_files(nested)
                      continue

                  integrity = entry.get("integrity")
                  offset = entry.get("offset")
                  size = entry.get("size")
                  if not isinstance(integrity, dict) or offset is None or not isinstance(size, int):
                      continue

                  block_size = integrity.get("blockSize")
                  if not isinstance(block_size, int):
                      raise SystemExit("invalid ASAR integrity block size")

                  start = content_start + int(str(offset))
                  content = data[start:start + size]
                  integrity["hash"] = hashlib.sha256(content).hexdigest()
                  integrity["blocks"] = [
                      hashlib.sha256(content[i:i + block_size]).hexdigest()
                      for i in range(0, len(content), block_size)
                  ] or [hashlib.sha256(b"").hexdigest()]

          files = header.get("files")
          if not isinstance(files, dict):
              raise SystemExit("invalid ASAR header")
          refresh_files(files)

          encoded = json.dumps(header, separators=(",", ":")).encode()
          if len(encoded) != header_size:
              raise SystemExit(
                  f"ASAR header size changed: expected {header_size}, got {len(encoded)}"
              )

          asar.write_bytes(data[:header_start] + encoded + data[header_start + header_size:])
          PY

          cat > "$out/bin/chatgpt" <<EOF
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          export PATH="$out/libexec:\$PATH"
          runtime_root="\$HOME/.cache/codex-runtimes"

          patch_runtimes() {
            local dir stamp want interp
            interp="\$(< "$NIX_CC/nix-support/dynamic-linker")"
            local libs=(
              "${pkgs.stdenv.cc.cc.lib}/lib"
              "${pkgs.zlib}/lib"
              "${pkgs.libxcrypt-legacy}/lib"
              "${pkgs.curl}/lib"
              "${pkgs.nss}/lib"
              "${pkgs.nspr}/lib"
            )
            for dir in "\$runtime_root"/*/; do
              [[ -f "\$dir/runtime.json" ]] || continue
              want="\$(cat "\$dir/runtime.json"; printf '%s\n' "\$interp")"
              stamp="\$dir/.nix-patched"
              [[ -f "\$stamp" && "\$(cat "\$stamp")" == "\$want" ]] && continue
              auto-patchelf \
                --paths "\$dir" \
                --libs "\''${libs[@]}" \
                --ignore-missing 'libcurl-gnutls.so.4' \
                >/dev/null 2>&1 || true
              printf '%s' "\$want" > "\$stamp"
            done
          }

          mkdir -p "\$runtime_root"
          patch_runtimes

          app_pid=\$\$
          (
            while kill -0 "\$app_pid" 2>/dev/null; do
              "$out/libexec/inotifywait" -qq -t 60 -e moved_to "\$runtime_root" >/dev/null 2>&1 || continue
              patch_runtimes
            done
          ) &

          exec "$out/lib/chatgpt/codex-launcher" "\$@"
          EOF
          chmod +x "$out/bin/chatgpt"

          runHook postInstall
        '';

        preFixup = ''
          addAutoPatchelfSearchPath "${pkgs.qt5.qtbase}/lib"
          addAutoPatchelfSearchPath "${pkgs.qt6.qtbase}/lib"
        '';

        postFixup = ''
          patchelf --add-rpath "${pkgs.qt5.qtbase}/lib" "$out/lib/chatgpt/libqt5_shim.so" || true
          patchelf --add-rpath "${pkgs.qt6.qtbase}/lib" "$out/lib/chatgpt/libqt6_shim.so" || true
        '';

        meta = {
          description = "Official ChatGPT desktop application for Linux";
          homepage = "https://learn.chatgpt.com/docs/linux/linux-app";
          changelog = "https://learn.chatgpt.com/docs/changelog";
          license = lib.licenses.unfree;
          sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
          mainProgram = "chatgpt";
          platforms = ["x86_64-linux" "aarch64-linux"];
        };
      };
    in {
      packages.chatgpt =
        if builtins.elem system ["x86_64-linux" "aarch64-linux"]
        then package
        else throw "chatgpt: unsupported system " + system;
  };
}
