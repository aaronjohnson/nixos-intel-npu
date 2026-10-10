# The Intel NPU model compiler ("driver compiler"), repackaged from Intel's
# prebuilt Ubuntu release of intel/linux-npu-driver.
#
# nixpkgs' intel-npu-driver builds the Level Zero driver, firmware and tests from
# source but not this compiler, so on NixOS nothing can compile a model for the
# NPU: the driver and OpenVINO both look for libopenvino_intel_npu_compiler_loader.so.
#
# The compiler itself is open source (openvinotoolkit/npu_compiler, Apache-2.0);
# building it from source means building a large LLVM-based toolchain, so this
# takes Intel's binaries and patches them to use nixpkgs' libraries.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  tbb,
  zstd,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "intel-npu-compiler";
  version = "1.38.0";
  # Intel's release build stamp, part of the asset name.
  build = "20260910-34487311128";

  src = fetchurl {
    url = "https://github.com/intel/linux-npu-driver/releases/download/v${finalAttrs.version}/linux-npu-driver-v${finalAttrs.version}.${finalAttrs.build}-ubuntu2604.tar.gz";
    hash = "sha256-g2hebZL02xymXkQoRtSHx/6xM1Y0szmUKSzrOPkzvMc=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
  ];

  buildInputs = [
    stdenv.cc.cc.lib # libstdc++, libgcc_s
    tbb
    zstd
    zlib
  ];

  unpackPhase = ''
    runHook preUnpack
    tar -xzf $src
    dpkg-deb -x intel-driver-compiler-npu_*.deb root
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/lib root/usr/lib/x86_64-linux-gnu/libopenvino_intel_npu_compiler*.so
    runHook postInstall
  '';

  meta = {
    description = "Intel NPU model compiler for the Level Zero NPU driver and OpenVINO";
    homepage = "https://github.com/intel/linux-npu-driver";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
