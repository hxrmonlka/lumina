{lib, ...}: {
  perSystem = {pkgs, ...}: let
    manifest = (lib.importTOML ../../cli/Cargo.toml).package;
  in {
    packages.lumina-cli = pkgs.rustPlatform.buildRustPackage {
      pname = manifest.name;
      inherit (manifest) version;

      src = lib.fileset.toSource {
        root = ../../cli;
        fileset = ../../cli;
      };

      cargoLock.lockFile = ../../cli/Cargo.lock;

      meta = {
        inherit (manifest) description;
        mainProgram = "lumina";
        platforms = lib.platforms.unix;
      };
    };
  };
}
