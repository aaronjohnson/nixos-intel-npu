# The Intel NPU model compiler, built from source.
#
# Follows Intel's own recipe in intel/linux-npu-driver (compiler/*.cmake): build
# OpenVINO with openvinotoolkit/npu_compiler as an extra module in
# "compiler for driver" mode, and install only the CiD component, which is the
# two libraries the NPU driver and OpenVINO look for.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  python3,
  onetbb,
  zlib,
  zstd,
  # Intel's LLVM/MLIR fork, built as its own package.
  npu-compiler-llvm,
}:

let
  # Revisions pinned by linux-npu-driver v1.38.0, compiler/compiler_source.cmake.
  openvinoSrc = fetchFromGitHub {
    owner = "openvinotoolkit";
    repo = "openvino";
    rev = "d8047fb380b27a9d5827cb3f22aec7781ae5ac82"; # NPU_COMPILER_OPENVINO_REVISION
    fetchSubmodules = true;
    hash = "sha256-djEof2C5T5EyKz5hy4TQdW0Q1WHZYVHYFLujox90r/I=";
  };
  # Its llvm-project submodule is intel-staging/npu-compiler-llvm, Intel's LLVM
  # fork; it's built as its own package (npu-compiler-llvm) and used prebuilt.
  npuCompilerSrc = fetchFromGitHub {
    owner = "openvinotoolkit";
    repo = "npu_compiler";
    rev = "0b38f7d42113ff329ac2bdd33583d123de4ccf2f"; # tag npu_ud_2026_38_rc1
    fetchSubmodules = true;
    # The NPU-side SHAVE kernels (sw_runtime_kernels/**/prebuild) are stored in
    # Git LFS. They run on the NPU's own vector cores and are built with Intel's
    # SHAVE toolchain, so they ship prebuilt, like firmware.
    fetchLFS = true;
    hash = "sha256-rXUysfCLKc3VKavc3lG8BZtWLgvQVPTI/QP11Xk8F/Y=";
  };
  # Submodule commits of that npu_compiler revision, for version strings.
  llvmRev = "8f3977c01be0f24be98b67ef2c911fd82657f30c"; # thirdparty/llvm-project
  elfRev = "d325f45f2cb405b5fa2ff17a30de9469f1641b73"; # thirdparty/elf
in
stdenv.mkDerivation {
  pname = "intel-npu-compiler";
  # The compiler revision pinned by intel/linux-npu-driver 1.38.0
  # (compiler/compiler_source.cmake), matching nixpkgs' intel-npu-driver.
  version = "1.38.0";

  # OpenVINO is the CMake project; the compiler plugs into it as an extra module.
  src = openvinoSrc;

  postUnpack = ''
    cp -r ${npuCompilerSrc} npu_compiler
    chmod -R u+w npu_compiler
  '';

  # The build asks git for commit hashes to put in version strings, but Nix
  # sources have no .git. Use the pinned revisions instead.
  postPatch = ''
    substituteInPlace ../npu_compiler/cmake/compiler_commit_hash.cmake \
      --replace-fail "git rev-parse HEAD" "echo ${npuCompilerSrc.rev}"
    substituteInPlace ../npu_compiler/thirdparty/elf/npu-loader/cmake/npu_loader_version.cmake \
      --replace-fail "git rev-parse HEAD" "echo ${elfRev}"
    for f in ../npu_compiler/cmake/npu_compiler_version.cmake \
             ../npu_compiler/src/vpux_driver_compiler/src/vpux_compiler_l0/CMakeLists.txt; do
      substituteInPlace "$f" --replace-fail "find_package(Git REQUIRED)" ""
    done

    # The cost model files are already complete in the source (no Git LFS needed).
    substituteInPlace ../npu_compiler/cmake/prepare_cost_model_binary.cmake \
      --replace-fail "find_package(Git QUIET REQUIRED)" "" \
      --replace-fail "COMMAND \''${GIT_EXECUTABLE} lfs pull" "COMMAND true"

    cat >> cmake/developer_package/version.cmake <<'EOF'
    # Nix: no .git in the sources, so report the pinned revisions.
    function(ov_commit_hash VAR REPO_ROOT)
      if(REPO_ROOT MATCHES "llvm-project")
        set(''${VAR} "${builtins.substring 0 11 llvmRev}" PARENT_SCOPE)
      elseif(REPO_ROOT MATCHES "npu_compiler")
        set(''${VAR} "${builtins.substring 0 11 npuCompilerSrc.rev}" PARENT_SCOPE)
      else()
        set(''${VAR} "${builtins.substring 0 11 openvinoSrc.rev}" PARENT_SCOPE)
      endif()
    endfunction()
    function(ov_branch_name VAR REPO_ROOT)
      set(''${VAR} "HEAD" PARENT_SCOPE)
    endfunction()
    EOF
  '';

  preConfigure = ''
    cmakeFlagsArray+=(
      "-DOPENVINO_EXTRA_MODULES=$NIX_BUILD_TOP/npu_compiler"
      "-DOUTPUT_ROOT=$PWD/build"
    )
  '';

  # GCC 16 reports -Wmaybe-uninitialized in the MLIR-generated parsers for the
  # compiler's bytecode attributes (_result_width/_rank/_format), and the build
  # uses -Werror. It's a false positive: those parameters are all required, the
  # generated struct(params) loop runs exactly once per required key and rejects
  # unknown or duplicate keys, each value is checked after parsing, and an assert
  # precedes the read. GCC can't see through the lambda and std::optional. This
  # keeps the warning visible but non-fatal; Intel builds with an older GCC.
  #
  # It also reports -Wunused-but-set-variable for a loop counter that is
  # incremented but never read (VPUIP legalize_repeating_func_calls.cpp): accurate
  # but harmless dead code. Intel passes the same flag for its Android builds.
  env.NIX_CFLAGS_COMPILE = toString [
    "-Wno-error=maybe-uninitialized"
    "-Wno-error=unused-but-set-variable"
  ];

  # Large build: on Hydra, build on the big machines.
  requiredSystemFeatures = [ "big-parallel" ];

  nativeBuildInputs = [
    cmake
    ninja
    python3
  ];

  buildInputs = [
    onetbb
    zlib
    zstd
  ];

  # Intel's NPU_COMPILER_CMAKE_ARGS, from linux-npu-driver
  # compiler/npu_compiler_build.cmake, plus using nixpkgs' TBB.
  cmakeFlags = [
    (lib.cmakeBool "BUILD_COMPILER_FOR_DRIVER" true)
    # Build against npu-compiler-llvm instead of the bundled llvm-project submodule.
    (lib.cmakeBool "ENABLE_PREBUILT_LLVM_MLIR_LIBS" true)
    (lib.cmakeFeature "MLIR_BINARY_PKG_DIR" "${npu-compiler-llvm}")
    (lib.cmakeBool "BUILD_SHARED_LIBS" false)
    (lib.cmakeFeature "THREADING" "TBB")
    (lib.cmakeBool "ENABLE_SYSTEM_TBB" true)
    (lib.cmakeBool "ENABLE_DEVELOPER_BUILD" false)
    (lib.cmakeBool "ENABLE_OV_IR_FRONTEND" true)
  ]
  ++ map (option: lib.cmakeBool option false) [
    "ENABLE_AUTO"
    "ENABLE_AUTO_BATCH"
    "ENABLE_CPPLINT"
    "ENABLE_DRIVER_COMPILER_ADAPTER"
    "ENABLE_FASTER_BUILD"
    "ENABLE_FUNCTIONAL_TESTS"
    "ENABLE_HETERO"
    "ENABLE_INTEL_CPU"
    "ENABLE_INTEL_GPU"
    "ENABLE_INTEL_NPU_INTERNAL"
    "ENABLE_INTEL_NPU_PROTOPIPE"
    "ENABLE_JS"
    "ENABLE_LTO"
    "ENABLE_MULTI"
    "ENABLE_NPU_EXECUTION_ENGINE"
    "ENABLE_NPU_LSP_SERVER"
    "ENABLE_NPU_PLUGIN_ENGINE"
    "ENABLE_OV_JAX_FRONTEND"
    "ENABLE_OV_ONNX_FRONTEND"
    "ENABLE_OV_PADDLE_FRONTEND"
    "ENABLE_OV_PYTORCH_FRONTEND"
    "ENABLE_OV_TF_FRONTEND"
    "ENABLE_OV_TF_LITE_FRONTEND"
    "ENABLE_PRIVATE_TESTS"
    "ENABLE_PROXY"
    "ENABLE_PYTHON"
    "ENABLE_PYTHON_PACKAGING"
    "ENABLE_SAMPLES"
    "ENABLE_TBBBIND_2_5"
    "ENABLE_TEMPLATE"
    "ENABLE_TESTS"
    "ENABLE_WHEEL"
  ];

  # Build only the two libraries, not all of OpenVINO.
  ninjaFlags = [
    "openvino_intel_npu_compiler"
    "openvino_intel_npu_compiler_loader"
  ];

  installPhase = ''
    runHook preInstall
    cmake --install . --component CiD --prefix $out
    # Intel packages the component under cid/; use the usual layout.
    mv $out/cid/lib $out/lib
    mv $out/cid/include $out/include
    rm -r $out/cid
    runHook postInstall
  '';

  meta = {
    description = "Intel NPU model compiler for the Level Zero NPU driver and OpenVINO, built from source";
    homepage = "https://github.com/openvinotoolkit/npu_compiler";
    license = lib.licenses.asl20;
    # Built from source, except the 794 SHAVE kernels that run on the NPU itself
    # (sw_runtime_kernels/**/prebuild): they need Intel's non-public MoviTools.
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryFirmware
    ];
    platforms = [ "x86_64-linux" ];
  };
}
