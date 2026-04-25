---
name: Bug report
about: Something in fluera_canvas isn't behaving as documented
title: "[bug] "
labels: bug
---

## What happened

<!-- One paragraph describing the bug. Skip the dramatic build-up. -->

## Expected behaviour

<!-- What did you expect to see instead? -->

## Reproduction

Minimal Flutter snippet that reproduces the bug. Less than 30 lines if
possible. Inline, not as an attachment.

```dart
import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

void main() => runApp(const MaterialApp(
  home: Scaffold(body: FlueraCanvas()),
));
```

Steps to trigger the bug starting from a fresh `flutter run`:

1. ...
2. ...
3. ...

## Environment

- `fluera_canvas` version: <!-- e.g. 0.3.0 -->
- Flutter version: <!-- output of `flutter --version` -->
- Platform: <!-- Android / iOS / Linux / macOS / Windows / Web -->
- Build mode: <!-- debug / profile / release -->
- Device & GPU (if mobile): <!-- e.g. Pixel 7 / Adreno 660 / Xiaomi 2107113SG -->
- Rendering backend: <!-- Skia / Impeller-Metal / Impeller-Vulkan / CanvasKit / WebGPU -->

## Logs

Paste the relevant lines from `flutter run`. Filter out the OS noise
(GPU vendor strings, profile-installer banners, …) and keep what comes
out of your Dart code or the Flutter framework.

```
<paste here>
```

## Additional context

<!-- Screenshot / GIF / link to a stripped-down demo repo. Optional. -->
