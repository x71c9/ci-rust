{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  packages = [
    pkgs.gh
    pkgs.git
  ];
  shellHook = ''
    export PATH="$PWD/scripts:$PATH"
    bash scripts/fetch-rebase.sh
  '';
}
