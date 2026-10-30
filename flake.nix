{
  description = "TO: kompresja obrazu — kodowanie różnicowe/predykcyjne";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = pkgs.python3.withPackages (
            ps: with ps; [
              numpy
              pillow
              matplotlib
            ]
          );
        in
        {
          default = pkgs.mkShell {
            packages = [
              python
              pkgs.git
            ];
            shellHook = ''
              export TO_ROOT="$(pwd)"
              export PYTHONPATH="$TO_ROOT/src''${PYTHONPATH:+:$PYTHONPATH}"
              echo "TO predcomp: python=$(python --version)"
              echo "  python -m predcomp.cli --help"
              echo "  python -m predcomp.cli samples"
              echo "  python -m predcomp.cli benchmark"
            '';
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = pkgs.python3.withPackages (
            ps: with ps; [
              numpy
              pillow
              matplotlib
            ]
          );
        in
        {
          import-check = pkgs.runCommand "predcomp-import-check" { } ''
            export PYTHONPATH=${self}/src
            ${python}/bin/python -c "import predcomp; import predcomp.predictors; import predcomp.huffman"
            mkdir -p $out
            echo ok > $out/result
          '';
        }
      );
    };
}
