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

Upstream both fixes to nixpkgs: the compiler as part of `intel-npu-driver`, and the
Level Zero runpath for OpenVINO's NPU plugin.

## Licence

The Nix code here is MIT. The compiler binaries are Intel's, under Apache-2.0.
