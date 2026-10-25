# Changelog

Field reports from the lab bench. Newest report on top, numbered in the order
they were filed. Each says what changed for someone using the flake, what now
works on real hardware, and what is still known not to. All testing so far is
on one machine: a Framework Laptop 13 Pro (Core Ultra X7 358H, NPU 5) on
nixos-unstable.

## Field report 4 · 10 October 2026 · in step with the nixpkgs drafts

The packages were brought into line with the drafts being prepared for
nixpkgs, so what you build here is what is proposed upstream.

- `npu-compiler-llvm` is versioned by the date of the packaged commit
  (2026-08-18) and no longer passes options this LLVM has dropped
  (`LLVM_ENABLE_TERMINFO`, `LLVM_BUILD_EXAMPLES`).
- `intel-npu-compiler-source` uses `onetbb` directly rather than the `tbb`
  alias, and drops an unused `pkg-config` and a redundant `--strip`.
- CI on the self-hosted NPU runner now works with the Cachix cache (the
  runner is not a trusted Nix user, so it no longer adds itself as a
  substituter), and reports its progress while the long source build runs.

Still known not to work: nothing upstream yet. Using the compiler on NixOS
still means using this flake.

## Field report 3 · 10 October 2026 · a binary cache, tested on the bench

CI now builds everything and pushes it to
[nixos-intel-npu.cachix.org](https://nixos-intel-npu.cachix.org), so the
source build no longer has to be compiled on your own machine.

- Every push and pull request: `nix flake check` and the prebuilt compiler,
  built on GitHub-hosted runners and pushed to the cache.
- Pushes to `main` and manual runs only (never pull requests): the LLVM fork
  and the source-built compiler are built on a self-hosted runner with an
  Intel NPU, which then runs Intel's `npu-umd-test` on the real NPU before
  the result is pushed to the cache.
- The flake offers the cache through `nixConfig` (Nix asks before using it);
  the README shows how to add it system-wide.

Still known not to work: the cache covers `x86_64-linux` only, the only
system the flake builds for.

## Field report 2 · 10 October 2026 · the compiler from source

The flake can now build the NPU compiler from source, following Intel's own
recipe in linux-npu-driver 1.38.0. Point the module at it with
`hardware.intel-npu-compiler.package`.

- `npu-compiler-llvm`: Intel's LLVM/MLIR fork, built as its own package (like
  nixpkgs' `triton-llvm`). With `buildTests = true` it runs `check-mlir`:
  3299 passed, 0 failed.
- `intel-npu-compiler-source`: OpenVINO plus openvinotoolkit/npu_compiler at
  the revisions linux-npu-driver pins, built against `npu-compiler-llvm`,
  installing only the two compiler libraries in the usual `lib/` and
  `include/` layout.
- On the bench it matches Intel's binary: `npu-umd-test` 315/315 passed, and
  OpenVINO runs a conv net on the NPU matching the CPU to 1e-4. An early build
  passed only 244 of 315 because the NPU's SHAVE kernels had been fetched as
  Git LFS pointer files; they are now fetched properly.
- GCC 16 needs `-Wno-error` for one false-positive `maybe-uninitialized`
  warning in MLIR-generated parsers and for one harmless unused counter. The
  reasoning is written up in `package-source.nix`.

Still known not to be from source: the 794 SHAVE kernels (7 MB) that run on
the NPU's own vector cores. They are built with Intel's SHAVE toolchain,
which is not public, so they ship prebuilt like firmware, and the package
says so in `sourceProvenance`. Expect a long build: LLVM, then about 3700
compiler steps.

## Field report 1 · 10 October 2026 · first light on the NPU

nixpkgs ships Intel's NPU driver but not the model compiler it needs, so on
NixOS the driver loads and every model compile fails. This flake supplies the
compiler.

- `intel-npu-compiler`: the compiler libraries from Intel's prebuilt
  linux-npu-driver 1.38.0 release, patched to use nixpkgs' libraries.
- `hardware.intel-npu-compiler.enable`: turns on
  `hardware.cpu.intel.npu.enable` and puts the compiler next to the driver in
  `/run/opengl-driver/lib`, where the driver looks for it.
- On the bench, Intel's `npu-umd-test` went from 193 passed and 122 failed to
  315 passed, and OpenVINO 2026.4 runs a small conv net on the NPU in 2.9 ms
  (8.7 ms on the CPU) with the same results.

Still known not to work: nixpkgs' OpenVINO does not find the NPU on its own,
because its NPU plugin cannot find the Level Zero loader. Until that is fixed
in nixpkgs, set `hardware.intel-npu-compiler.openvinoWorkaround = true;` (or
set `LD_LIBRARY_PATH` for the one program) and compile with
`{"NPU_COMPILER_TYPE": "DRIVER"}`. See the README.
