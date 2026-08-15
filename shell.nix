{ system ? builtins.currentSystem, ... }:
let
  pkgs = import (import ./nix/sources.nix).nixpkgs { inherit system; };
in
pkgs.mkShell {
  buildInputs = [
    pkgs.llama-cpp
    pkgs.niv
    pkgs.nixpkgs-fmt
  ];
  shellHook = ''
  '';
}
