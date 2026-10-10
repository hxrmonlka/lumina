{...}: {
  flake.lib.hardware = {
    intel = import ./hardware/_intel.nix;
    amd = import ./hardware/_amd.nix;
    nvidia = import ./hardware/_nvidia.nix;
    vulkan = import ./hardware/_vulkan.nix;
    mkFramework = import ./hardware/_framework.nix;
  };
}
