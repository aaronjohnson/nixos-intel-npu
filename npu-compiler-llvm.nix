# LLVM + MLIR from Intel's fork used by the NPU compiler, built on its own so the
# compiler can build against it (ENABLE_PREBUILT_LLVM_MLIR_LIBS) instead of
# bundling it.
#
# Same idea as nixpkgs' triton-llvm, but this is a fork, not upstream LLVM at a
# pinned commit: intel-staging/npu-compiler-llvm carries 26 commits on top of
# upstream (2026-02-23), mostly MLIR changes the compiler depends on and upstream
# doesn't have: quantile-quantized and FP4 types in the Quant dialect, relaxed
# operand types in the ASM parser, memory-space attributes, inliner and
# side-effect interface additions.
#
# Configuration mirrors set_llvm_flags() in npu_compiler's
# cmake/compile_options_llvm.cmake.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  python3,
  zlib,
  zstd,
  # Build and run MLIR's test suite (check-mlir), like triton-llvm's buildTests.
  # Off by default, as in Intel's build: it adds thousands of targets and a long run.
  buildTests ? false,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "npu-compiler-llvm";
  version = "23.0.0-unstable-2026-02-23";

  # The llvm-project submodule of openvinotoolkit/npu_compiler at
  # npu_ud_2026_38_rc1 (the compiler shipped with linux-npu-driver 1.38.0).
  src = fetchFromGitHub {
    owner = "intel-staging";
    repo = "npu-compiler-llvm";
    rev = "8f3977c01be0f24be98b67ef2c911fd82657f30c";
    hash = "sha256-QvQcXdfoTALPJiJeFrshTaqkU7m2e2UuUAp7Ki57sVc=";
  };

  sourceRoot = "${finalAttrs.src.name}/llvm";

  nativeBuildInputs = [
    cmake
    ninja
    python3
  ];

  buildInputs = [
    zlib
    zstd
  ];

  cmakeFlags = [
    (lib.cmakeFeature "LLVM_ENABLE_PROJECTS" "mlir")
    (lib.cmakeFeature "LLVM_TARGETS_TO_BUILD" "host")
    (lib.cmakeBool "LLVM_ENABLE_RTTI" true)
    (lib.cmakeBool "LLVM_ENABLE_EH" true)
    (lib.cmakeBool "LLVM_ENABLE_ASSERTIONS" false)
    (lib.cmakeFeature "LLVM_ABI_BREAKING_CHECKS" "FORCE_OFF")
    (lib.cmakeBool "LLVM_BUILD_UTILS" true)
    (lib.cmakeBool "LLVM_INSTALL_UTILS" true) # FileCheck, not: used by the compiler's lit tests
    # Static libraries, linked into the compiler's shared library, as in Intel's build.
    (lib.cmakeBool "BUILD_SHARED_LIBS" false)
    (lib.cmakeBool "LLVM_ENABLE_PIC" true)
  ]
  ++ [
    (lib.cmakeBool "LLVM_INCLUDE_TESTS" buildTests)
    (lib.cmakeBool "MLIR_INCLUDE_TESTS" buildTests)
  ]
  ++ map (option: lib.cmakeBool option false) [
    "LLVM_ENABLE_WARNINGS"
    "LLVM_ENABLE_BINDINGS"
    "LLVM_ENABLE_BACKTRACES"
    "LLVM_ENABLE_CRASH_OVERRIDES"
    "LLVM_ENABLE_TERMINFO"
    "LLVM_INCLUDE_BENCHMARKS"
    "LLVM_INCLUDE_EXAMPLES"
    "LLVM_BUILD_EXAMPLES"
    "LLVM_BUILD_TOOLS"
  ];

  doCheck = buildTests;
  checkTarget = "check-mlir";

  requiredSystemFeatures = [ "big-parallel" ];

  meta = {
    description = "Intel's LLVM/MLIR fork used by the Intel NPU compiler";
    homepage = "https://github.com/intel-staging/npu-compiler-llvm";
    license = with lib.licenses; [
      asl20
      llvm-exception
    ];
    platforms = [ "x86_64-linux" ];
  };
})
