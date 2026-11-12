{
  inputs,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    bun2nix = inputs.bun2nix.packages.${system}.default;
    version = "0.3.0";
    latestVersion = "0.4.0";
    stableHashes = {
      x64 = "sha256-sbwOssjgQTjFcTAxmGt53MKPloDk3AJbWf7MdIrcE78=";
      arm64 = lib.fakeHash;
    };
    arch =
      if pkgs.stdenv.hostPlatform.isAarch64
      then "arm64"
      else if pkgs.stdenv.hostPlatform.isx86_64
      then "x64"
      else throw "Kunai is only packaged for x86_64-linux and aarch64-linux";
    target = "kunai-linux-${arch}";
    runtimeInputs = with pkgs; [
      mpv
      yt-dlp
      ffmpeg
      curl-impersonate
    ];
    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      makeWrapper
    ];
    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
    ];
    stable = pkgs.stdenvNoCC.mkDerivation {
      pname = "kunai";
      inherit version;

      src = pkgs.fetchurl {
        url = "https://github.com/KitsuneKode/kunai/releases/download/v${version}/${target}.tar.gz";
        hash = stableHashes.${arch};
      };

      sourceRoot = ".";
      inherit nativeBuildInputs buildInputs;

      dontStrip = true;

      installPhase = ''
        install -Dm755 ${target} $out/bin/kunai
      '';

      postFixup = ''
        wrapProgram $out/bin/kunai --prefix PATH : ${lib.makeBinPath runtimeInputs}
      '';

      meta = {
        description = "Terminal-first media shell for anime, movies, TV and YouTube";
        homepage = "https://kunai.kitsunekode.in";
        license = lib.licenses.mit;
        mainProgram = "kunai";
        platforms = ["x86_64-linux" "aarch64-linux"];
      };
    };
    source = pkgs.fetchFromGitHub {
      owner = "KitsuneKode";
      repo = "kunai";
      rev = "7bf8b8af396f98e539235e32db1579f9347e5169";
      hash = "sha256-qt6DJiVbCFj4EnUTYNhvC/QIo8+/vzSFGPp/UZiIVmw=";
    };

    # Dependency set for `kunai-latest`, generated from the pinned Kunai
    # workspace's bun.lock by `.github/scripts/update-kunai.py` and committed
    # as `kunai-bun.nix` at the repository root.
    #
    # bun2nix emits workspace packages as `copyPathToStore ./apps/cli`-style
    # paths relative to the workspace root. Those directories only exist in
    # the pinned Kunai source, not in this repository, so this wrapper
    # redirects every `copyPathToStore` call into `source` instead of
    # rewriting the generated text. `bunNix` stays a plain Nix function, so
    # `fetchBunDeps` (which does `pkgs.callPackage bunNix { ... }`) consumes
    # it without import-from-derivation.
    kunaiBunRoot = toString ../..;
    bunNix = {
      copyPathToStore,
      fetchFromGitHub,
      fetchgit,
      fetchurl,
      ...
    }:
      (import ../../kunai-bun.nix) {
        inherit fetchFromGitHub fetchgit fetchurl;
        copyPathToStore = p:
          copyPathToStore (source + lib.removePrefix kunaiBunRoot (toString p));
      };

    # Upstream patches its `braces` dependency (see upstream package.json
    # `patchedDependencies`). bun2nix pre-patches packages in the Nix cache
    # and the bun2nix hook strips `patchedDependencies` from package.json and
    # bun.lock before the offline install, so the patch must be replayed here
    # via `overrides` or the build would silently use unpatched braces.
    kunaiBunOverrides = bun2nix.patchedDependenciesToOverrides {
      patchedDependencies = {
        "braces@3.0.3" = source + "/patches/braces@3.0.3.patch";
      };
    };

    latest = pkgs.stdenvNoCC.mkDerivation {
      pname = "kunai";
      version = latestVersion;
      src = source;

      nativeBuildInputs = [pkgs.bun bun2nix.hook] ++ nativeBuildInputs;
      inherit buildInputs;

      bunDeps = bun2nix.fetchBunDeps {
        inherit bunNix;
        overrides = kunaiBunOverrides;
      };
      bunInstallFlagsArray = [
        "--filter"
        "@kitsunekode/kunai"
        "--frozen-lockfile"
      ];
      dontRunLifecycleScripts = true;
      dontUseBunBuild = true;
      dontUseBunCheck = true;
      dontStrip = true;

      buildPhase = ''
        bun run --cwd apps/cli build:binary:host --skip-typecheck
      '';

      installPhase = ''
        install -Dm755 apps/cli/dist/bin/${target} $out/bin/kunai
      '';

      postFixup = ''
        wrapProgram $out/bin/kunai --prefix PATH : ${lib.makeBinPath runtimeInputs}
      '';

      meta =
        stable.meta
        // {
          description = "Latest upstream source build of Kunai, a terminal-first media shell";
        };
    };
  in {
    packages.bun2nix-cli = bun2nix;
    packages.kunai = stable;
    packages.kunai-latest = latest;
  };
}
