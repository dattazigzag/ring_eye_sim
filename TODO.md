# TODO

## In progress
- [ ] **Phase 6 — Art-Net send** — 6a implemented, PENDING TEST on an Art-Net monitor:
  - `DMXSender.pde` (near-verbatim from humanoid_face_twin); `dmxData[512]`; `RingGrid.writeToDMXBuffer()` writes raw RGB → channels i*3..i*3+2
  - Throttled send (~30 Hz `DMX_SEND_INTERVAL_MS` millis timer, decoupled from the uncapped draw loop); zeroes buffer each tick so cleared video blanks the ring
  - `A` toggles send (lazy create + connect); `exit()` sends all-zero blackout; pixelDensity≠1 startup WARNING guard
  - Defaults: broadcast 255.255.255.255:6454, universe 0, subnet 0. Requires `ch.bildspur.artnet` library
  - **6b remaining:** UI fields (IP / port / universe / subnet / broadcast toggle + START/STOP toggle) so a real ESP32 can be retargeted without code edits
- [ ] **Re-verify Phase 5 sampling at `pixelDensity(1)`** — the verification screenshots were captured with the startup log showing `pixelDensity=2`, where `pixels[y*width+x]` (logical coords) reads the wrong location. Sampling is only valid at `pixelDensity(1)`. Re-enable it, confirm the log reads `pixelDensity=1`, re-check the discs, THEN trust the values for Phase 6.

## Up next
- [ ] Phase 7 — Color pipeline (gamma + brightness)
- [ ] Phase 8 — Config persistence

## Decisions
- `frameRate(30)` stays commented out — sketch runs uncapped (~56 fps). Decided 2026-05-29: NOT restoring it. Art-Net send is throttled independently to ~30 Hz via a millis timer (`DMX_SEND_INTERVAL_MS`) so the receiver isn't flooded.

## Deferred
- [ ] Phase 9 — ESP32 NeoPixel ring receiver (build only when Saurabh asks)

## Done
- [x] **Phase 5** — Pixel sampling + preview discs ✓ implemented & visually confirmed 2026-05-29 (re-verify pending at pixelDensity 1 — see In progress)
  - `RingGrid.sampleColors()` averages video pixels in each cell's inscribed circle (r = cellSize/2) into `cellColors[]`; reads framebuffer via `loadPixels()` (relies on pixelDensity(1)), clamped to canvas region, bit-shift channel extraction, alloc-free
  - `drawPreview()` draws a filled disc of the sampled color per cell; `C` toggles `previewEnabled`
  - draw(): sample after video + zero-image, BEFORE overlay; gated on `previewEnabled` for now (phase 6 widens to `preview || artNet`)
  - monochrome sources → grey discs (luminance), expected; full RGB ready for color clips
- [x] **Video freeze + Texture.bufferUpdate NPE — FIXED** ✓ all errors gone 2026-05-29 (4.4.4 Intel)
  - Root cause: `processedImage.copy(loadedVideo, …)` resized off the *live* Movie on the render thread, racing the GStreamer AppSink callback → disposed-buffer warnings + fatal NPE in `Texture.bufferUpdate`
  - Fix: detach each frame (read → loadPixels → `System.arraycopy` into native-size `loadedImage`), resize off `loadedImage`, never the Movie; call `update()` LAST in `draw()` (after zero-image trick) — matches the old humanoid_face_twin project
  - Supporting (kept): `pixelDensity(1)`, 480×480 transcoded sources, watchdog as frame-drought safety net
  - See contexts/99_gotchas.md for full write-up
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
