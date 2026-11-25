{
  inputs,
  lib,
  ...
}: {
  perSystem = {system, ...}: let
    pname = "darling";
    version = "unstable-2026-11-25";
    rev = "2a70cb1a5accde44e34656a92a40c490cdccd3c0";

    pkgs = import inputs.nixpkgs {inherit system;};
    stdenv = pkgs.clangStdenv;

    wrappedLibs = with pkgs; [
      freetype
      libjpeg
      libpng
      libtiff
      giflib
      libX11
      libXext
      libXrandr
      libXcursor
      libxkbfile
      cairo
      libglvnd
      fontconfig
      dbus
      libGLU
      fuse3
      ffmpeg
      pulseaudio
    ];

    ccWrapperBypass = pkgs.runCommandWith {
      inherit stdenv;
      name = "darling-cc-wrapper-bypass";
      runLocal = false;
      derivationArgs = {
        template = pkgs.writeShellScript "darling-cc-wrapper-template" ''
          for ((i = 1; i <= $#; i++)); do
            j=$((i + 1))
            if [[ "''${!i}" == "-target" && "''${!j}" == *"darwin"* ]]; then
              exec @unwrapped@ "$@" $NIX_CFLAGS_COMPILE
            fi
          done
          exec @wrapped@ "$@"
        '';
      };
    } ''
      mkdir -p "$out/bin"

      unwrapped="${stdenv.cc.cc}/bin/$CC" wrapped="${stdenv.cc}/bin/$CC" \
        substituteAll "$template" "$out/bin/$CC"
      unwrapped="${stdenv.cc.cc}/bin/$CXX" wrapped="${stdenv.cc}/bin/$CXX" \
        substituteAll "$template" "$out/bin/$CXX"

      chmod +x "$out/bin/$CC" "$out/bin/$CXX"
    '';
  in {
    packages.darling = stdenv.mkDerivation {
      inherit pname version;

      src = pkgs.fetchFromGitHub {
        owner = "darlinghq";
        repo = "darling";
        inherit rev;
        fetchSubmodules = true;
        fetchLFS = true;
        preFetch = ''
          export GIT_CLONE_PROTECTION_ACTIVE=false
        '';
        hash = lib.fakeHash;
      };

      nativeBuildInputs = with pkgs; [
        bison
        ccWrapperBypass
        cmake
        flex
        libcap
        ninja
        pkg-config
        python3
        patchelf
      ];

      buildInputs = wrappedLibs ++ [
        pkgs.libbsd
        pkgs.openssl
        pkgs.fuse3.dev
        stdenv.cc.libc.linuxHeaders
      ];

      dontFixCmake = true;
      dontPatchShebangs = true;
      dontCheckForBrokenSymlinks = true;
      cmakeBuildType = " ";

      postPatch = ''
        patchShebangs \
          src/external/bootstrap_cmds/migcom.tproj/mig.sh \
          src/external/darlingserver/scripts \
          src/external/openssl_certificates/scripts

        substituteInPlace src/startup/CMakeLists.txt \
          --replace-fail SETUID ""

        if grep -q SETGID src/external/basic_cmds/CMakeLists.txt; then
          substituteInPlace src/external/basic_cmds/CMakeLists.txt \
            --replace-fail SETGID ""
        fi

        substituteInPlace src/external/darling-dmg/CMakeLists.txt \
          --replace-fail "pkg_check_modules(FUSE REQUIRED fuse)" "pkg_check_modules(FUSE REQUIRED fuse3)" \
          --replace-fail "wrap_elf(fuse libfuse.so)" "wrap_elf(fuse libfuse3.so)"

        substituteInPlace src/external/darling-dmg/src/main-fuse.h \
          --replace-fail "#define FUSE_USE_VERSION 26" "#define FUSE_USE_VERSION 31"

        substituteInPlace src/external/darling-dmg/src/main-fuse.cpp \
          --replace-fail "int hfs_getattr(const char* path, struct stat* stat)" "int hfs_getattr(const char* path, struct stat* stat, struct fuse_file_info*)" \
          --replace-fail "int hfs_readdir(const char* path, void* buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info* info)" "int hfs_readdir(const char* path, void* buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info* info, enum fuse_readdir_flags)" \
          --replace-fail "filler(buf, it->first.c_str(), &it->second, 0)" "filler(buf, it->first.c_str(), &it->second, 0, FUSE_FILL_DIR_DEFAULTS)"

        substituteInPlace src/external/darling-dmg/src/main-fuse.h \
          --replace-fail "int hfs_getattr(const char* path, struct stat* stat);" "int hfs_getattr(const char* path, struct stat* stat, struct fuse_file_info*);" \
          --replace-fail "int hfs_readdir(const char* path, void* buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info* info);" "int hfs_readdir(const char* path, void* buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info* info, enum fuse_readdir_flags);"
      '';

      cmakeFlags = [
        "-DCOMPONENTS=stock"
        "-DDARLING_ARCHS=x86_64"
        "-DCOMPILE_PY2_BYTECODE=OFF"
        "-DENABLE_METAL=OFF"
        "-DDARLINGSERVER_XDG_USER_DIR_CMD=${pkgs.xdg-user-dirs}/bin/xdg-user-dir"
      ];

      env.NIX_CFLAGS_COMPILE = "-Wno-macro-redefined -Wno-unused-command-line-argument";
      env.LD_LIBRARY_PATH = lib.makeLibraryPath wrappedLibs;

      postFixup = ''
        patchelf --add-rpath "${lib.makeLibraryPath wrappedLibs}:${pkgs.addDriverRunpath.driverLink}/lib" \
          "$out/libexec/darling/usr/libexec/darling/mldr"
      '';

      meta = {
        description = "Open-source Darwin/macOS compatibility layer for Linux";
        homepage = "https://www.darlinghq.org";
        changelog = "https://github.com/darlinghq/darling/commits/${rev}";
        license = lib.licenses.gpl3Plus;
        sourceProvenance = with lib.sourceTypes; [fromSource];
        mainProgram = "darling";
        platforms = ["x86_64-linux"];
      };
    };
  };
}
