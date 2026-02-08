{
  description = "Library of low-level helper functions for nix expressions.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      lib = nixpkgs.lib;
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = lib.genAttrs supportedSystems;
      nix-utils = import ./lib { inherit lib; };
    in
    {
      lib = nix-utils;
      overlays = {
        default = final: prev: {
          inherit nix-utils;
        };
      };
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          treefmt = pkgs.runCommand "treefmt" { } ''
            ${self.formatter.${system}}/bin/treefmt --ci --working-dir ${self}
            touch $out
          '';
        }
      );
      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "treefmt";
          text = ''treefmt "$@"'';
          runtimeInputs = [
            pkgs.deadnix
            pkgs.nixfmt
            pkgs.treefmt
          ];
        }
      );
      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          packages = [
            self.formatter.${system}
          ];
        };
      });
    };
}
