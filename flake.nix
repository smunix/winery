{
  description =
    "Winery: A compact, well-typed seralisation format for Haskell values";

  inputs.devshell.url = "github:numtide/devshell";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nix-filter.url = "github:numtide/nix-filter";

  outputs = { self, flake-utils, nix-filter, devshell, nixpkgs }:
    with nixpkgs.lib;
    with flake-utils.lib;
    eachSystem [ "x86_64-linux" ] (system:
      let
        substr = replaceStrings [ "." ] [ "" ];
        version = ghc:
          "${ghc}.${substring 0 8 self.lastModifiedDate}.${
            self.shortRev or "dirty"
          }";
        config = { };
        overlays.devshell = devshell.overlay;
        overlays.default = f: p:
          let
            defaultGhc =
              (replaceStrings [ "." ] [ "" ] p.haskellPackages.ghc.version);

            ghcVersion = "ghc${defaultGhc}";

            mkHaskellPackages = hspkgs:
              (hspkgs.override (old: {
                overrides = composeExtensions (old.overrides or (_: _: { }))
                  (_: hp:
                    {
                      # mkDerivation = args:
                      #   hp.mkDerivation (args // {
                      #     enableLibraryProfiling = false;
                      #     doCheck = false;
                      #     doHaddock = false;
                      #   });
                    });
              })).extend (hf: hp:
                with f.haskell.lib;
                composeExtensions (hf: hp: {
                  winery = disableLibraryProfiling ((hf.callCabal2nix "winery"
                    (with nix-filter.lib;
                      filter {
                        root = self;
                        # exclude = [ (matchExt "cabal") ];
                      }) { }).overrideAttrs (old: {
                        version =
                          "${substr hp.ghc.version}-${substr old.version}";
                      }));
                }) (hf: hp: {
                  # generic-trie = disableLibraryProfiling (dontHaddock (dontCheck
                  #   (doJailbreak (hf.callHackage "generic-trie" "0.3.1" { }))));
                  fast-builder = disableLibraryProfiling (dontHaddock (dontCheck
                    (doJailbreak
                      (hf.callHackage "fast-builder" "0.1.3.0" { }))));
                }) hf hp);

            # all haskellPackages
            allHaskellPackages = let
              cases = listToAttrs (map (n: {
                name = "${n}";
                value = mkHaskellPackages
                  f.haskell.packages."${if n == "default" then
                    "${ghcVersion}"
                  else
                    "ghc${n}"}";
              }) [ "default" "902" "922" ]);
            in cases;

            # all packages
            allPackages = listToAttrs (map (n: {
              name = if n == "default" then n else "winery-${n}";
              value = allHaskellPackages."${n}".winery;
            }) [ "default" "902" "922" ]);

            # make dev shell
            mkDevShell = g:
              p.devshell.mkShell {
                name = "winery-${g}";
                imports = [ (pkgs.devshell.importTOML ./devshell.toml) ];
                packages = with f;
                  with f.allHaskellPackages."${g}"; [
                    f.haskell-language-server
                    f.ghcid
                    (ghcWithPackages (P: with p; [ winery ghc cabal-install ]))
                  ];
              };

            # all packages
            allDevShells = listToAttrs (map (n: {
              name = "${n}";
              value = mkDevShell n;
            }) [ "default" "902" "922" ]);
          in {
            haskellPackages = allHaskellPackages.default;
            inherit allHaskellPackages allDevShells allPackages;
          };

        pkgs = import nixpkgs {
          inherit system config;
          overlays = [ overlays.devshell overlays.default ];
        };

      in with pkgs.lib; rec {
        inherit overlays;
        packages = flattenTree (pkgs.recurseIntoAttrs pkgs.allPackages);
        devShells = flattenTree (pkgs.recurseIntoAttrs pkgs.allDevShells);
      });
}
