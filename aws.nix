{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    localstack
    (python3.withPackages (ps: with ps; [ numpy matplotlib pandas biopython ]))
    terraform-local
    terraform
    bcftools
    bwa
    samtools
  ];
}
