{lib, ...}: {
  options.flake = {
    lib = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.unspecified;
      default = {};
      description = "Lumina's library, consumed by Alice via the lumina flake input.";
    };
    homeModules = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.unspecified;
      default = {};
      description = "Home Manager modules exported by Lumina.";
    };
  };
}
