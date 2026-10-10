{
  config,
  lib,
  pkgs,
  ...
}: let
  cfgGpu = config.hardware.lumina.intel.gpu;
  cfgCpu = config.hardware.lumina.intel.cpu;

  gen = cfgGpu.generation;

  isPreBroadwell = gen == "pre-broadwell";
  isLegacy = gen == "legacy"; # 5th–10th gen incl. Coffee Lake 8th gen
  isXe = gen == "xe"; # 12th-gen+ / Iris Xe / Arc
in {
  options.hardware.lumina.intel = {
    gpu = {
      enable = lib.mkEnableOption "Lumina – Intel GPU driver";

      generation = lib.mkOption {
        type = lib.types.enum [
          "pre-broadwell"
          "legacy"
          "xe"
        ];
        default = "xe";
        description = ''
          Intel GPU generation tier. See module header for the full breakdown.

          pre-broadwell – 1st–4th gen (Sandy/Ivy/Haswell). i965 only.
          legacy        – 5th–10th gen (Broadwell → Comet Lake / Coffee Lake 8th gen).
                          Ships both iHD and i965; iHD is primary.
          xe            – 12th-gen+ / Iris Xe / Arc. iHD + vpl-gpu-rt (QSV).
        '';
      };

      earlyKms = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Load i915 in the initrd for early KMS (avoids flicker on LUKS).";
      };

      enableGuC = lib.mkOption {
        type = lib.types.bool;
        # GuC is only meaningful / recommended on Xe/Arc; keep it off by default
        # for legacy to avoid surprises on Coffee Lake where it is unnecessary.
        default = isXe;
        description = ''
          Pass i915.enable_guc=3 to the kernel.
          Needed for GuC/HuC firmware on 12th-gen+ / Arc for QSV offload.
          Not needed for Coffee Lake / legacy; leave false there.
        '';
      };

      # Coffee Lake and older Skylake/Kaby Lake can optionally enable Quick Sync
      # for H.265/VP9 via Intel's hybrid driver.
      hybridCodec = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Build intel-vaapi-driver with hybrid codec support.
          Enables H.265 / VP9 Quick Sync on Skylake / Kaby Lake / Coffee Lake
          (6th–8th gen). Only applies when generation = "legacy".
        '';
      };

      openclNeo = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable Intel NEO OpenCL + Level Zero runtime.
          Xe / Arc only — use intel-compute-runtime-legacy1 for Coffee Lake OpenCL.
        '';
      };

      openclLegacy = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable OpenCL for Coffee Lake / legacy iGPUs via
          intel-compute-runtime-legacy1. Only applies when generation = "legacy".
        '';
      };
    };

    cpu = {
      enable = lib.mkEnableOption "Lumina – Intel CPU tuning";

      pstate = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable intel_pstate driver (active mode).
          Effective on 6th-gen+ (Skylake). 8th-gen Coffee Lake benefits from this.
        '';
      };
    };
  };

  config = lib.mkMerge [
    # GPU
    (lib.mkIf cfgGpu.enable {
      assertions = [
        {
          assertion = !cfgGpu.openclNeo || isXe;
          message = "hardware.lumina.intel.gpu.openclNeo requires generation = \"xe\"";
        }
        {
          assertion = !cfgGpu.openclLegacy || isLegacy;
          message = "hardware.lumina.intel.gpu.openclLegacy requires generation = \"legacy\"";
        }
        {
          assertion = !cfgGpu.hybridCodec || isLegacy;
          message = "hardware.lumina.intel.gpu.hybridCodec requires generation = \"legacy\"";
        }
      ];

      services.xserver.videoDrivers = ["modesetting"];

      hardware.graphics = {
        enable = true;
        enable32Bit = true;

        extraPackages = with pkgs;
          if isXe
          then
            lib.flatten [
              intel-media-driver # VA-API (iHD) — required for Xe / Arc
              vpl-gpu-rt # oneVPL / QSV runtime (12th-gen+)
              (lib.optional cfgGpu.openclNeo intel-compute-runtime)
            ]
          else if isLegacy
          then
            # 5th–10th gen (including 8th-gen Coffee Lake UHD 620/630):
            # Ship both iHD and i965. iHD handles most tasks; i965 is kept
            # because it performs better in browsers (Gecko / Chromium).
            let
              vaDriver =
                if cfgGpu.hybridCodec
                then pkgs.intel-vaapi-driver.override {enableHybridCodec = true;}
                else pkgs.intel-vaapi-driver;
            in
              lib.flatten [
                intel-media-driver # iHD — primary VA-API (Broadwell+)
                vaDriver # i965 — browser fallback / hybrid codec
                libvdpau-va-gl # VDPAU → VA-API shim
                (lib.optional cfgGpu.openclLegacy (intel-compute-runtime-legacy1.overrideAttrs (old: {
                  cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_CXX_FLAGS=-Wno-error=sfinae-incomplete"];
                })))
              ]
          else
            # pre-broadwell: i965 only, no iHD support
            [
              pkgs.intel-vaapi-driver
              pkgs.libvdpau-va-gl
            ];

        # 32-bit VA-API for Steam / Wine.
        extraPackages32 = with pkgs.pkgsi686Linux;
          if isXe
          then [
            intel-media-driver
            vpl-gpu-rt
          ]
          else if isLegacy
          then let
            vaDriver32 =
              if cfgGpu.hybridCodec
              then intel-vaapi-driver.override {enableHybridCodec = true;}
              else intel-vaapi-driver;
          in [
            intel-media-driver
            vaDriver32
          ]
          else [intel-vaapi-driver];
      };

      environment.sessionVariables = {
        # iHD is the preferred backend for Broadwell+ (incl. Coffee Lake).
        # Override to "i965" at the session level if browsers act up.
        LIBVA_DRIVER_NAME =
          if isPreBroadwell
          then "i965"
          else "iHD";
      };

      boot.initrd.kernelModules = lib.optional cfgGpu.earlyKms "i915";

      boot.kernelParams = lib.optional cfgGpu.enableGuC "i915.enable_guc=3";

      hardware.enableRedistributableFirmware = lib.mkDefault true;
    })

    # CPU
    (lib.mkIf cfgCpu.enable {
      boot.kernelParams = lib.optional cfgCpu.pstate "intel_pstate=active";
      hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
    })
  ];
}
