{
  description = "Sherlyn Website";

  nixConfig = {
    extra-substituters = [
      "https://rslib.cachix.org"
      "https://rayandrew.cachix.org"
    ];
    extra-trusted-public-keys = [
      "rslib.cachix.org-1:8OHneG2sLeTDlsZ4AZyNh8zx2zAwoiZUKVPnl21B+58="
      "rayandrew.cachix.org-1:kJnvdWgUyErPGaQWgh/yyu91szgRYD+V/WQ4Dbc4n9M="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    rs-web.url = "github:rslib/web";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
      pre-commit-hooks,
      rs-web,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          programs.stylua.enable = true;
          programs.prettier.enable = true;
          programs.prettier.includes = [
            "*.md"
            "*.yaml"
            "*.yml"
          ];
        };

        pre-commit-check = pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            treefmt = {
              enable = true;
              package = treefmtEval.config.build.wrapper;
            };
          };
        };
        rs-web-bin = rs-web.packages.${system}.default;

        # Build the static site
        site = pkgs.stdenv.mkDerivation {
          pname = "sherlynpw-site";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [ rs-web-bin ];

          buildPhase = ''
            rs-web build --output dist
          '';

          installPhase = ''
            cp -r dist $out
          '';
        };

        # Dev server script
        devServer = pkgs.writeShellScriptBin "dev" ''
          set -e

          # Start rs-web watch in background
          echo "Starting file watcher..."
          ${rs-web-bin}/bin/rs-web serve --output dist --watch
        '';
      in
      {
        formatter = treefmtEval.config.build.wrapper;

        packages.default = site;
        packages.site = site;

        apps = {
          dev = {
            type = "app";
            program = "${devServer}/bin/dev";
          };
          default = {
            type = "app";
            program = "${devServer}/bin/dev";
          };
        };

        checks.formatting = treefmtEval.config.build.check self;
        checks.pre-commit-check = pre-commit-check;

        devShells.default = pkgs.mkShell {
          buildInputs = [
            rs-web-bin
            treefmtEval.config.build.wrapper
          ];

          shellHook = ''
            ${pre-commit-check.shellHook}
            echo "Development environment loaded"
            python --version
          '';
        };
      }
    );
}
