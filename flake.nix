{
  inputs = {
    nixpkgs.url = "github:nix-ocaml/nix-overlays";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      self,
      treefmt-nix,
      ...
    }:
    let
      eachSystem =
        f:
        nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed (
          system:
          f system (
            nixpkgs.legacyPackages.${system}.extend (
              _self: super: {
                # You can set the OCaml version to a particular release. Also, you
                # may have to pin some packages to a particular revision if the
                # devshell fail to build. This should be resolved in the upstream.
                ocamlPackages = super.ocaml-ng.ocamlPackages_latest;
              }
            )
          )
        );

      treefmtEval = eachSystem (
        _system: pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";

          programs.nixfmt.enable = true;
          programs.ocamlformat.enable = true;
          programs.zizmor.enable = true;
          programs.mdformat.enable = true;
        }
      );
    in
    {
      packages = eachSystem (
        _system: pkgs: with pkgs; {
          default = ocamlPackages.buildDunePackage {
            pname = "crista";
            version = "0.1";
            duneVersion = "3";
            src = self.outPath;

            nativeBuildInputs = [ gitMinimal ];

            buildInputs = with ocamlPackages; [ ocaml-syntax-shims ];

            propagatedBuildInputs = with ocamlPackages; [
              picos
              picos_io
              miou
              parseff
            ];

            checkInputs = with ocamlPackages; [
              alcotest
              routes
            ];
          };
        }
      );

      devShells = eachSystem (
        system: pkgs: {
          default = pkgs.mkShell {
            inputsFrom = [ self.packages.${system}.default ];
            packages = [
              # For running wpt
              pkgs.python3
            ]
            ++ (with pkgs.ocamlPackages; [
              ocaml-lsp
              ocamlformat
              ocp-indent
              alcotest
              routes
              utop
              # Needed for generating documentation
              opam
              odoc
              odig
              # This may fail to build, so it is turned off by default.
              # (sherlodoc.override { enableServe = true; })
            ])
            # Enable file watcher.
            # ++ lib.optional pkgs.stdenv.isLinux pkgs.inotify-tools
            ;
          };
        }
      );

      formatter = eachSystem (system: _pkgs: treefmtEval.${system}.config.build.wrapper);

      checks = eachSystem (
        system: _pkgs:
        {
          treefmt = treefmtEval.${system}.config.build.check self;
        }
        // self.packages.${system}
      );
    };
}
