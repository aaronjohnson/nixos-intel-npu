{
  description = "Intel NPU model compiler for NixOS (Core Ultra laptops)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        intel-npu-compiler = pkgs.callPackage ./package.nix { };
        default = self.packages.${system}.intel-npu-compiler;
      };

      nixosModules.default = import ./module.nix { inherit self; };
    };
}
