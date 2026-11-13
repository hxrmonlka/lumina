{lib, ...}: {
  perSystem = {pkgs, ...}: let
    pname = "animesama-cli";
    version = "1.0.23";

    py = pkgs.python3Packages;
  in {
    packages.animesama-cli = py.buildPythonApplication rec {
      inherit pname version;

      src = pkgs.fetchFromGitHub {
        owner = "Miro-sh";
        repo = "animesama-cli";
        tag = "v${version}";
        hash = "sha256-PYbh9tsekJxVkVp+vsrbBx38IpAhIu7EZWCMFpp9gpc=";
      };

      postPatch = ''
        substituteInPlace pyproject.toml \
          --replace-fail 'version = "1.0.7"' 'version = "${version}"'
      '';

      pyproject = true;

      build-system = [py.setuptools];

      dependencies = with py; [
        requests
        beautifulsoup4
        textual
        pillow
      ];

      makeWrapperArgs = [
        "--prefix"
        "PATH"
        ":"
        (lib.makeBinPath [pkgs.mpv])
      ];

      pythonImportsCheck = ["anime_sama"];

      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        $out/bin/animesama-cli -h | grep -q "Usage:"
        runHook postInstallCheck
      '';

      meta = {
        description = "Browse and watch anime from anime-sama.fr directly in your terminal";
        homepage = "https://github.com/Miro-sh/animesama-cli";
        changelog = "https://github.com/Miro-sh/animesama-cli/releases/tag/v${version}";
        license = lib.licenses.gpl3Only;
        mainProgram = pname;
        platforms = lib.platforms.unix;
      };
    };
  };
}
