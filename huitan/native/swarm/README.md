# Optional CPU swarm prototype

This is an opt-in, single-threaded Godot GDExtension experiment. World and City
continue to use GDScript. It is **not enabled in production**. The captured
128-enemy monument collision regression is now fixed in both backends;
the performance target still requires further work.
See [performance evidence](../../docs/gameplay/attack-performance.md).

## Scope and rollback

`SceneCombatConfiguration.native_swarm_enabled` selects the optional kernel.
It defaults to `false`; changing it back immediately restores the script planner
and movement for existing actors. Missing binaries also retain the script path.
The benchmark enables the central scheduler alongside the native kernel; reported
whole-candidate differences therefore include both changes.

The kernel batches dense-crowd pair forces using the existing stable-slot input
and neighbor-list invalidation. Ordinary chase and flat movement run in C++, with
one synchronous native call per actor. Route/terrain qualification and public
combat events still call the existing scripts. This is **partial batching**, not
an all-actor data simulation or a worker-thread implementation. Special moves,
damage, animation, wall geometry, and simulation frequency remain unchanged.

The ground motor faithfully ports the existing sweeps and conservative absence
proofs; uncertain geometry returns to `CharacterBody3D.move_and_slide()`. This
keeps real wall collision. Ordinary movement excludes the player's body from
recovery; its CharacterBody fallback adds and removes a scoped exception. This
prevents implicit player overlap recovery from pushing monsters into walls.
Lock-line charge retains real player contact and damage.
Do not relax the 3 mm inner-capsule QA threshold to accept a timing result.

## Build locally

Currently validated only with **Godot 4.7.2, single precision, Windows x64**.
Requirements: Git, CMake 3.22+, Python 3, Visual Studio 2022 C++ tools and Windows
SDK. No Godot engine rebuild is required.

```powershell
./native/swarm/build.ps1 -GodotPath <Godot.exe> -PythonPath <python.exe>
```

The script pins official `godot-cpp` to
`2bb1acf6f8ae1ce96ac7b9ba3a10b499c59c49ec`, dumps the API from the supplied engine,
and checks version/precision before compiling. It places dependencies and build
data under `D:/.codexfile`; override `-GodotCppPath` and `-BuildDirectory` if needed.
The local output `bin/hd2d_swarm.dll` is ignored by Git.

The manifest lives outside `res://` and is loaded only on explicit request.
Export packaging, other platforms, other engine versions, and live DLL reload
are not implemented. A normal exported game does not include this prototype.

## Validate (128 enemies only)

```powershell
./huitan/tools/run_tests.ps1 -GodotPath <Godot.exe> -Suite native
./huitan/tools/benchmark_native_swarm.ps1 -GodotPath <Godot.exe> -Pairs 2
```

When explicitly requested, use the actual display for FPS measurement:

```powershell
& <Godot.exe> --resolution 1440x900 --disable-vsync --max-fps 0 --path huitan --audio-driver Dummy --script res://tools/benchmark_combat_fps.gd -- --count=128 --native-queries --with-native-prototype --output=D:/.codexfile/work/fps-script.json
```

Add `--native-swarm` after `--` for the candidate. Create the output directory
first. This is a real-time rendered test; do not pass `--headless` or
`--fixed-fps`. It uses a stationary 20-second simulation warmup, then the same
3/2/2/4-second nominal gameplay phases. Expensive wall QA runs outside frame
sampling. It records actual wall-clock FPS and the phase-end frustum population.
Counters and nested native timers are off. Optional `--gpu-timing` adds viewport
timers for a separate diagnostic run; leave it off for primary FPS comparisons.
No screenshots are captured. Sound is muted by the benchmark.

Tests require the DLL. Ordinary `regression` and `all` exclude optional native
tests and remain usable without a compiler. The comparison runs script/native/
native/script in separate headless processes, verifies source and DLL hashes,
birth IDs, density samples, real sword hits and ricochet interactions. It keeps
the 60 Hz simulation; timings are CPU callback windows, **not rendered FPS**.

By default, any failed behavior gate aborts acceptance. Use
`-CollectRejectedDiagnostics` only to collect all arms of an already failing
experiment: `validation.json` still records rejection and the command exits
unsuccessfully. No timing from rejected runs constitutes performance acceptance.

The benchmark samples wall intrusion every 30 ticks. The separate movement tests
check every tested step; neither covers every possible crowd contact. A diagnostic
every-step replay originally detected transient monument-edge intrusion during
normal CharacterBody fallback. After the scoped-player fix, the original failed
case and the native case each pass 84,480 per-step checks. Passing sampled
benchmarks alone is still insufficient evidence for untested contacts. Visuals
and gameplay feel require manual QA.

## Dependency license

`godot-cpp` is maintained by the Godot Engine contributors under the MIT license:
[pinned source and license](https://github.com/godotengine/godot-cpp/blob/2bb1acf6f8ae1ce96ac7b9ba3a10b499c59c49ec/LICENSE.md).
Its source is fetched to the external cache rather than vendored here. Any future
binary distribution must include its license notice.
