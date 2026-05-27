# TODO

## In progress
- [ ] **Phase 4** — UI panel + N slider (ControlP5, console textarea)

## Up next
- [ ] Phase 5 — Pixel sampling (color extraction)
- [ ] Phase 6 — Art-Net send
- [ ] Phase 7 — Color pipeline (gamma + brightness)
- [ ] Phase 8 — Config persistence

## Deferred
- [ ] Phase 9 — ESP32 NeoPixel ring receiver (build only when Saurabh asks)

## Done
- [x] **Phase 3** — Ring grid overlay (visual only, N=12 hardcoded) ✓ verified 2026-05-27
  - RingGrid class: geometry matches Figma (R=350, BREATHE=0.95, inscribed-tangent cellSize)
  - Stroked red cells (no fill — video shows through), red labels outside cells, dim red guides
  - Hotkeys: G toggle grid, L toggle labels
  - Per-cell geometry precomputed into primitive arrays (zero per-frame allocations)
  - **Perf**: dropped Java2D (8 fps) → switched to P3D + file picker for `O` (27 fps steady)
  - **Perf**: added pre-resize-on-CPU pattern (MediaHandler.processedImage at canvas-fit size)
    — same trick as the existing humanoid_face_twin project; cuts texture upload bandwidth
  - Documented Java2D vs P3D, the GStreamer reflection exceptions, and the resize pattern
    in `contexts/99_gotchas.md`
- [x] **Phase 2** — Video transform via keyboard ✓ verified 2026-05-27
  - Bug found & fixed: Movie.loop() does NOT reliably resume from paused state in Processing 4.
    Resume must use .play() — the initial loop flag persists. In `contexts/99_gotchas.md`.
- [x] **Phase 1** — Skeleton + video drag-and-drop ✓ verified 2026-05-27
  - Bug found & fixed: SDrop is broken under P3D. In `contexts/99_gotchas.md`.

---

See `contexts/02_build_plan.md` for the detailed scope and test steps for each phase.
