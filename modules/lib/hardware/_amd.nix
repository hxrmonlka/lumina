{
  config,
  lib,
  pkgs,
  ...
}: let
  cfgGpu = config.hardware.lumina.amd.gpu;
  cfgCpu = config.hardware.lumina.amd.cpu;
in {
  options.hardware.lumina.amd = {
    gpu = {
      enable = lib.mkEnableOption "Lumina – AMD GPU (amdgpu) driver";

      earlyKms = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Load amdgpu in the initrd for early KMS (avoids flickering during LUKS unlock).
        '';
      };

      rocm = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable ROCm/OpenCL support via Mesa's clover or the ROCM stack.";
      };

      lact = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable LACT daemon for AMD GPU fan/power/OC control.
          Access the GUI via `lact-gui` or through a system tray app.
        '';
      };

      amdvlk = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Add AMD's official Vulkan driver (amdvlk) alongside Mesa's radv.
          WARNING: amdvlk can be outdated and may break some games. Prefer
          radv (Mesa) for gaming; only enable for specific workloads.
        '';
      };

      # Legacy GCN1/GCN2 support - disabled by default in mainline kernels.
      legacySupport = {
        southernIslands = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Force amdgpu for Southern Islands (GCN 1 / SI) cards.";
        };
        seaIslands = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Force amdgpu for Sea Islands (GCN 2 / CIK) cards.";
        };
      };
    };

    cpu = {
      enable = lib.mkEnableOption "Lumina – AMD CPU power/perf tuning";

      pstate = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable amd-pstate (EPP) driver for Zen 3+ / Ryzen 6000+.";
      };

      zenpower = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Load zenpower kernel module for CPU sensor readings.";
      };
    };
  };

  config = lib.mkMerge [
    # GPU
    (lib.mkIf cfgGpu.enable {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs;
          lib.flatten [
            # Mesa ships the radeonsi VA-API driver; no extra package needed.
            # Add amdvlk only when explicitly requested.
            (lib.optional cfgGpu.amdvlk amdvlk)
            (lib.optionals cfgGpu.rocm [
              rocmPackages.clr
              rocmPackages.clr.icd
            ])
          ];
      };

      # Early KMS: load amdgpu in initrd so the display is up before the OS.
      boot.initrd.kernelModules = lib.optional cfgGpu.earlyKms "amdgpu";

      # Legacy GCN1/GCN2 - force amdgpu over the radeon driver.
      boot.kernelParams = lib.flatten [
        (lib.optionals cfgGpu.legacySupport.southernIslands [
          "radeon.si_support=0"
          "amdgpu.si_support=1"
        ])
        (lib.optionals cfgGpu.legacySupport.seaIslands [
          "radeon.cik_support=0"
          "amdgpu.cik_support=1"
        ])
      ];

      # ROCm: Mesa expects HIP libraries at /opt/rocm/hip.
      systemd.tmpfiles.rules = lib.optional cfgGpu.rocm "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}";

      # LACT service for fan/OC control.
      services.lact.enable = cfgGpu.lact;
    })

    # CPU
    (lib.mkIf cfgCpu.enable {
      boot.kernelParams = lib.optional cfgCpu.pstate "amd_pstate=active";

      boot.kernelModules = lib.optional cfgCpu.zenpower "zenpower";

      # Suppress the default acpi_cpufreq conflict when pstate is active.
      boot.blacklistedKernelModules = lib.optional cfgCpu.pstate "acpi_cpufreq";

      # amd-ucode for early microcode updates.
      hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
    })
  ];
}
