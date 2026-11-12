{lib, ...}: {
  perSystem = {pkgs, ...}: let
    version = "0.3.0";
    latestVersion = "0.4.0";
    stableHashes = {
      x64 = lib.fakeHash;
      arm64 = lib.fakeHash;
    };
    arch =
      if pkgs.stdenv.hostPlatform.isAarch64 then "arm64"
      else if pkgs.stdenv.hostPlatform.isx86_64 then "x64"
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
      hash = lib.fakeHash;
    };
    workspace = pkgs.stdenvNoCC.mkDerivation {
      pname = "kunai-workspace";
      src = source;
      version = latestVersion;

      nativeBuildInputs = [pkgs.bun];
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = lib.fakeHash;

      buildPhase = ''
        export HOME="$TMPDIR"
        bun install --filter @kitsunekode/kunai --frozen-lockfile --ignore-scripts
      '';

      installPhase = ''
        mkdir -p $out
        cp -a . $out/
      '';
    };
    latest = pkgs.stdenvNoCC.mkDerivation {
      pname = "kunai";
      version = latestVersion;
      src = workspace;

      nativeBuildInputs = [pkgs.bun] ++ nativeBuildInputs;
      inherit buildInputs;

      buildPhase = ''
        bun run --cwd apps/cli build:binary:host --skip-typecheck
      '';

      installPhase = ''
        install -Dm755 apps/cli/dist/bin/${target} $out/bin/kunai
      '';

      postFixup = ''
        wrapProgram $out/bin/kunai --prefix PATH : ${lib.makeBinPath runtimeInputs}
      '';

      passthru.workspace = workspace;

      meta = stable.meta // {
        description = "Latest upstream source build of Kunai, a terminal-first media shell";
      };
    };
  in {
    packages.kunai = stable;
    packages.kunai-latest = latest;
  };
}
