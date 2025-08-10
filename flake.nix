{
  description = "Hasktorch";

  nixConfig = {
    extra-substituters = [
      "https://hasktorch.cachix.org"
    ];
    extra-trusted-public-keys = [
      "hasktorch.cachix.org-1:wLjNS6HuFVpmzbmv01lxwjdCOtWRD8pQVR3Zr/wVoQc="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = {
    self,
    nixpkgs,
    flake-parts,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      imports = [
        ./nix/nixpkgs-instances.nix
      ];
      flake = {
        overlays.default = import ./nix/overlay.nix;
      };
      perSystem = {
        lib,
        pkgs,
        self',
        pkgsCuda,
        ...
      }: let
        ghc = "ghc984";
        mnist = (pkgs.callPackage ./nix/datasets.nix {}).mnist;
        mkHasktorchPackageSet = t: p:
          lib.mapAttrs' (name: value: lib.nameValuePair "${name}-${t}" value) (lib.genAttrs [
            "codegen"
            "hasktorch"
            # Cannot be built until type-level-rewrite-rules supports GHC 9.8
            # "hasktorch-gradually-typed"
            "libtorch-ffi"
            "libtorch-ffi-helper"
          ] (name: p.haskell.packages.${ghc}.${name}));

        examples =
          (pkgs.haskell.packages.${ghc}.callCabal2nix "examples"
            ./examples {}).overrideAttrs {
          LIBTORCH_SKIP_DOWNLOAD = "1";
          LIBTORCH_HOME = lib.getInclude pkgs.libtorch-bin;
          LIBTORCH_CUDA_VERSION = pkgs.cudaPackages.cudaMajorMinorVersion;
        };
      in {
        packages =
          {
            inherit examples;
          }
          // (mkHasktorchPackageSet "cuda" pkgsCuda)
          // (mkHasktorchPackageSet "cpu" pkgs);
        devShells = let
          packages = p:
            with p; [
              codegen
              hasktorch
              examples
              # Cannot be built until type-level-rewrite-rules supports GHC 9.8
              # hasktorch-gradually-typed
              libtorch-ffi
              libtorch-ffi-helper
            ];
          nativeBuildInputs = with pkgs; [
            cabal-install
            haskell-language-server
          ];
        in {
          default = self'.devShells.cpu;
          cpu = pkgs.haskell.packages.${ghc}.shellFor {
            inherit packages nativeBuildInputs;
          };
          cuda = pkgsCuda.haskell.packages.${ghc}.shellFor {
            inherit packages nativeBuildInputs;
          };
        };
        apps = {
          mnist-mixed-precision = {
            type = "app";
            program = pkgsCuda.writeShellScriptBin "mnist-mixed-precision" ''
              DEVICE=cuda:0 ${self'.packages.examples}/bin/mnist-mixed-precision ${mnist}/
            '';
            meta.description = "A simple mlp implementation of an mnist classifier using untyped tensors";
          };
          static-mnist-cnn = {
            type = "app";
            program = pkgsCuda.writeShellScriptBin "static-mnist-cnn" ''
              DEVICE=cuda:0 ${self'.packages.examples}/bin/static-mnist-cnn ${mnist}/
            '';
            meta.description = "Static Mnist CNN";
          };
          static-mnist-mlp = {
            type = "app";
            program = pkgsCuda.writeShellScriptBin "static-mnist-mlp" ''
              DEVICE=cuda:0 ${self'.packages.examples}/bin/static-mnist-mlp ${mnist}/
            '';
            meta.description = "Static Mnist MLP";
          };
        };
      };
    };
}
