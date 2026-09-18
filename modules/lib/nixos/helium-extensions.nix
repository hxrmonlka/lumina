{
  flake.nixosModules.helium-extensions = {
    config,
    lib,
    ...
  }: let
    cfg = config.lumina.helium;
  in {
    options.lumina.helium.extensions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [
        "cofdbpoegempjloogbagkncekinflcnj"
      ];
      description = ''
        Chrome extension IDs to force-install in the native Helium browser.

        Extensions are managed by Helium through Chromium's managed policy
        mechanism. Versions and artifacts are resolved by Helium itself.
      '';
    };

    config = lib.mkIf (cfg.extensions != []) {
      environment.etc."chromium/policies/managed/lumina-helium.json".text = builtins.toJSON {
        ExtensionInstallForcelist = cfg.extensions;
      };
    };
  };
}
