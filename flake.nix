{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";

    bun2nix = {
      url = "github:nix-community/bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    grub-theme = {
      url = "github:hxrmonlka/resources/grub";
      flake = false;
    };

    fastfetch = {
      url = "github:hxrmonlka/resources/fastfetch";
      flake = false;
    };

    shoji = {
      url = "github:hxrmonlka/shoji/eup";
      flake = false;
    };

    m3shapes = {
      url = "github:soramanew/m3shapes/8a6fe8961749887d677700b6508e0c9249968b7e";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./modules);
}
