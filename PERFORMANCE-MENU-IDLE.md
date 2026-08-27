# Main menu idle energy — investigation notes

**Date:** 2026-08-15
**Branch this work sits on:** started from `feature-release-refinements`
**Device:** iPhone 17 Pro Max, iOS 27.0, debug build
**Trace:** `~/Documents/Mancala-perf-traces/2026-08-15-menu-idle.trace`
(kept outside the repo deliberately — 9.2 MB, don't commit it into history
without deciding you want it there forever)

---

## The question

Sitting on the main menu doing nothing, Xcode reported **Energy Impact: Very
High** and the phone was warm. Was that just the cost of running under Xcode, or
was something actually wrong?

**Answer: both.** Most of the alarming number was the debugger. Underneath it
there was one real bug (now fixed) and one real architectural cost (still there,
and it's a design decision rather than a defect).

---

## Headline numbers

Same build, same phone, same screen:

| Run | CPU |
| --- | --- |
| Under Xcode, debugger attached | 70–100%, "Very High" |
| Launched by Instruments, no debugger | **~23% of one core** |

Do not diagnose energy from a debugger-attached run. The gauge was inflating
this 3–4×.

CPU per 5-second bucket across the 45s trace:

```
t= 0-5s   117% of a core
t= 5-10s  172%              <- two threads baking textures in parallel
t=10-15s   60%
t=15-45s   ~20-23%          <- steady state
```

---

## Finding 1 — texture bakes were running on the main thread (FIXED)

The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every type is
main-actor isolated unless declared `nonisolated`. `BoardTextureBuilder` was not.

That meant this, in `BoardScene.bakedMaterial`:

```swift
let image = await Task.detached(priority: .userInitiated) {
    BoardTextureBuilder.baseColor(for: style)   // main-actor isolated!
}.value
```

...detached a closure inferred as `@MainActor` and faithfully detached it *onto
the main thread*. So `prewarmRemainingMaterials()` baked 2048×1024 procedural
textures, per pixel, on the main actor, right after launch — while the player
sits on the menu. Same for slab/ring mesh generation, the IBL environment bake,
and `BoardMaterialSwatch.bakeMissing`.

**Tells:** `Potential Structural Swift Concurrency Issue: unsafeForcedSync called
from Swift Concurrent context` in the console at runtime; the "main actor-isolated
… cannot be called from outside of the actor" warnings at compile time. Those
warnings *were* the bug being reported. Treat them as errors, not noise.

**This is the second time this has bitten the project** — the first was the
Impossible AI search freeze. Same root cause, same fix.

**Fix:** `nonisolated` on the pure-compute types. Verified in the profile: the
bakes now appear on background worker threads `0x335428` and `0x335421`, two in
parallel, which is what produces the 172% bucket.

---

## Finding 2 — the hidden 3D board was fully rendering (FIXED)

`Board3DView` is mounted unconditionally and only ever hidden with
`.opacity(0)` — under the main menu, *and* whenever the flat 2D theme is
selected. RealityKit's renderer is not occlusion-aware and knows nothing about
the opacity of the SwiftUI layer it draws into, so a hidden board was still
being shaded, still lit by the IBL environment, and still re-rendering
`keyLight`'s shadow map every frame.

Players who chose the flat theme were rendering a 3D board they never asked for,
for their whole session.

**Fix:** `BoardScene.setRendering(_:)` disables `boardRoot`, `keyLight` and
`iblEntity` — the camera rig stays enabled so the view still has something to
render with. Nothing is deallocated, so coming back is a flag flip, not a
rebuild. Driven from `ContentView.isBoardRenderingNeeded`.

**Result:** GPU share 41.7% → 9.7%, memory 391 MB → 252 MB.

A `warmRenderer()` holds rendering on for 1.5s after `buildRoot` so RealityKit
still compiles pipelines and uploads meshes behind the menu. That 1.5s is a
guess, not a measurement.

---

## Finding 3 — SwiftUI is completely idle (NOT A PROBLEM)

Body-evaluation counts on the menu, via `PerfProbe`:

```
ContentView       3 evaluations at launch, then never again
BoardBackground   once, then never
RealityUpdate     once, then never
PebbleStage       0-4/s (its idle loop retargeting)
```

Nothing redraws at frame rate. Two changes were made on the theory that
something did — gating the gyro on the menu/`scenePhase`, and removing a
duplicated `BoardBackgroundView` behind the menu. Both are correct hygiene and
worth keeping, but **neither was ever costing meaningful CPU.** Don't
re-derive that.

---

## Finding 4 — what the remaining ~23% actually is

Filtering every steady-state sample for frames in the app binary:

```
=== any app-binary frames, by thread ===
    3ms  [Main Thread]  __debug_blank_executor_main
```

Three milliseconds, and it's the Swift runtime's idle executor. **There is no
app-level hot spot left on the menu.** The remaining cost is:

- `CoreRE` (RealityKit's engine) — 34% of samples
- Metal / IOKit command submission — ~10%, via `IOGPUMetalCommandQueue submitCommandBuffer`
- entered through `ARView.doUpdateCallback(engine:deltaTime:)`, the per-frame engine tick

RealityKit runs off its own display link. Disabling the content emptied the
frame but the engine still ticks, culls and encodes one every frame. That fixed
floor is the ~20%.

Caveat: some `CoreRE` samples are `RealityEmitterBase::emitCameraGraphs` /
`RenderGraphFile::provide`, which is RealityKit's trace emitter and may be partly
an artifact of Instruments being attached.

---

## Still open — a design decision, not a bug

The only lever that removes the remaining ~20% is **unmounting the
`RealityView`** when the board isn't visible. That collides head-on with the
existing invariant that it must never be unmounted, because a rebuilt
`RealityView` strands the persisted `BoardScene` entity graph and the board comes
back permanently invisible.

| Option | Menu cost | Cost of entering a game |
| --- | --- | --- |
| Keep it warm (today) | ~20% of a core | instant |
| Unmount when hidden | ~0 | needs `BoardScene` to survive re-attachment; "Preparing 3D board…" would start appearing |

Recommendation: leave it. ~23% measured without a debugger, on a debug build,
is not the "Very High" that started this.

**Not yet done:** profile a **Release** build. Those per-pixel bake loops are
exactly what `-Onone` punishes hardest, so the launch burst is likely far
smaller for real users. That's the single most useful remaining measurement.

---

## Cleanup before this merges anywhere

- [ ] Delete `Mancala/ViewSupport/PerfProbe.swift` and its call sites
      (`ContentView`, `BoardBackgroundView`, `MenuPebbleStage`, `Board3DView`).
      DEBUG-only and compiled out of release, but it's scaffolding.
      The per-frame `RKFrame` tick in `SowingMotionSystem` has already been
      removed — its `Task` allocation skewed measurements.
- [ ] Decide on the `warmRenderer()` 1.5s window with a measurement.
- [ ] `MenuPebbleStage.swift` / `MenuPebbleDevMenu.swift` in this tree contain
      unrelated in-progress work that predates this investigation.

---

## How to reproduce the profiling

The Xcode license was accepted on 2026-08-15, so `xctrace` works. Launch rather
than attach — it avoids fighting LLDB *and* removes the debugger's overhead,
which is the single biggest distortion here.

```sh
xcrun xctrace record --device 00008150-000C78D80AC0401C \
  --template 'Time Profiler' --time-limit 45s --no-prompt \
  --output run.trace --launch -- com.jackdavey.mancala

xcrun xctrace export --input run.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output tp.xml
```

Parsing `tp.xml`: every element is either `id=` (definition) or `ref=` (a
back-reference to an id defined earlier *anywhere* in the document). Build
`{id: element}` over `root.iter()` first and deref everything — a naive
`findall` returns almost nothing. Rows carry `sample-time` (ns), `weight` (ns),
`thread`, and `tagged-backtrace/backtrace/frame` (leaf first, each with a nested
`binary`). Window out the first ~15s or launch work swamps the steady state.

Without a device, typecheck with the toolchain `swiftc` directly:

```sh
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc \
  -typecheck \
  -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk \
  -target arm64-apple-ios26.0 -swift-version 5 -default-isolation MainActor \
  $(find Mancala -name '*.swift')
```

`-default-isolation MainActor` is essential — without it you won't see the
isolation warnings that Finding 1 turned on.

---

## Files touched

| File | Change |
| --- | --- |
| `Board3D/BoardTextureBuilder.swift` | `nonisolated` on the enum — **the important fix** |
| `Board3D/BoardMeshBuilder.swift` | `nonisolated` on pure functions, `MeshData`, `std_reversed` |
| `Board3D/BoardLayout3D.swift` | `nonisolated` |
| `Models/GameSettings.swift` | `BoardMaterialStyle` → `nonisolated`, `Sendable` |
| `Board3D/BoardScene.swift` | `setRendering`, `applyRenderingState`, `warmRenderer` |
| `ContentView.swift` | `isBoardRenderingNeeded`; gyro gated on menu + `scenePhase`; duplicate background removed; `gameContentOpacity` now hides the game on all platforms |
| `ViewSupport/BoardBackgroundView.swift` | probe call site only |
| `ViewSupport/PerfProbe.swift` | new, temporary scaffolding |
| `Board3D/Board3DView.swift` | probe call site only |
