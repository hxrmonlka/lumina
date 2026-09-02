{lib, ...}: let
  allowedHosts = ["serpentine"];
  allowedUsers = ["alice"];

  mkHostAssertion = hostName: {
    assertion = builtins.elem hostName allowedHosts;
    message = "lumina/signature: host '${hostName}' is not authorized. Allowed: ${builtins.concatStringsSep ", " allowedHosts}.";
  };

  mkUserAssertion = hostName: userName: {
    assertion =
      builtins.elem hostName allowedHosts
      && builtins.elem userName allowedUsers;
    message =
      "lumina/signature: host '${hostName}' / user '${userName}' is not authorized."
      + " Allowed hosts: ${builtins.concatStringsSep ", " allowedHosts}."
      + " Allowed users: ${builtins.concatStringsSep ", " allowedUsers}.";
  };
in {
  # Library
  flake.lib.signatures = {
    inherit allowedHosts allowedUsers mkHostAssertion mkUserAssertion;
  };

  # NixOS module, import into a host configuration to gate it
  flake.nixosModules.signature = {config, ...}: {
    assertions = [(mkHostAssertion (config.networking.hostName or "unknown"))];
  };

  # Home Manager module, import into a user's HM imports to gate it
  flake.homeModules.signature = {
    config,
    osConfig ? {},
    ...
  }: let
    hostName = osConfig.networking.hostName or "unknown";
    userName = config.home.username or "unknown";
  in {
    assertions = [(mkUserAssertion hostName userName)];
  };
}
