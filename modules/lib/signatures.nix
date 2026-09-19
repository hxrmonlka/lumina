{lib, ...}: let
  mkHostSignature = allowedHost: {config, ...}: {
    assertions = [
      {
        assertion = (config.networking.hostName or "unknown") == allowedHost;
        message = "lumina/signature: expected host '${allowedHost}', got '${config.networking.hostName or "unknown"}'.";
      }
    ];
  };

  mkUserSignature = allowedHost: allowedUser: {
    config,
    osConfig ? {},
    ...
  }: {
    assertions = [
      {
        assertion =
          (osConfig.networking.hostName or "unknown") == allowedHost
          && (config.home.username or "unknown") == allowedUser;
        message = "lumina/signature: expected '${allowedUser}@${allowedHost}', got '${config.home.username or "unknown"}@${osConfig.networking.hostName or "unknown"}'.";
      }
    ];
  };
in {
  flake.lib.signatures = {
    inherit mkHostSignature mkUserSignature;
  };
}
