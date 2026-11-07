{
  description = "Bifrost AI gateway — NixOS package and systemd service module";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs supportedSystems
          (system: f system (import nixpkgs { inherit system; }));

      version = "2.5.0";

      # Static Go binary fetched directly from upstream download server.
      # To bump: change version, then for each arch run:
      #   nix store prefetch-file https://downloads.getmaxim.ai/bifrost/v<NEW>/linux/<arch>/bifrost-http
      # Hashes for v2.5.0 - update these when bumping version
      sources = {
        "x86_64-linux"  = { arch = "amd64"; hash = "sha256-1/lpfr9EP4+WHBx1HlgSMyCujHSRcOr2O2RV3U8f3i8="; };
      };

      bifrostFor = system: pkgs:
        let
          src = sources.${system} or
            (throw "bifrost: unsupported system ${system}; supported: ${toString supportedSystems}");
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "bifrost";
          inherit version;

          src = pkgs.fetchurl {
            url = "https://downloads.getmaxim.ai/bifrost/v${version}/linux/${src.arch}/bifrost-http";
            hash = src.hash;
          };

          dontUnpack = true;

          installPhase = ''
            runHook preInstall
            install -Dm755 $src $out/bin/bifrost-http
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Bifrost AI gateway — high-performance multi-provider LLM proxy";
            homepage    = "https://github.com/maximhq/bifrost";
            license     = licenses.asl20;
            platforms   = [ "x86_64-linux" "aarch64-linux" ];
            mainProgram = "bifrost-http";
          };
        };

    in
    {
      packages = forAllSystems (system: pkgs: {
        bifrost = bifrostFor system pkgs;
        default = bifrostFor system pkgs;
      });

      apps = forAllSystems (system: pkgs: {
        default = {
          type    = "app";
          program = "${bifrostFor system pkgs}/bin/bifrost-http";
          meta = {
            description = "Bifrost AI gateway — high-performance multi-provider LLM proxy";
            homepage    = "https://github.com/maximhq/bifrost";
          };
        };
      });

      nixosModules.bifrost = import ./module.nix self;
      nixosModules.default = import ./module.nix self;
    };
}
