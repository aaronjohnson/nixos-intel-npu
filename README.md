# nixos-intel-npu

Run models on the **Intel NPU** ("Intel AI Boost") of Core Ultra laptops on NixOS.

nixpkgs ships Intel's NPU driver (`hardware.cpu.intel.npu.enable`) but not the
**model compiler** the driver needs to turn a model into something the NPU can run.
Without it the driver loads, but every attempt to compile a model fails:

```
dlopen: /run/opengl-driver/lib/libopenvino_intel_npu_compiler_loader.so: cannot open shared object file
```

This flake packages that compiler from Intel's prebuilt
[linux-npu-driver](https://github.com/intel/linux-npu-driver) release (the
`intel-driver-compiler-npu` package; the compiler is open source,
[openvinotoolkit/npu_compiler](https://github.com/openvinotoolkit/npu_compiler),
Apache-2.0) and patches it to use nixpkgs' libraries.

Tested on a Framework Laptop 13 Pro (Core Ultra X7 358H, NPU 5) with
nixos-unstable, driver 1.38.0:

| | Without | With |
|---|---|---|
| Intel's `npu-umd-test --config none` | 193 passed, 122 failed | 315 passed, 0 failed |
| OpenVINO 2026.4, small conv net | NPU not usable | NPU: 2.9 ms vs CPU 8.7 ms, same results |

## Use

```nix
# flake.nix
inputs.nixos-intel-npu = {
  url = "github:aaronjohnson/nixos-intel-npu";
  inputs.nixpkgs.follows = "nixpkgs";
};

# in your nixosSystem modules
nixos-intel-npu.nixosModules.default
{ hardware.intel-npu-compiler.enable = true; }
```

This also turns on `hardware.cpu.intel.npu.enable`, and puts the compiler next to
the driver in `/run/opengl-driver/lib`.

## Binary cache

CI builds both versions and pushes them to [nixos-intel-npu.cachix.org](https://nixos-intel-npu.cachix.org).
The source build is compiled and tested on a laptop with an Intel NPU (Intel's
`npu-umd-test` on real hardware) before it lands in the cache. The flake offers the cache
via `nixConfig`; to use it system-wide:

```nix
nix.settings = {
  substituters = [ "https://nixos-intel-npu.cachix.org" ];
  trusted-public-keys = [ "nixos-intel-npu.cachix.org-1:ikhkuI/crInBQxA1PBUQAupWk13HfJCDAIYHHn7/g3A=" ];
};
```

## Building from source

The default package repackages Intel's prebuilt compiler (installs in seconds).
The flake also builds it from source, following Intel's own recipe in
linux-npu-driver (`compiler/*.cmake`):

| Package | What it is |
|---|---|
| `npu-compiler-llvm` | Intel's LLVM/MLIR fork ([intel-staging/npu-compiler-llvm](https://github.com/intel-staging/npu-compiler-llvm), 26 commits on LLVM 23, mostly MLIR quantisation types and API additions), built on its own like nixpkgs' `triton-llvm`. `buildTests = true` runs `check-mlir`: 3299 passed, 0 failed. |
| `intel-npu-compiler-source` | OpenVINO plus [openvinotoolkit/npu_compiler](https://github.com/openvinotoolkit/npu_compiler), built against `npu-compiler-llvm` (`ENABLE_PREBUILT_LLVM_MLIR_LIBS`), installing only the two libraries. |

Verified the same way as the binary: `npu-umd-test` 315/315, and OpenVINO runs a
conv net on the NPU matching the CPU to 1e-4. Expect a long build (LLVM plus about
3700 compiler steps).

To use it with the module:

```nix
hardware.intel-npu-compiler.package =
  nixos-intel-npu.packages.x86_64-linux.intel-npu-compiler-source;
```

Not everything is from source: 794 small **SHAVE kernels** (`sw_runtime_kernels/**/prebuild`,
7 MB, Git LFS) run on the NPU's own vector cores and are built with Intel's
MoviTools, which isn't public. They ship prebuilt, like firmware, and the package
declares `sourceProvenance = [ fromSource binaryFirmware ]`.

Notes for the build: the version-string git lookups are patched to the pinned
revisions; GCC 16 needs `-Wno-error` for one false-positive `maybe-uninitialized`
in MLIR-generated parsers and one harmless unused counter (details in
`package-source.nix`).

## OpenVINO

nixpkgs' OpenVINO has its own problem: its NPU plugin `dlopen`s `libze_loader.so.1`
but that isn't on its search path, so OpenVINO never lists the NPU. Until that's
fixed in nixpkgs:

- set `hardware.intel-npu-compiler.openvinoWorkaround = true;` (puts the Level Zero
  loader on `LD_LIBRARY_PATH`), or set `LD_LIBRARY_PATH` just for the program, and
- compile with the driver's compiler, since OpenVINO only looks for one in its own
  directory:

```python
core = openvino.Core()
compiled = core.compile_model(model, "NPU", {"NPU_COMPILER_TYPE": "DRIVER"})
```

## Plans

Upstream to nixpkgs: `npu-compiler-llvm` and the source-built compiler (hooked into
`intel-npu-driver`), and separately the Level Zero runpath for OpenVINO's NPU plugin.

## Licence

The Nix code here is MIT. The compiler binaries are Intel's, under Apache-2.0.
