{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.lumina.vulkan;

  # Resolve the ICD JSON path for a given driver name.
  # Mesa drivers live under mesa.drivers; nvidia is placed at a fixed path by
  # the nvidia module; amdvlk ships its own share/vulkan/icd.d.

  # Mesa encodes the CPU arch in ICD filenames (e.g. radeon_icd.x86_64.json).
  mesaArch =
    if pkgs.stdenv.hostPlatform.isx86_64
    then "x86_64"
    else if pkgs.stdenv.hostPlatform.isi686
    then "i686"
    else if pkgs.stdenv.hostPlatform.isAarch64
    then "aarch64"
    else pkgs.stdenv.hostPlatform.parsed.cpu.name;

  icdPath = {
    "radv" = "${pkgs.mesa.drivers}/share/vulkan/icd.d/radeon_icd.${mesaArch}.json";
    # amdvlk only ships x86_64 binaries officially; amd_icd64.json is intentionally
    # not arch-parameterised - AMDVLK does not support aarch64.
    "amdvlk" = "${pkgs.amdvlk}/share/vulkan/icd.d/amd_icd64.json";
    "anv" = "${pkgs.mesa.drivers}/share/vulkan/icd.d/intel_icd.${mesaArch}.json";
    "nvk" = "${pkgs.mesa.drivers}/share/vulkan/icd.d/nouveau_icd.${mesaArch}.json";
    # nvidia places its ICD at a well-known runtime path via the driver module.
    "nvidia" = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json";
  };
in {
  options.hardware.lumina.vulkan = {
    enable = lib.mkEnableOption "Lumina – Vulkan support";

    support32Bit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable 32-bit Vulkan ICD/layers (Steam, Wine/Proton, DXVK).";
    };

    tools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install vulkan-tools (vulkaninfo, vkcube, vkcube-wayland).
        Useful for verifying driver setup and filing bug reports.
      '';
    };

    amd = {
      amdvlk = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Add AMDVLK alongside Mesa RADV.
          The Vulkan loader will see both ICDs; most apps prefer AMDVLK
          when it is present, which can degrade gaming performance.
          Recommended only for workstation / pro workloads.
          Use defaultDriver = "radv" to keep RADV as the forced default
          when amdvlk is installed.
        '';
      };
    };

    # ANV (Mesa) is already present; no extra packages needed.
    # hasvk (Haswell Vulkan) is wired into Mesa automatically for that uArch.
    # Options will be added here if Intel-specific Vulkan tuning is needed.

    nvidia = {
      nvk = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Add NVK — Mesa's open-source Nouveau Vulkan driver.
          Only meaningful when NOT using the proprietary Nvidia driver.
          Requires nouveau kernel module to be active.
          For Maxwell / Pascal / Turing via Nouveau open kernel modules.
        '';
      };
    };

    layers = {
      validation = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install Khronos Vulkan validation layers (vulkan-validation-layers).
          Adds significant runtime overhead — for Vulkan development only.
          Activate per-app:
            VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation <app>
          When this is true, VK_LAYER_PATH is extended to include the
          validation layer manifests so the loader can find them.
        '';
      };

      overlay = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Expose the Mesa Vulkan overlay layer (VkLayer_MESA_overlay).
          On nixpkgs-unstable the layer is built into Mesa; this option
          sets ENABLE_VKLAYER_MESA_OVERLAY=1 so it auto-activates globally.
          For per-app use without global activation:
            VK_INSTANCE_LAYERS=VK_LAYER_MESA_overlay <app>
        '';
      };

      deviceSelect = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable the Mesa device-select implicit layer (VkLayer_MESA_device_select).
          On nixpkgs-unstable this layer is built into Mesa by default.
          Useful on hybrid GPU systems; honours the DRI_PRIME / VK_ICD_FILENAMES
          env vars to pick the correct GPU automatically.
          Setting this to false exports
            DISABLE_LAYER_AMD_SWITCHABLE_GRAPHICS_1=1
          to prevent the layer from intercepting ICD enumeration.
        '';
      };
    };

    defaultDriver = lib.mkOption {
      type = lib.types.enum [
        "auto"
        "radv"
        "amdvlk"
        "anv"
        "nvk"
        "nvidia"
      ];
      default = "auto";
      description = ''
        Force a specific Vulkan ICD globally via VK_DRIVER_FILES.
        "auto"   – no override; let the Vulkan loader enumerate all ICDs.
        "radv"   – Mesa RADV (AMD). Forces RADV even when amdvlk is installed.
        "amdvlk" – AMD's proprietary driver. Requires amd.amdvlk = true.
        "anv"    – Mesa ANV (Intel).
        "nvk"    – Mesa NVK / Nouveau. Requires nvidia.nvk = true.
        "nvidia" – Proprietary Nvidia ICD (placed by the Nvidia driver module).
        Note: VK_DRIVER_FILES overrides any per-app VK_ICD_FILENAMES. For
        per-app overrides use a wrapper script instead.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        Additional Vulkan ICD or layer packages passed to
        hardware.graphics.extraPackages (64-bit).
      '';
    };

    extraPackages32 = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        Same as extraPackages but for 32-bit (hardware.graphics.extraPackages32).
        Required for Steam / DXVK / Wine.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.defaultDriver != "amdvlk" || cfg.amd.amdvlk;
        message = ''
          `hardware.lumina.vulkan.defaultDriver = "amdvlk"` requires
          `hardware.lumina.vulkan.amd.amdvlk = true`.
        '';
      }
      {
        assertion = cfg.defaultDriver != "nvk" || cfg.nvidia.nvk;
        message = ''
          `hardware.lumina.vulkan.defaultDriver = "nvk"` requires
          `hardware.lumina.vulkan.nvidia.nvk = true`.
        '';
      }
    ];

    hardware.graphics = {
      enable = true;
      enable32Bit = cfg.support32Bit;

      extraPackages = lib.flatten [
        # amdvlk: AMD proprietary Vulkan ICD (64-bit).
        (lib.optional cfg.amd.amdvlk pkgs.amdvlk)

        # NVK: Mesa Nouveau Vulkan. Mesa is already present; this is a no-op
        # package-wise (nvk ships inside mesa.drivers), but including pkgs.mesa
        # here explicitly documents the dependency intent.
        # Left as a comment - NVK is part of the mesa package that is already
        # installed via hardware.graphics; no extra package needed.

        # Validation layers (Khronos).
        (lib.optional cfg.layers.validation pkgs.vulkan-validation-layers)

        # User-supplied extras.
        cfg.extraPackages
      ];

      extraPackages32 = lib.flatten [
        # 32-bit amdvlk for Steam / Wine / DXVK.
        (lib.optional cfg.amd.amdvlk pkgs.driversi686Linux.amdvlk)

        cfg.extraPackages32
      ];
    };

    # vulkan-tools: vulkaninfo, vkcube, vkcube-wayland.
    environment.systemPackages = lib.optional cfg.tools pkgs.vulkan-tools;

    environment.sessionVariables = lib.mkMerge [
      # VK_LOADER_DRIVERS_SELECT filters the ICDs the Vulkan loader uses globally.
      # "auto" means no variable is set - standard loader behaviour.
      (lib.mkIf (cfg.defaultDriver != "auto") {
        VK_LOADER_DRIVERS_SELECT = builtins.replaceStrings [mesaArch "64"] ["*" "*"] (builtins.baseNameOf icdPath.${cfg.defaultDriver});
      })

      # The Vulkan loader only searches well-known system paths for layer
      # manifests. On NixOS we must extend VK_LAYER_PATH so it can find
      # store-resident manifests.
      (lib.mkIf cfg.layers.validation {
        VK_LAYER_PATH = lib.makeSearchPath "share/vulkan/explicit_layer.d" [
          pkgs.vulkan-validation-layers
        ];
      })

      # The overlay layer is implicit (loaded automatically) when this env
      # var is set. Remove this if you only want per-app activation.
      (lib.mkIf cfg.layers.overlay {
        ENABLE_VKLAYER_MESA_OVERLAY = "1";
      })

      # device-select is an implicit layer in Mesa - it is active by default.
      # Setting deviceSelect = false disables it for the whole session.
      (lib.mkIf (!cfg.layers.deviceSelect) {
        DISABLE_LAYER_AMD_SWITCHABLE_GRAPHICS_1 = "1";
      })
    ];
  };
}
