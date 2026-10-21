# Linux performance hill-climb

Headless measurements of nanoui on Linux against itself and other GUI
frameworks. The JSON source of truth is `bench/frameworks.json`.

Host: Ubuntu 24.04, x86_64, **no discrete GPU**. nanoui draws with
`src/ui/raster.zig` through `ui.Tester` (offscreen, 900×640 at 2×). Mesa
llvmpipe is installed; windowed GL was not measured. rustc 1.83.0.

## Method

Scenes: `boxes` (600 moving shadowed rects), `text`, `scroll`, `list`,
`dashboard`, `springs` (2 000 `ui.motion` boxes), `letters`. 30 frames of
warm-up, 20 measured, one or two repeats. A change is kept only if a
scene improves by more than 3% and nothing important regresses by more
than that.

## Results (after climb)

| scene | nanoui frame p50 | nanoui encode | egui frame p50 | clay frame p50 |
|---|---:|---:|---:|---:|
| boxes | 0.074 ms | 24.0 ms | 0.107 ms | 0.064 ms |
| text | 0.205 ms | 2.1 ms | 0.315 ms | — |
| scroll | 0.510 ms | 2.0 ms | 1.431 ms | — |
| list | 0.057 ms | 2.0 ms | — | — |
| dashboard | 0.044 ms | 12.8 ms | — | — |
| springs | 0.571 ms | 4.7 ms | 0.334 ms* | — |
| letters | 0.081 ms | 0.71 ms | — | — |

\* egui's "springs" scene is `sin()` offsets, not spring physics. nanoui
solves a closed-form spring per channel.

nanoui **leads egui** on boxes, text and scroll (frame CPU). It trails
egui on the springs *declaration* because it integrates 2 000 real
springs. Clay is slightly ahead on boxes layout (0.064 vs 0.074) and
draws nothing.

CPU-raster **encode** is the Linux gap vs a GPU: Gaussian shadows on the
boxes/dashboard scenes are ~12–24 ms. Frame CPU stays under 1 ms. A 60 Hz
CPU window would drop on those two scenes; the OpenGL path (when a GPU
or llvmpipe window is used) is the intended live path and was not timed
here.

ReleaseFast binary: gallery 8.1 MB, counter 6.9 MB. Idle CPU is 0 (nothing
polls).

## Steps

### 0. Baseline

Motion API expansion and `scroll_max` on every scroller. First Linux
numbers: springs frame 0.807 ms (build 0.682), boxes encode 26 ms.

### 1. `ui.keyInt` (kept, springs −9.3%)

Integer keys for the 2 000-box scene. No formatted strings per box per
frame.

### 2. Reuse `ui.Canvas` (kept)

Hill-climb's CPU path now draws into a retained buffer, as a Linux
window does. letters encode −65%, dashboard encode −46%, text encode
−47%. boxes still redraws the whole framebuffer (every shadow moves).

### 3. `Channel.sample` at t ≤ 0 (kept, springs −11.5%)

`retarget` samples the old motion, then samples again at t = 0. The
second sample skipped the spring matrix.

### 4. `Spring.matrix` last-value cache (kept, springs −11.9%)

Channels of the same spring share a clock. The last closed-form
solution is reused when stiffness, damping, mass and t match.

Springs frame CPU: **0.807 → 0.571 ms (−29%)**. Further tries (shadow
math, per-channel SIMD) were not taken: they risk the Metal-matching
raster tests for <3% on the already-sub-millisecond frame path.

## Skips

GPUI, iced, Slint, Dioxus, Flutter, Qt Quick, GTK4 widgets, Tauri and
Electron did not build here. Reasons are in `bench/frameworks.json`
`skips`. The common blocker is Rust 1.85–1.87 / edition 2024 vs rustc
1.83. mygo's twin is Metal-only.

## Where nanoui still trails

- **vs GPUI:** not measured (GPUI would not build). Expected live-path
  gap is the CPU raster vs GPUI's GPU backend, not the view/layout tick.
- **vs egui springs:** egui is not solving springs.
- **vs Clay boxes:** Clay emits 600 flat commands and no shadows.
- **CPU shadows:** boxes/dashboard encode 12–24 ms. A GPU (or a cheaper
  CPU shadow) is the next climb, kept off this pass to protect raster
  equality tests.
