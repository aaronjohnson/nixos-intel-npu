# NixOS module: hardware.intel-npu-compiler.enable = true;
#
# Puts the NPU model compiler next to the Level Zero NPU driver in
# /run/opengl-driver/lib, where the driver looks for it. With it, Level Zero
# programs (and Intel's npu-umd-test) can compile and run models on the NPU.
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.intel-npu-compiler;
in
{
  options.hardware.intel-npu-compiler = {
    enable = lib.mkEnableOption "the Intel NPU model compiler (also enables hardware.cpu.intel.npu)";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.intel-npu-compiler;
      defaultText = lib.literalExpression "nixos-intel-npu.packages.\${system}.intel-npu-compiler";
      description = "The compiler package to install.";
    };

    openvinoWorkaround = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Put the Level Zero loader on LD_LIBRARY_PATH for all sessions, so nixpkgs'
        OpenVINO can find the NPU. Its NPU plugin dlopens libze_loader.so.1 but its
        RUNPATH doesn't include it (nixpkgs bug). Also compile with
        {"NPU_COMPILER_TYPE": "DRIVER"} in OpenVINO, since it only looks for the
        compiler in its own lib directory.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.cpu.intel.npu.enable = true;
    hardware.graphics.extraPackages = [ cfg.package ];

    environment.sessionVariables = lib.mkIf cfg.openvinoWorkaround {
      LD_LIBRARY_PATH = [ "${lib.getLib pkgs.level-zero}/lib" ];
    };
  };
}
