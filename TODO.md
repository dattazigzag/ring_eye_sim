# TODO

## In progress
- [ ] **Video freeze mitigation — watchdog soak test** (Processing 4.4.4 Intel). The GStreamer AppSink "Native object has been disposed" warnings still print and are expected (upstream race, can't be caught). Three mitigations now in place: `pixelDensity(1)`, 480×480 transcoded sources, and the auto-reload watchdog in `MediaHandler`. Soak-test: leave a clip looping for a long stretch and confirm the watchdog reloads (look for `[watchdog] … reloading`) instead of a hard freeze. Tune `WATCHDOG_TIMEOUT_MS` if it false-fires or recovers too slowly.
- [ ] **Phase 5** — Pixel sampling (color extraction + preview circles)

## Up next
- [ ] Phase 6 — Art-Net send
- [ ] Phase 7 — Color pipeline (gamma + brightness)
- [ ] Phase 8 — Config persistence

## Deferred
- [ ] Phase 9 — ESP32 NeoPixel ring receiver (build only when Saurabh asks)

## Done
- [x] **480×480 resize** ✓ verified 2026-05-28 (4.4.4 Intel)
  - Active area 1024→480, UI panel 200→240, total window 480×720
  - Ring radius proportional: `ringR = canvas.width * 350/1024` ≈ 164
  - Console relaid full-width, stacked below the control rows
  - Manual tweak kept: `drawCells()` strokeWeight 2→1
  - `pixelDensity(1)` confirmed required on 4.4.4 too (log shows pixelDensity=2 when omitted) — kept ON
- [x] **Watchdog auto-reload** (MediaHandler) — implemented 2026-05-28, soak test pending (see In progress)
  - `lastFrameMillis` stamped per successful `read()`; reload if no frame >3s while `shouldBePlaying`
  - Reloads via fresh `loop()` (not `jump()` — seek re-triggers the segment assertion); preserves transform
  - Source clips pre-transcoded to 480×480 H.264 (ffmpeg) to cut decode load + race frequency (see gotchas)
- [x] **Phase 4** — ControlP5 UI panel (N slider, toggles, console) ✓ verified 2026-05-27
  - PIXELS (N) slider 8–60 snapped even → RingGrid.setN()
  - OPEN VIDEO button (mirrors O), GRID/LABELS toggles (mirror G/L)
  - Console Textarea (pattern from humanoid_face_twin); log() routes to console + UI
  - RingGrid: setN() + set/toggle pairs, uiSyncing guard prevents double-toggle
- [x] **Phase 3** — Ring grid overlay + perf fixes (P3D + CPU pre-resize) ✓ verified 2026-05-27
  - Stroked red cells, labels, guides; geometry matches Figma
  - 8 fps (Java2D) → 27 fps steady (P3D + processedImage pre-resize)
  - GStreamer reflection exceptions under Rosetta are harmless (see gotchas)
- [x] **Phase 2** — Video transform via keyboard ✓ verified 2026-05-27
  - Movie resume must use .play() not .loop() (see gotchas)
- [x] **Phase 1** — Skeleton + video drag-and-drop ✓ verified 2026-05-27
  - SDrop broken under P3D (see gotchas)

---

See `contexts/02_build_plan.md` for the detailed scope and test steps for each phase.
