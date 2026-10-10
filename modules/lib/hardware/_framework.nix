# Examples:
#   imports = [ (inputs.lumina.lib.hardware.mkFramework inputs.nixos-hardware) ];
#
#   hardware.lumina.framework = {
#     enable = true;
#     model  = "13-amd-7040";
#
#     # Only needed if the model has a discrete Nvidia GPU (FW16 dGPU module):
#     nvidia.nvidiaBusId = "PCI:1:0:0";
#     nvidia.amdBusId    = "PCI:193:0:0";
#   };
#
# Models:
#   13-11th-intel         Framework 13 – 11th-gen Intel
#   13-12th-intel         Framework 13 – 12th-gen Intel
#   13-13th-intel         Framework 13 – 13th-gen Intel
#   13-intel-cu1          Framework 13 – Intel Core Ultra Series 1
#   13-amd-7040           Framework 13 – AMD Ryzen 7040 (Phoenix)
#   13-amd-ai300          Framework 13 – AMD Ryzen AI 300 (Strix/Hawk Point)
#   16-amd-7040           Framework 16 – AMD Ryzen 7040
#   16-amd-ai300          Framework 16 – AMD Ryzen AI 300
#   16-amd-ai300-nvidia   Framework 16 – AMD Ryzen AI 300 + Nvidia dGPU module

nixosHardware:
  {
    config,
    lib,
    pkgs,
    ...
  }:
  let
    cfg = config.hardware.lumina.framework;

    # Map model strings → nixos-hardware module attribute names.
    nixosHwModuleAttr = {
      "13-11th-intel" = "framework-11th-gen-intel";
      "13-12th-intel" = "framework-12th-gen-intel";
      "13-13th-intel" = "framework-13th-gen-intel";
      "13-intel-cu1" = "framework-intel-core-ultra-series1";
      "13-amd-7040" = "framework-13-7040-amd";
      "13-amd-ai300" = "framework-amd-ai-300-series";
      "16-amd-7040" = "framework-16-7040-amd";
      "16-amd-ai300" = "framework-16-amd-ai-300-series";
      "16-amd-ai300-nvidia" = "framework-16-amd-ai-300-series-nvidia";
    };

    hwModule =
      nixosHardware.nixosModules.${nixosHwModuleAttr.${cfg.model}}
        or (throw "hardware.lumina.framework.model: unknown model '${cfg.model}'");

    hasNvdGpu = cfg.model == "16-amd-ai300-nvidia";
  in
  {
    # Pull in the appropriate nixos-hardware Framework profile only when enabled.
    imports = lib.optional cfg.enable hwModule;

    # ── Option declarations ────────────────────────────────────────────────
    options.hardware.lumina.framework = {
      enable = lib.mkEnableOption "Lumina – Framework laptop hardware profile";

      model = lib.mkOption {
        type = lib.types.enum [
          "13-11th-intel"
          "13-12th-intel"
          "13-13th-intel"
          "13-intel-cu1"
          "13-amd-7040"
          "13-amd-ai300"
          "16-amd-7040"
          "16-amd-ai300"
          "16-amd-ai300-nvidia"
        ];
        description = ''
          Framework laptop model. Determines which nixos-hardware profile to import.
          See module header for the full model list.
        '';
      };

      fwupd = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable fwupd for BIOS/firmware updates via LVFS.";
      };

      powerProfiles = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable power-profiles-daemon.
          Recommended over TLP for AMD Framework laptops.
        '';
      };

      fprintd = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable fingerprint reader support via fprintd.
          After enabling, enroll with: fprintd-enroll
        '';
      };

      # Required only for "16-amd-ai300-nvidia" — the dGPU module.
      nvidia = {
        nvidiaBusId = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "PCI:1:0:0";
          description = ''
            PRIME PCI bus ID of the Nvidia dGPU on the FW16 dGPU module.
            REQUIRED for model = "16-amd-ai300-nvidia".
            FW16's modular design means bus IDs vary per system config.
            Find with: lspci | grep -E "VGA|3D"
            then convert hex to decimal: c1:00.0 → PCI:193:0:0
          '';
        };
        amdBusId = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "PCI:193:0:0";
          description = "PRIME PCI bus ID of the AMD iGPU on the FW16.";
        };
      };
    };

    # ── Implementation ─────────────────────────────────────────────────────
    config = lib.mkIf cfg.enable {
      # fwupd – BIOS and firmware updates over LVFS.
      services.fwupd.enable = cfg.fwupd;

      # power-profiles-daemon (preferred for AMD Framework).
      services.power-profiles-daemon.enable = cfg.powerProfiles;
      # Disable tlp if power-profiles-daemon is active (they conflict).
      services.tlp.enable = lib.mkIf cfg.powerProfiles (lib.mkForce false);

      # Fingerprint reader.
      services.fprintd.enable = cfg.fprintd;

      assertions = [
        {
          assertion = !hasNvdGpu || (cfg.nvidia.nvidiaBusId != "" && cfg.nvidia.amdBusId != "");
          message = ''
            `hardware.lumina.framework.model = "16-amd-ai300-nvidia"` requires both
            `hardware.lumina.framework.nvidia.nvidiaBusId` and
            `hardware.lumina.framework.nvidia.amdBusId` to be set.
          '';
        }
      ];

      # PRIME bus IDs for the FW16 Nvidia dGPU module.
      # nixos-hardware's nvidia submodule enables offload mode; we just supply the IDs.
      hardware.nvidia.prime = lib.mkIf hasNvdGpu {
        nvidiaBusId = lib.mkIf (cfg.nvidia.nvidiaBusId != "") cfg.nvidia.nvidiaBusId;
        amdgpuBusId = lib.mkIf (cfg.nvidia.amdBusId != "") cfg.nvidia.amdBusId;
      };

      # Redistributable firmware (wifi, Bluetooth, iGPU blobs).
      hardware.enableRedistributableFirmware = lib.mkDefault true;

      # Kernel: Framework docs suggest 6.12+ for the AI 300 series.
      # The nixos-hardware module usually sets a sane default;
      # override here only if on a problematic model.
      boot.kernelPackages = lib.mkIf (
        cfg.model == "13-amd-ai300" || cfg.model == "16-amd-ai300" || cfg.model == "16-amd-ai300-nvidia"
      ) (lib.mkDefault pkgs.linuxPackages_latest);
    };
  }
