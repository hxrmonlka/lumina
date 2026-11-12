{
  flake.nixosModules.waydroid = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.lumina.waydroid;

    basePackage =
      if config.networking.nftables.enable
      then pkgs.waydroid-nftables
      else pkgs.waydroid;

    patchedPackage = basePackage.overrideAttrs (old: {
      postPatch =
        (old.postPatch or "")
        + ''
          substituteInPlace tools/helpers/http.py \
            --replace-fail "urllib.request.urlopen(url)" "urllib.request.urlopen(url, timeout=${toString cfg.networkTimeout})" \
            --replace-fail "urllib.request.urlopen(req)" "urllib.request.urlopen(req, timeout=${toString cfg.networkTimeout})"
        ''
        + lib.optionalString cfg.forceIPv4 ''
          cat >> tools/helpers/http.py <<'PYEOF'

          import socket as _lumina_socket

          _lumina_getaddrinfo = _lumina_socket.getaddrinfo


          def _lumina_ipv4_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
              return _lumina_getaddrinfo(host, port, _lumina_socket.AF_INET, type, proto, flags)


          _lumina_socket.getaddrinfo = _lumina_ipv4_getaddrinfo
          PYEOF
        '';
    });

    initWrapper = pkgs.writeShellApplication {
      name = "lumina-waydroid-init";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        if [ "$(id -u)" -ne 0 ]; then
          echo "lumina-waydroid-init: run as root (sudo lumina-waydroid-init)" >&2
          exit 1
        fi
        attempt=1
        until timeout ${toString cfg.initTimeout} ${lib.getExe config.virtualisation.waydroid.package} init "$@"; do
          if [ "$attempt" -ge ${toString cfg.initRetries} ]; then
            echo "lumina-waydroid-init: failed after $attempt attempts" >&2
            exit 1
          fi
          attempt=$((attempt + 1))
          echo "lumina-waydroid-init: retry $attempt of ${toString cfg.initRetries}" >&2
          sleep 5
        done
      '';
    };

    houdiniRev = "2f8f088671182e17e67321e098e8411a3972a628";

    houdiniRc = pkgs.writeText "houdini.rc" ''
      on early-init
          mount binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc

      on property:ro.enable.native.bridge.exec=1
          exec -- /system/bin/sh -c "echo ':arm_exe:M::\\x7f\\x45\\x4c\\x46\\x01\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x02\\x00\\x28::/system/bin/houdini:P' > /proc/sys/fs/binfmt_misc/register"
          exec -- /system/bin/sh -c "echo ':arm_dyn:M::\\x7f\\x45\\x4c\\x46\\x01\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x03\\x00\\x28::/system/bin/houdini:P' >> /proc/sys/fs/binfmt_misc/register"
          exec -- /system/bin/sh -c "echo ':arm64_exe:M::\\x7f\\x45\\x4c\\x46\\x02\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x02\\x00\\xb7::/system/bin/houdini64:P' >> /proc/sys/fs/binfmt_misc/register"
          exec -- /system/bin/sh -c "echo ':arm64_dyn:M::\\x7f\\x45\\x4c\\x46\\x02\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x03\\x00\\xb7::/system/bin/houdini64:P' >> /proc/sys/fs/binfmt_misc/register"
    '';

    houdini = pkgs.runCommand "libhoudini-android13" {
      nativeBuildInputs = [pkgs.unzip];
      src = pkgs.fetchurl {
        url = "https://github.com/supremegamers/vendor_intel_proprietary_houdini/archive/${houdiniRev}.zip";
        hash = "sha256-LoLNyI3cTUGPf7hhruu3xJyDqRuX9X2hBRC14RRqTtU=";
      };
    } ''
      unzip -q $src
      mkdir -p $out
      cp -r --no-preserve=ownership vendor_intel_proprietary_houdini-${houdiniRev}/prebuilts/. $out/
      chmod -R u+w $out
      mkdir -p $out/etc/init
      cp ${houdiniRc} $out/etc/init/houdini.rc
    '';

    houdiniProps = {
      "ro.product.cpu.abilist" = "x86_64,x86,arm64-v8a,armeabi-v7a,armeabi";
      "ro.product.cpu.abilist32" = "x86,armeabi-v7a,armeabi";
      "ro.product.cpu.abilist64" = "x86_64,arm64-v8a";
      "ro.dalvik.vm.native.bridge" = "libhoudini.so";
      "ro.enable.native.bridge.exec" = "1";
      "ro.dalvik.vm.isa.arm" = "x86";
      "ro.dalvik.vm.isa.arm64" = "x86_64";
    };

    propsJson = pkgs.writeText "lumina-waydroid-props.json" (builtins.toJSON houdiniProps);

    syncScript = pkgs.writeShellApplication {
      name = "lumina-waydroid-houdini-sync";
      runtimeInputs = [pkgs.coreutils pkgs.python3];
      text = ''
        state=/var/lib/waydroid
        if [ ! -f "$state/waydroid.cfg" ]; then
          exit 0
        fi
        mkdir -p "$state/overlay/system"
        cp -rT --preserve=mode ${cfg.houdini.package} "$state/overlay/system"
        chmod -R u+w "$state/overlay/system"
        python3 - "$state" ${propsJson} <<'PYEOF'
        import configparser
        import json
        import os
        import sys

        state, props_file = sys.argv[1], sys.argv[2]
        props = json.load(open(props_file))

        cfg_path = os.path.join(state, "waydroid.cfg")
        cfg = configparser.ConfigParser()
        cfg.read(cfg_path)
        if not cfg.has_section("properties"):
            cfg.add_section("properties")
        for key, value in props.items():
            cfg.set("properties", key, value)
        with open(cfg_path, "w") as handle:
            cfg.write(handle)

        base_path = os.path.join(state, "waydroid_base.prop")
        if os.path.isfile(base_path):
            lines = [
                line
                for line in open(base_path).read().splitlines()
                if line.split("=", 1)[0] not in props
            ]
            lines += [key + "=" + value for key, value in props.items()]
            with open(base_path, "w") as handle:
                handle.write("\n".join(lines) + "\n")
        PYEOF
      '';
    };
  in {
    options.lumina.waydroid = {
      enable = lib.mkEnableOption "Waydroid with Lumina fixes";

      networkTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 30;
        description = "Socket timeout in seconds for Waydroid OTA and image requests. Upstream sets none, so a stalled connection hangs `waydroid init` without output.";
      };

      forceIPv4 = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Resolve only IPv4 addresses in Waydroid network requests.";
      };

      initTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1800;
        description = "Seconds before `lumina-waydroid-init` stops one attempt.";
      };

      initRetries = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
        description = "Maximum attempts of `lumina-waydroid-init`.";
      };

      houdini = {
        enable = lib.mkEnableOption "libhoudini ARM translation (Intel CPUs, Android 13 image)";
        package = lib.mkOption {
          type = lib.types.package;
          default = houdini;
          defaultText = lib.literalExpression "pinned libhoudini derivation";
          description = "Directory tree copied into the Waydroid system overlay at container start.";
        };
      };
    };

    config = lib.mkIf cfg.enable {
      virtualisation.waydroid = {
        enable = true;
        package = lib.mkDefault patchedPackage;
      };

      environment.systemPackages = [initWrapper];

      systemd.services.waydroid-container.serviceConfig.ExecStartPre =
        lib.mkIf cfg.houdini.enable [(lib.getExe syncScript)];
    };
  };
}
