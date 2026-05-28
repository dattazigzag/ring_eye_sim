# TODO

## In progress
- [ ] **480×480 resize** — verifying on Processing 4.4.4 (Intel). Active area 1024→480, UI panel 200→240, total window 480×720. Ring radius now proportional: `ringR = canvas.width * 350/1024` ≈ 164. Console relaid out full-width, stacked below the control rows. Manual tweaks under test (not yet committed): `drawCells()` strokeWeight 2→1; `pixelDensity(1)` temporarily commented out in `settings()`.
- [ ] **Phase 5** — Pixel sampling (color extraction + preview circles)

## Up next
- [ ] Phase 6 — Art-Net send
- [ ] Phase 7 — Color pipeline (gamma + brightness)
- [ ] Phase 8 — Config persistence

## Deferred
- [ ] Phase 9 — ESP32 NeoPixel ring receiver (build only when Saurabh asks)

## Done
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
