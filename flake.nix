{
  description = "A Nix Flake for generating devenv-based project templates";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
      };
    in {
      defaultPackage.x86_64-linux = pkgs.hello;
    };}
