{
  description = "Intel NPU model compiler for NixOS (Core Ultra laptops)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Prebuilt results from CI (.github/workflows/build.yml), so the source build
  # doesn't have to be compiled locally. Nix asks before using it.
  nixConfig = {
    extra-substituters = [ "https://nixos-intel-npu.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-intel-npu.cachix.org-1:ikhkuI/crInBQxA1PBUQAupWk13HfJCDAIYHHn7/g3A="
    ];
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        intel-npu-compiler = pkgs.callPackage ./package.nix { };
        npu-compiler-llvm = pkgs.callPackage ./npu-compiler-llvm.nix { };
        intel-npu-compiler-source = pkgs.callPackage ./package-source.nix {
          inherit (self.packages.${system}) npu-compiler-llvm;
        };
        default = self.packages.${system}.intel-npu-compiler;
      };

      nixosModules.default = import ./module.nix { inherit self; };
    };
}
