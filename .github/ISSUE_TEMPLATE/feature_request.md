---
name: Feature request
about: Propose a new public API, widget, or behaviour for fluera_canvas
title: "[feat] "
labels: enhancement
---

## What you want

<!-- One paragraph describing the feature. -->

## Why

What problem does it solve? What's the use case? What does your
code currently look like to work around the absence of this feature?

## Proposed API

If you have a shape in mind, sketch it. Otherwise leave this open —
we'll iterate during the discussion.

```dart
// e.g. a new constructor parameter:
FlueraCanvas(
  ...,
  myNewFeature: MyNewFeatureConfig(...),
);

// or a new method on the State:
canvasKey.currentState?.doNewThing();
```

## Alternatives considered

What other approaches did you think about? Why did you reject them?
("Could be done app-side" is a valid answer — we tend to keep the SDK
headless and push product decisions to the consumer when possible.)

## Scope

Is this a candidate for the free `fluera_canvas` SDK, or for the
commercial `fluera_canvas_gpu` add-on, or for an out-of-tree consumer
package? See [CONTRIBUTING.md](../../CONTRIBUTING.md#what-lives-in-fluera_canvas-vs-fluera_canvas_gpu)
for the split rationale.

## Additional context

<!-- Mock-ups, comparison with other libraries, links to relevant
     prior art. Optional. -->
