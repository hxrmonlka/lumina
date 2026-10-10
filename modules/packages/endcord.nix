{
  inputs,
  lib,
  ...
}: {
  perSystem = {system, ...}: let
    pname = "endcord";
    version = "1.5.4";

    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfreePredicate = pkg:
        builtins.elem (lib.getName pkg) [pname];
    };

    py = pkgs.python3Packages;

    pythonEnv = py.python.withPackages (ps:
      with ps; [
        websocket-client
        python-socks
        orjson
        soundcard
        soundfile
        numpy
        pycryptodome
        pillow
        av
        pynacl
      ]);

    buildEnv = py.python.withPackages (ps: with ps; [cython setuptools]);

    runtimePath = lib.makeBinPath (with pkgs; [
      wl-clipboard
      xclip
      libnotify
      xdg-utils
    ]);
  in {
    packages.endcord = pkgs.stdenv.mkDerivation {
      inherit pname version;

      src = pkgs.fetchFromGitHub {
        owner = "sparklost";
        repo = "endcord";
        tag = version;
        hash = "sha256-ccpTm573Nhxj2AKvqSunE2ZZAemgox9hDakUSwvaw3s=";
      };

      nativeBuildInputs = [buildEnv];

      buildPhase = ''
        runHook preBuild
        python setup.py build_ext --inplace
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        site="$out/${py.python.sitePackages}"
        mkdir -p "$site/endcord_cython" "$out/libexec/endcord" "$out/bin"

        cp -r endcord/. "$site/endcord/"
        cp endcord_cython/*.so "$site/endcord_cython/"
        cp main.py "$out/libexec/endcord/main.py"

        cat > "$out/bin/endcord" <<LAUNCHER
        #!${pythonEnv}/bin/python
        import os
        import runpy
        import sys

        site = "$site"
        os.environ["PATH"] = "${runtimePath}:" + os.environ.get("PATH", "")
        os.environ["PYTHONPATH"] = site + os.pathsep + os.environ.get("PYTHONPATH", "")
        sys.path.insert(0, site)
        runpy.run_path("$out/libexec/endcord/main.py", run_name="__main__")
        LAUNCHER
        chmod +x "$out/bin/endcord"

        install -Dm444 tools/com.sparklost.endcord.desktop \
          "$out/share/applications/com.sparklost.endcord.desktop"
        install -Dm444 tools/icons/endcord.svg \
          "$out/share/icons/hicolor/scalable/apps/com.sparklost.endcord.svg"

        runHook postInstall
      '';

      dontFixup = true;

      meta = {
        description = "Feature rich Discord TUI client";
        homepage = "https://github.com/sparklost/endcord";
        changelog = "https://github.com/sparklost/endcord/releases/tag/${version}";
        license = lib.licenses.unfree;
        sourceProvenance = with lib.sourceTypes; [fromSource];
        mainProgram = pname;
        platforms = ["x86_64-linux" "aarch64-linux"];
      };
    };
  };
}
