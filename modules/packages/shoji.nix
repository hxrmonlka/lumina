{inputs, ...}: {
  perSystem = {pkgs, ...}: let
    system = pkgs.stdenv.hostPlatform.system;
    shoji = inputs.shoji.packages.${system};
  in {
    packages = {
      inherit (shoji) shell cli greeter;
      shoji-shell = shoji.shell;
      shoji-cli = shoji.cli;
      shoji-greeter = shoji.greeter;
    };
  };
}
