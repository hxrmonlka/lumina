{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.lumina.nvidia;

  # Map our simplified driver names to nixpkgs kernel package attributes.
  driverPackage =
    {
      stable = config.boot.kernelPackages.nvidiaPackages.stable;
      beta = config.boot.kernelPackages.nvidiaPackages.beta;
      production = config.boot.kernelPackages.nvidiaPackages.production;
      legacy-470 = config.boot.kernelPackages.nvidiaPackages.legacy_470;
      legacy-390 = config.boot.kernelPackages.nvidiaPackages.legacy_390;
    }.${
      cfg.driver
    };

  primeEnabled = cfg.prime.enable;

  # Exactly one of intelBusId / amdBusId should be set for hybrid setups.
  hasPrimePeer = cfg.prime.intelBusId != "" || cfg.prime.amdBusId != "";
in {
  options.hardware.lumina.nvidia = {
    enable = lib.mkEnableOption "Lumina – Nvidia GPU driver";

    open = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Use the open-source kernel modules (Turing / RTX 20xx and newer).
        Set to false for Maxwell/Pascal/Volta or when open modules cause issues.
      '';
    };

    driver = lib.mkOption {
      type = lib.types.enum [
        "stable"
        "beta"
        "production"
        "legacy-470"
        "legacy-390"
      ];
      default = "stable";
      description = "Driver branch to use.";
    };

    modesetting = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable kernel modesetting. Required for Wayland.";
    };

    forceFullCompositionPipeline = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Fixes screen tearing at the cost of some performance.";
    };

    powerManagement = {
      enable = lib.mkEnableOption "Nvidia runtime power management (RTD3)";
      finegrained = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Fine-grained power management: allow the dGPU to power down when idle.
          Turing+ only. Requires prime.mode = "offload".
        '';
      };
    };

    prime = {
      enable = lib.mkEnableOption "Nvidia PRIME hybrid graphics";

      mode = lib.mkOption {
        type = lib.types.enum [
          "offload"
          "sync"
          "reverse-sync"
        ];
        default = "offload";
        description = ''
          offload      – AMD/Intel iGPU default; Nvidia on-demand via nvidia-offload.
          sync         – Nvidia always-on; iGPU output forwarded through Nvidia.
          reverse-sync – Nvidia always-on; iGPU drives the display.
        '';
      };

      nvidiaBusId = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "PCI:1:0:0";
        description = ''
          PCI bus ID of the Nvidia GPU. Find with:
            lspci | grep -E "VGA|3D"
          then convert hex to decimal: c1:00.0 → PCI:193:0:0
        '';
      };

      intelBusId = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "PCI:0:2:0";
        description = "PCI bus ID of the Intel iGPU (leave empty if AMD iGPU).";
      };

      amdBusId = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "PCI:6:0:0";
        description = "PCI bus ID of the AMD iGPU (leave empty if Intel iGPU).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !primeEnabled || hasPrimePeer;
        message = ''
          `hardware.lumina.nvidia.prime.enable` requires either
          `hardware.lumina.nvidia.prime.intelBusId` or
          `hardware.lumina.nvidia.prime.amdBusId` to be set.
        '';
      }
    ];

    # Unfree required for the proprietary driver.
    # Required for proprietary Nvidia drivers.
    # Users can override if they have a more granular unfree predicate.
    nixpkgs.config.allowUnfree = lib.mkDefault true;

    services.xserver.videoDrivers = ["nvidia"];

    hardware.nvidia = {
      open = cfg.open;
      package = driverPackage;
      modesetting.enable = cfg.modesetting;
      nvidiaSettings = true;
      forceFullCompositionPipeline = cfg.forceFullCompositionPipeline;

      powerManagement = {
        enable = cfg.powerManagement.enable;
        finegrained = cfg.powerManagement.finegrained;
      };

      prime = lib.mkIf primeEnabled {
        offload = lib.mkIf (cfg.prime.mode == "offload") {
          enable = true;
          enableOffloadCmd = true; # provides `nvidia-offload` wrapper
        };
        sync.enable = cfg.prime.mode == "sync";
        reverseSync.enable = cfg.prime.mode == "reverse-sync";

        nvidiaBusId = lib.mkIf (cfg.prime.nvidiaBusId != "") cfg.prime.nvidiaBusId;
        intelBusId = lib.mkIf (cfg.prime.intelBusId != "") cfg.prime.intelBusId;
        amdgpuBusId = lib.mkIf (cfg.prime.amdBusId != "") cfg.prime.amdBusId;
      };
    };

    # Graphics / OpenGL (hardware.opengl was renamed in NixOS 24.11)
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      # nvidia-vaapi-driver is added by the nvidia module automatically on unstable;
      # leaving extraPackages empty here - extend per-host if NVENC/NVDEC is needed.
    };

    # Required kernel modules for the open driver path.
    boot.kernelModules = lib.optionals cfg.open ["nvidia_uvm"];

    # Wayland environment hints for apps using EGL/GBM.
    environment.sessionVariables = {
      LIBVA_DRIVER_NAME = "nvidia";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      GBM_BACKEND = "nvidia-drm";
    };
  };
}
