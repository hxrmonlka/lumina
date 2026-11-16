{
  inputs,
  lib,
  ...
}: {
  perSystem = {system, ...}: let
    pname = "coderabbit-cli";
    version = "0.9.5";

    # Map the flake system to the upstream archive suffix.
    platforms = {
      "x86_64-linux" = "linux-x64";
      "aarch64-linux" = "linux-arm64";
      "aarch64-darwin" = "darwin-arm64";
    };

    platform = platforms.${system};

    # The CLI is a proprietary Bun-compiled binary distributed through
    # cli.coderabbit.ai, so allowUnfree is scoped to this package only.
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfreePredicate = pkg:
        builtins.elem (lib.getName pkg) [pname];
    };

    hashes = {
      linux-x64 = "sha256-U/XYIgGeb3MW/8wmBBmdlMKjmtUhYDCATj8S8eRxGBg=";
      linux-arm64 = "sha256-h/v92WR89rSMLP4HMKwI+20z43DWWyscU5iznKRY/GQ=";
      darwin-arm64 = "sha256-iylrxAdfsqVzm36aX1TNKlQvobrhKV3jBYuD+NL/pzg=";
    };

    src = pkgs.fetchurl {
      url = "https://cli.coderabbit.ai/releases/${version}/coderabbit-${platform}.zip";
      hash = hashes.${platform};
    };

    package = pkgs.stdenv.mkDerivation {
      inherit pname version src;

      nativeBuildInputs =
        [pkgs.unzip]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.autoPatchelfHook];

      # The binary dlopen()s libsecret-1.so.0 at runtime for keyring-backed
      # credential storage. It is not a DT_NEEDED entry, so buildInputs alone
      # would leave it off the RUNPATH; runtimeDependencies keeps it resolvable
      # for the dlopen. On darwin the Mach-O links against system libraries
      # and must stay untouched.
      buildInputs =
        lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.libsecret];

      runtimeDependencies =
        lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.libsecret];

      # The binary embeds the Bun runtime and the compiled JS payload after
      # the ELF image; stripping rewrites sections and can invalidate the
      # payload offsets, so it stays off.
      dontStrip = true;

      unpackPhase = ''
        runHook preUnpack
        unzip "$src"
        runHook postUnpack
      '';

      installPhase = ''
        runHook preInstall

        install -Dm755 coderabbit "$out/bin/coderabbit"
        ln -s coderabbit "$out/bin/cr"

        runHook postInstall
      '';

      # The CLI writes $HOME/.coderabbit/logs on startup, so --version needs
      # a writable HOME inside the build sandbox. Authentication is never
      # performed here; it remains a user operation after installation.
      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck

        export HOME="$(mktemp -d)"

        reported="$("$out/bin/coderabbit" --version)"
        aliasReported="$("$out/bin/cr" --version)"

        if [ "$reported" != "${version}" ]; then
          echo "coderabbit --version reported '$reported', expected '${version}'"
          exit 1
        fi
        if [ "$aliasReported" != "${version}" ]; then
          echo "cr --version reported '$aliasReported', expected '${version}'"
          exit 1
        fi

        runHook postInstallCheck
      '';

      meta = {
        description = "CodeRabbit CLI for AI-powered code reviews in the terminal";
        longDescription = ''
          Official CodeRabbit CLI, a proprietary Bun-compiled binary that
          reviews local Git changes with AI before you commit. Authentication
          (`coderabbit auth login` or `cr auth login`) is a user operation and
          is never performed by this package. On Linux, credentials are stored
          through the system keyring via a runtime dlopen of libsecret.
        '';
        homepage = "https://www.coderabbit.ai/cli";
        changelog = "https://docs.coderabbit.ai/changelog";
        license = lib.licenses.unfree;
        sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
        mainProgram = "coderabbit";
        platforms = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
      };
    };
  in {
    # Guarded at the export so unsupported systems fail lazily, with this
    # package's own message, before the nixpkgs import is forced.
    packages.coderabbit-cli =
      if platforms ? ${system}
      then package
      else throw "coderabbit-cli: unsupported system ${system} (supported: x86_64-linux, aarch64-linux, aarch64-darwin)";
  };
}
