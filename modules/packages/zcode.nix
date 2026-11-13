{
  inputs,
  lib,
  ...
}: {
  perSystem = {system, ...}: let
    pname = "zcode";
    version = "3.18.2";

    pkgs = import inputs.nixpkgs {inherit system;};

    arch =
      if system == "aarch64-linux"
      then "arm64"
      else "x64";

    src = pkgs.fetchurl {
      url = "https://cdn-zcode.z.ai/zcode/electron/releases/${version}/linux-${arch}/ZCode-${version}-linux-${arch}.AppImage";
      hash =
        if arch == "arm64"
        then "sha256-7BlOfm+a43hsTBvP0Ui+Mn7/Sr2ebEHvBgFejOnxg3w="
        else "sha256-9rL7OUE6fv4X470IbH0Gpq3KDf2gmaF5jqizUfC3B0k=";
    };

    appimageContents = pkgs.appimageTools.extract {inherit pname version src;};

    # The prebuilt sharp native module under resources/app.asar.unpacked
    # resolves its libvips through a $ORIGIN rpath pointing at a sibling
    # @img/sharp-libvips-linux-x64 directory, but upstream's electron-builder
    # config does not unpack that sibling next to it (the identical library is
    # shipped inside app.asar and under resources/glm/...). Exposing the exact
    # libvips-cpp the AppImage bundles puts it back on the loader path
    # (the FHS env links $out/lib into /usr/lib and runs ldconfig over it), so
    # sharp loads regardless of which bundled instance is required first.
    sharpLibvips = pkgs.runCommand "${pname}-sharp-libvips" {} ''
      mkdir -p $out/lib
      cp --dereference "${appimageContents}/resources/glm/packages/node-repl-host/node_modules/@img/sharp-libvips-linux-x64/lib/libvips-cpp.so.8.17.3" "$out/lib/"
    '';
  in {
    packages.zcode = pkgs.appimageTools.wrapType2 {
      inherit pname version src;

      # Runtime deps beyond the stock appimageTools FHS environment. The tray
      # fallbacks bundled in the AppImage's usr/lib (libappindicator.so.1,
      # libindicator.so.7) additionally want the GTK2 libdbusmenu bindings,
      # which nixpkgs no longer builds; Electron then falls back to its native
      # StatusNotifierItem tray implementation, so they are not provided here.
      extraPkgs = pkgs: [sharpLibvips];

      # Expose NixOS's hardware graphics driver trees (GLX/EGL/Vulkan ICDs,
      # VAAPI/VDPAU) inside the sandbox like Steam's FHS environment does.
      # ro-bind-try makes this a no-op on systems without them.
      extraBwrapArgs = [
        "--ro-bind-try /run/opengl-driver /run/opengl-driver"
        "--ro-bind-try /run/opengl-driver-32 /run/opengl-driver-32"
      ];

      extraInstallCommands = ''
        install -Dm444 ${appimageContents}/zcode.desktop \
          $out/share/applications/zcode.desktop
        substituteInPlace $out/share/applications/zcode.desktop \
          --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=${pname} --no-sandbox %U'

        for size in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512 1024x1024; do
          install -Dm444 ${appimageContents}/usr/share/icons/hicolor/$size/apps/zcode.png \
            $out/share/icons/hicolor/$size/apps/zcode.png
        done
      '';

      meta = {
        description = "Z.ai AI coding agent desktop application (Agentic Development Environment)";
        homepage = "https://zcode.z.ai/";
        downloadPage = "https://zcode.z.ai/en";
        changelog = "https://github.com/zai-org/ZCode/releases";
        license = lib.licenses.asl20;
        sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
        mainProgram = pname;
        platforms = ["x86_64-linux" "aarch64-linux"];
      };
    };
  };
}
