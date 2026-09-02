{lib, ...}: let
  allowedHosts = ["serpentine"];
  allowedUsers = ["alice"];

  mkMessage = hostName: userName:
    "lumina: signature verification failed for host '${hostName}'"
    + lib.optionalString (userName != null) " and user '${userName}'"
    + ". This module is proprietary to Alice and refuses to evaluate on unauthorized hosts or users.";

  mkAssertion = hostName: userName: {
    assertion = builtins.elem hostName allowedHosts && (userName == null || builtins.elem userName allowedUsers);
    message = mkMessage hostName userName;
  };

  protectNixos = mod: args @ {config, ...}: let
    hostName = config.networking.hostName or "unknown";
    result = mod args;
  in
    result
    // {
      assertions = (result.assertions or []) ++ [(mkAssertion hostName null)];
    };

  protectHome = mod: args @ {
    config,
    osConfig ? {},
    ...
  }: let
    hostName = osConfig.networking.hostName or "unknown";
    userName = config.home.username or "unknown";
    result = mod args;
  in
    result
    // {
      assertions = (result.assertions or []) ++ [(mkAssertion hostName userName)];
    };
in {
  flake.lib.signatures = {
    hosts = allowedHosts;
    users = allowedUsers;
    assertHost = hostName: mkAssertion hostName null;
    assertHostUser = hostName: userName: mkAssertion hostName userName;
    inherit protectNixos protectHome;
  };
}
