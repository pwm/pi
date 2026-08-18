{ system ? builtins.currentSystem, ... }:
let
  pkgs = import (import ./nix/sources.nix).nixpkgs { inherit system; };
in
pkgs.mkShell {
  buildInputs = [
    pkgs.llama-cpp
    pkgs.niv
    pkgs.nixpkgs-fmt
    pkgs.nodejs # npm for `pi install` (plugins load without it; only install/update need it)
  ];
  shellHook = ''
  '';
}
