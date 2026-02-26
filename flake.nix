{
  description = "RocksDB C++ SIGTRAP reproduction";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            cmake
            ninja
            pkg-config
            rocksdb
            gcc
            clang
            jq
          ];

          shellHook = ''
            echo "[repro-shell] ready"
            echo "[repro-shell] run: ./repro.sh"
          '';
        };
      }
    );
}
