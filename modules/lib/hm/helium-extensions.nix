{ 
  flake.homeModules.helium-extensions = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.lumina.helium;

    fetchExtension = id: spec: let
      crx = pkgs.fetchurl {
        url = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=131.0.0.0&acceptformat=crx2,crx3&x=id%3D${id}%26uc";
        hash = spec.hash;
      };
    in
      pkgs.runCommand "helium-extension-${id}-${spec.version}" {
        nativeBuildInputs = [pkgs.python3 pkgs.unzip];
      } ''
        set -eu

        tmp="$TMPDIR/extension.zip"

        ${pkgs.python3}/bin/python3 - "${crx}" "$tmp" <<'PY'
import struct
import sys

src, dst = sys.argv[1:]
with open(src, "rb") as f:
    data = f.read()

if data[:4] != b"Cr24":
    raise SystemExit("not a CRX file")

version = struct.unpack_from("<I", data, 4)[0]
if version == 2:
    header_size = struct.unpack_from("<I", data, 8)[0]
    payload_offset = 16 + header_size
elif version == 3:
    header_size = struct.unpack_from("<I", data, 8)[0]
    payload_offset = 12 + header_size
else:
    raise SystemExit(f"unsupported CRX version: {version}")

payload = data[payload_offset:]
if payload[:4] != b"PK\\x03\\x04":
    raise SystemExit("CRX payload is not a ZIP archive")

with open(dst, "wb") as f:
    f.write(payload)
PY

        mkdir -p "$out"
        ${pkgs.unzip}/bin/unzip -q "$tmp" -d "$out"

        ${pkgs.python3}/bin/python3 - "$out/manifest.json" "${spec.version}" <<'PY'
import json
import sys

manifest_path, expected_version = sys.argv[1:]
with open(manifest_path, encoding="utf-8") as f:
    manifest = json.load(f)

actual_version = manifest.get("version")
if actual_version != expected_version:
    raise SystemExit(
        f"extension version mismatch: expected {expected_version}, got {actual_version}"
    )
PY
      '';
  in {
    options.lumina.helium.extensions = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            version = lib.mkOption {
              type = lib.types.str;
              description = ''
                Exact Chromium extension version to deploy.
              '';
            };

            hash = lib.mkOption {
              type = lib.types.str;
              description = ''
                Nix fixed-output hash of the Chrome Web Store CRX artifact.
              '';
            };
          };
        }
      );

      default = {};

      example = lib.literalExpression ''
        {
          "cjpalhdlnbpafiamejdnhcphjbkeiagm" = {
            version = "1.67.1";
            hash = "sha256-...";
          };
        }
      '';

      description = ''
        Declaratively managed Chromium extensions for the native Helium browser.

        Extension IDs are taken from the attribute names. The extension payload is
        fetched from the Chrome Web Store and installed into Helium's default
        profile extension directory.
      '';
    };

    config = lib.mkIf (cfg.extensions != {}) {
      home.file = lib.mapAttrs' (
        id: spec:
          lib.nameValuePair ".config/net.imput.helium/Default/Extensions/${id}/${spec.version}" {
            source = fetchExtension id spec;
          }
      ) cfg.extensions;
    };
  };
}
