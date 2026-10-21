# Linux performance hill-climb

Headless measurements of nanoui on Linux against itself and other GUI
frameworks. The JSON source of truth is `bench/frameworks.json`. Each
kept change is a step here.

Host: recorded per run (OS, arch, renderer). This environment has no
discrete GPU; the CPU raster (`src/ui/raster.zig`) or Mesa llvmpipe is
used. Windows stay hidden (`ui.Tester`, `--nanoui-snapshot`).

## Method

- Scenes: `boxes` (600 moving rects), `text`, `scroll`, `list`,
  `dashboard`, plus motion scenes (`springs`, `letters`) once they land
  in hillclimb.
- Metrics: frame CPU p50/p99, dropped frames (over 16.7 ms), encode/draw,
  cold start to first frame, idle CPU, RSS, binary size.
- A change is kept only if a scene improves by more than 3% and nothing
  else regresses by more than that.
- Peer frameworks that will not build are skipped, with a reason in the
  JSON `skips` list. Runs stay bounded (`--frames` 60–120, `--repeat` 1–2).

## Steps

### 0. Baseline (this PR)

Motion API expansion (scroll-linked values, drag/snap, shared-element,
staggered text) and `scroll_max` recorded for every scroller. First
Linux numbers go in `bench/frameworks.json` as `baseline`.
