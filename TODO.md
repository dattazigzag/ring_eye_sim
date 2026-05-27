# TODO

## In progress
- [ ] **Phase 3** — Ring grid overlay (visual only, N=12 hardcoded)

## Up next
- [ ] Phase 4 — UI panel + N slider
- [ ] Phase 5 — Pixel sampling (color extraction)
- [ ] Phase 6 — Art-Net send
- [ ] Phase 7 — Color pipeline (gamma + brightness)
- [ ] Phase 8 — Config persistence

## Deferred
- [ ] Phase 9 — ESP32 NeoPixel ring receiver (build only when Saurabh asks)

## Done
- [x] **Phase 2** — Video transform via keyboard ✓ verified 2026-05-27
  - Tested: drop + reset, arrows, Shift+arrows, Cmd+↑/↓ scale, R reset, Space pause/play, sequential drop replace
  - Bug found & fixed: Movie.loop() does NOT reliably resume from paused state in Processing 4. Resume must use .play() — the initial loop flag persists. Documented in `contexts/99_gotchas.md`.
- [x] **Phase 1** — Skeleton + video drag-and-drop ✓ verified 2026-05-27
  - Tested: two consecutive .mov drops, BACKSPACE clear, clean exit
  - Bug found & fixed: SDrop is broken under P3D. Documented in `contexts/99_gotchas.md`.

---

See `contexts/02_build_plan.md` for the detailed scope and test steps for each phase.
