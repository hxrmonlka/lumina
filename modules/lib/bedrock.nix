{lib, ...}: let
  initSystems = ["systemd" "openrc" "runit" "sysvinit"];

  mkPinsSection = pins:
    "[cross-bin]\n"
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList
      (cmd: stratum: "pin/bin/${cmd} = ${stratum}:/usr/bin/${cmd}")
      pins
    )
    + "\n";

  mkInitSection = {
    stratum,
    path,
    timeout ? null,
  }:
    "[init]\n"
    + "default = ${stratum}:${path}\n"
    + lib.optionalString (timeout != null) "timeout = ${toString timeout}\n";

  mkModule = {
    optionPath,
    confFile,
    hostStratum,
    strata,
    pins,
    init ? {},
  }: {config, ...}: let
    cfg = lib.getAttrFromPath optionPath config;
    userUnits = with config.systemd.user; [services timers sockets paths];
  in {
    options = lib.setAttrByPath optionPath {
      hostStratum = lib.mkOption {
        type = lib.types.str;
        default = hostStratum;
      };

      strata = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = strata;
      };

      pins = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
      };

      init = {
        stratum = lib.mkOption {
          type = lib.types.str;
          default = init.stratum or hostStratum;
        };

        system = lib.mkOption {
          type = lib.types.enum initSystems;
          default = init.system or "systemd";
        };

        path = lib.mkOption {
          type = lib.types.str;
          default = init.path or "/sbin/init";
        };

        timeout = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = init.timeout or null;
        };
      };
    };

    config = lib.mkMerge [
      (lib.setAttrByPath optionPath {
        pins = lib.mapAttrs (_: lib.mkDefault) pins;
      })
      {
        assertions = [
          {
            assertion = lib.all (s: lib.elem s cfg.strata) (lib.attrValues cfg.pins);
            message = "lumina/bedrock: pins reference a stratum missing from strata.";
          }
          {
            assertion = lib.elem cfg.init.stratum cfg.strata;
            message = "lumina/bedrock: init.stratum '${cfg.init.stratum}' is missing from strata.";
          }
          {
            assertion = cfg.init.system == "systemd" || lib.all (u: builtins.attrNames u == []) userUnits;
            message = "lumina/bedrock: init.system is '${cfg.init.system}' but systemd.user units are declared. Home Manager cannot start them without systemd.";
          }
        ];

        home.file.${confFile}.text =
          mkInitSection {
            inherit (cfg.init) stratum path timeout;
          }
          + "\n"
          + mkPinsSection cfg.pins;
      }
    ];
  };
in {
  flake.lib.bedrock = {
    inherit initSystems mkPinsSection mkInitSection mkModule;
  };
}
