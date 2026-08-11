{
  inputs = {
    nixpkgs.url = "github:nix-ocaml/nix-overlays";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://akirak.cachix.org"
    ];
    extra-trusted-public-keys = [
      "akirak.cachix.org-1:WJrEMdV1dYyALkOdp/kAECVZ6nAODY5URN05ITFHC+M="
    ];
  };

  outputs =
    {
      nixpkgs,
      self,
      treefmt-nix,
      ...
    }:
    let
      mkCristaPackages =
        isOverlay: ocamlPackages:
        let
          common = {
            version = "0.1";
            duneVersion = "3";
            src = self.outPath;
          };

          crista = ocamlPackages.callPackage (
            {
              alcotest,
              buildDunePackage,
              gitMinimal,
              ocaml-syntax-shims,
              parseff,
              routes,
            }:
            buildDunePackage (
              common
              // {
                pname = "crista";
                nativeBuildInputs = [ gitMinimal ];
                buildInputs = [ ocaml-syntax-shims ];
                propagatedBuildInputs = [ parseff ];
                checkInputs = [
                  alcotest
                  routes
                ];
              }
            )
          ) { };

          ocamlPackages' =
            if isOverlay then
              ocamlPackages
            else
              ocamlPackages.overrideScope (
                _: _: {
                  inherit crista;
                }
              );
        in
        {
          inherit crista;

          crista-eio = ocamlPackages'.callPackage (
            {
              buildDunePackage,
              gitMinimal,
              crista,
              eio,
              ocaml-syntax-shims,
            }:
            buildDunePackage (
              common
              // {
                pname = "crista-eio";
                nativeBuildInputs = [ gitMinimal ];
                buildInputs = [ ocaml-syntax-shims ];
                propagatedBuildInputs = [
                  crista
                  eio
                ];
              }
            )
          ) { };

          crista-picos = ocamlPackages'.callPackage (
            {
              buildDunePackage,
              gitMinimal,
              picos,
              picos_io,
              crista,
              ocaml-syntax-shims,
            }:
            buildDunePackage (
              common
              // {
                pname = "crista-picos";
                nativeBuildInputs = [ gitMinimal ];
                buildInputs = [ ocaml-syntax-shims ];
                propagatedBuildInputs = [
                  crista
                  picos
                  picos_io
                ];
              }
            )
          ) { };

          crista-miou = ocamlPackages'.callPackage (
            {
              alcotest,
              buildDunePackage,
              gitMinimal,
              miou,
              crista,
              ocaml-syntax-shims,
            }:
            buildDunePackage (
              common
              // {
                pname = "crista-miou";
                nativeBuildInputs = [ gitMinimal ];
                buildInputs = [ ocaml-syntax-shims ];
                propagatedBuildInputs = [
                  crista
                  miou
                ];
              }
            )
          ) { };
        };

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
      overlays.ocamlPackages = final: _prev: mkCristaPackages true final;

      packages = eachSystem (
        _system: pkgs:
        let
          packages = mkCristaPackages false pkgs.ocamlPackages;
        in
        packages // { default = packages.crista; }
      );

      devShells = eachSystem (
        system: pkgs: {
          default = pkgs.mkShell {
            inputsFrom = with self.packages.${system}; [
              crista
              crista-eio
              crista-picos
              crista-miou
            ];
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
