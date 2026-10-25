{lib, ...}: let
  appendPatch = patch: pkg:
    pkg.overrideAttrs (old: {
      patches = (old.patches or []) ++ [patch];
    });
in {
  flake.lib.patches = {
    mango = {
      scenefx = appendPatch ../../patches/mango/scenefx-output-saturation.patch;
      setgray = appendPatch ../../patches/mango/mango-setgray.patch;
    };
    breakpad = pkg:
      pkg.overrideAttrs (old: {
        patches =
          (old.patches or [])
          ++ lib.optional
          (!lib.any (p: lib.hasSuffix "fix-vtable-link.patch" (toString p)) (old.patches or []))
          ../../patches/breakpad/breakpad-fix-vtable-link.patch;
      });
  };
}
