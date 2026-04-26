# Contributing to fluera_canvas

Thanks for your interest in `fluera_canvas`. This document explains how
to set up a working dev environment, run tests, and submit a change.

## Repo layout

```
fluera_canvas/
├── lib/
│   ├── fluera_canvas.dart           # Public barrel
│   └── src/
│       ├── canvas/                  # FlueraCanvas, controller, gesture, toolbar
│       ├── core/                    # Engine primitives, scene graph base
│       ├── drawing/                 # Input pipeline + brush models
│       ├── rendering/               # Painters, spatial index, GPU bridge
│       ├── export/                  # Binary / JSON / PNG / .fluera codecs
│       └── utils/                   # Cross-cutting utilities
├── example/                         # Runnable gallery (7 demos)
├── test/                            # Unit + widget tests
├── doc/                             # Long-form guides (architecture, perf, …)
└── android/, ios/, linux/, ...      # Native plugin scaffolding
                                     # (full implementations live in
                                     # the commercial fluera_canvas_gpu)
```

Anything imported from `package:fluera_canvas/fluera_canvas.dart` is
part of the **semver contract**. Anything inside `src/` without a
corresponding export line is internal — do not depend on it from
consumer code.

### Source of truth for canvas-core

`fluera_canvas` is the **canonical home** for canvas, scene graph, rendering
and drawing primitives across the Fluera monorepo. Its sister package
`fluera_engine` is private and depends on this one — its older parallel
implementation in `lib/src/{canvas,drawing,rendering,core/scene_graph}` is
in **freeze**. Bug-fixes and new features for those concepts land here
first; engine picks them up via dependency. See the monorepo doc
`docs/CANVAS_OWNERSHIP.md` for the full rule and the migration tracker.

## Setup

```bash
git clone https://github.com/Lorencoshametaj/fluera_canvas.git
cd fluera_canvas
flutter pub get
cd example && flutter pub get && cd ..
```

Required:
- Flutter ≥ 3.27.0
- Dart ≥ 3.7.0

Optional:
- A physical Android device (Adreno GPU preferred) for verifying
  Impeller-Vulkan profile-mode behaviour — most regressions show up
  there before any other platform.

## Development workflow

```bash
# Type-check + lint
flutter analyze --no-pub

# Run all tests
flutter test

# Run a single test file
flutter test test/canvas_stroke_test.dart

# Format check (CI runs this)
dart format --output=none --set-exit-if-changed lib test

# Format in place
dart format lib test

# Run the example gallery
cd example && flutter run -d <device-id>

# Run the example in release/profile mode (catches more pipeline issues)
cd example && flutter run --profile -d <device-id>

# Pana score (matches pub.dev's analysis)
dart pub global activate pana
pana --no-warning --flutter-sdk "$HOME/development/flutter"
```

A change is **ready to merge** when:

- `flutter analyze` is clean
- All `flutter test` cases pass
- `dart format` is a no-op
- `pana` score ≥ 150 (current baseline; aim to keep or improve)
- A new test covers the change (unit for logic, widget for UI / lifecycle)
- README / CHANGELOG / dartdoc updated if the public API changed

## Commit conventions

We follow a lightweight **conventional-commit** style:

```
<type>(<scope>): <short summary>

<optional body>

<optional footer>
```

Types we use:

| Type | When |
|---|---|
| `feat` | New public API, new toolbar feature, new SDK widget |
| `fix` | Bug fix touching observable behaviour |
| `perf` | Performance improvement with no API change |
| `refactor` | Internal rework, no behaviour change |
| `docs` | README / CHANGELOG / dartdoc / `doc/` changes only |
| `test` | Adding / updating tests only |
| `chore` | Dependency bumps, tooling, repo hygiene |
| `release` | Version bump + tag |

Scopes you'll see in the history: `canvas`, `gesture`, `toolbar`,
`render`, `serializer`, `native-overlay`, `example`, `tests`.

Example:

```
fix(canvas): keep first stroke visible on Impeller-Vulkan profile

Vsync ticker drives setState every frame during a gesture so the
rendering pipeline doesn't coalesce mid-gesture frames. See
doc/troubleshooting-impeller.md for the long write-up.
```

## Pull requests

- Open an issue first if the change is non-trivial (new public API,
  breaking change, perf-sensitive area). API shape is converging on
  1.0; we want to avoid churn.
- One logical change per PR. Mixed PRs (feat + unrelated refactor)
  get split before merge.
- Re-run `flutter analyze`, `flutter test`, and `dart format` before
  pushing the final commit.
- Use the conventional-commit style for the PR title — it becomes
  the squash-merge commit message.

## What lives in `fluera_canvas` vs `fluera_canvas_gpu`

`fluera_canvas` (this repo, free MIT, on pub.dev):
- `FlueraCanvas` widget + drop-in toolbar
- Camera (`InfiniteCanvasController`) and gesture handling
- Pen / eraser tools
- Spatial index, viewport culling, undo/redo
- Serializer (binary + JSON), PNG export
- Background patterns
- Dart fallback live-stroke painter
- Scene-graph BASE primitives (visitor, node interfaces)

`fluera_canvas_gpu` (commercial, separate repo, license tiers
Indie / Team / Enterprise):
- Native GPU live-stroke pipeline (Vulkan / Metal / OpenGL / D3D11 / WebGPU)
- Sub-frame latency live ink

The split is intentional: a free pub.dev consumer can ship a fully
working canvas without the GPU plugin. With the plugin registered at
boot the live stroke transparently switches to the native renderer.

## Issue templates

Use the GitHub issue templates in `.github/ISSUE_TEMPLATE/` —
"Bug report" and "Feature request" — they include the fields we
need to triage quickly (Flutter version, platform, repro steps,
expected vs actual).

## Code style

- Lints come from `package:flutter_lints/flutter.yaml` plus the
  rules in `analysis_options.yaml`.
- 80-column soft limit, `dart format` is the source of truth.
- Public symbols MUST have dartdoc. Private symbols don't need it
  unless the rationale is non-obvious (workaround for a platform
  quirk, etc.).
- One painter per visual layer; stable painter instances + listenable
  repaints when the painter cost dominates a frame (see
  `_LiveStrokePainter`, `_CommittedStrokesPainter`).
- Prefer `setState` for app-level state, dedicated `ChangeNotifier`s
  (`_LiveStrokeNotifier`, `_CommitNotifier`) for render-state
  notifications routed through `super(repaint:)`.

## License

By contributing you agree your code ships under the same MIT license
as the rest of the package.
