# TODO

## In progress
- [ ] **Adjustment guides** (video outline + center cross + x/y/scale readout)
  - While moving/scaling the video: cyan video outline at the display bounds, a blue center cross at the VIDEO center (line it up against the red ring crosshair in Grid View to center the video), and an x/y/scale readout stacked just up-left of the ring center (in the dark middle — not a corner)
  - Auto-hide ~700 ms after the last move/scale (`ADJUST_GUIDE_LINGER_MS`, stamped via `lastAdjustMillis` on any arrow/scale key) and immediately on reset (`R`)
  - Drawn in `draw()` AFTER sampling + the DMX write → guides never touch `cellColors` or the bytes on the wire, even while Art-Net is sending
  - No new hotkeys (reuses move/scale/reset). Open question for Saurabh: blue cross on the VIDEO center (current) vs a fixed pin at the ring center

## Up next
- (Phase 9 ESP32 ring receiver is the only remaining item — see Deferred)

## Decisions
- `frameRate(30)` stays commented out — sketch runs uncapped (~56 fps). Decided 2026-05-29: NOT restoring it. Art-Net send is throttled independently to ~30 Hz via a millis timer (`DMX_SEND_INTERVAL_MS`) so the receiver isn't flooded.

## Deferred
- [ ] Phase 9 — ESP32 NeoPixel ring receiver (build only when Saurabh asks)

## Done
- [x] **Phase 8 — Config persistence (data/config.json)** ✓ tested working 2026-05-29
  - Save on `exit()` AND the `S` hotkey (exit() doesn't fire on a force-kill / IDE-Stop, per the freeze gotcha)
  - Restore on startup BEFORE the UI is built (controls show restored values): ring N + grid/labels/preview, color mode/gamma/brightness, Art-Net target (IP/port/universe/subnet/broadcast); per-key defaults when missing
  - Auto-load last video only if the file still exists (else amber log), then re-apply saved transform (loadMedia resets it first)
  - Art-Net target restored but NOT auto-started (no surprise broadcast on launch)
  - Bugfix (#4): a focused ControlP5 text field makes global `keyPressed` bail (`ui.isTextfieldFocused()`) so Backspace edits the field instead of clearing the video, and hotkeys don't fire while typing
  - Bugfix: GAMMA field `setAutoClear(false)` + echo the applied/clamped value on Enter — default autoClear blanked the field on submit
- [x] **Phase 7 — Color pipeline (gamma + brightness)** ✓ committed & tested working 2026-05-29
  - `ColorPipeline.pde`: RAW / GAMMA / GAMMA+BRIGHT; gamma 2.2 (256-entry table, rebuilt on change); brightness 0.5; `process(color)→color`. Default GAMMA+BRIGHT
  - Applied in `RingGrid.writeToDMXBuffer(dmxData, pipeline)` AND `drawPreview(pipeline)` → WYSIWYG preview
  - UI: BRIGHT % slider, GAMMA field, MODE cycle button (left column); hotkeys M / [ / ]; `syncColorControls()`
  - Panel UI_H 240→300 (window 480×780); video area unchanged
- [x] **Phase 6c — UI layout polish + colored console** ✓ verified working 2026-05-29
  - TOP-LEFT: OPEN VIDEO + GRID/LABELS/PREVIEW on one row (tight pitch); N slider below — shortened, caption to the RIGHT, accent foreground (fill always visible)
  - PREVIEW toggle mirrors `C`; `C` calls `ui.syncToggles()`; preview default ON
  - TOP-RIGHT: Art-Net cluster; light vertical separator L/R; full-width custom colored console on the bottom (info grey / ok green / warn amber / err red via `log()`/`logOk()`/`logWarn()`/`logErr()`)
  - Temp green test line removed after confirmation
- [x] **Phase 6b — Art-Net UI fields** ✓ verified working 2026-05-29
  - IP/port/universe/subnet textfields (INTEGER filter), BCAST toggle locks/dims the IP field, single START/STOP toggle (caption flips)
  - `startDMX()` rebuilds the sender from current field values (retarget without code edits); `stopDMX()` blackout + stop; `A` key funnels through the same path + `syncDmxToggle()`
  - Patterns from humanoid_face_twin/Processing/ArtNetSender
- [x] **Phase 6a — Art-Net send** ✓ verified on an Art-Net monitor 2026-05-29 (packets on universe 0, correct channel layout)
  - `DMXSender.pde` (near-verbatim from humanoid_face_twin); `dmxData[512]`; `RingGrid.writeToDMXBuffer()` writes raw RGB → channels i*3..i*3+2
  - Throttled send (~30 Hz `DMX_SEND_INTERVAL_MS` millis timer, decoupled from the uncapped draw loop); zeroes buffer each tick so cleared video blanks the ring
  - `A` toggles send (lazy create + connect); `exit()` sends all-zero blackout; pixelDensity≠1 startup WARNING guard
  - Defaults: broadcast 255.255.255.255:6454, universe 0, subnet 0. Requires `ch.bildspur.artnet` library
  - UI retargeting fields are Phase 6b (see In progress)
- [x] **Phase 5** — Pixel sampling + preview discs ✓ implemented & visually confirmed 2026-05-29; re-verified at `pixelDensity(1)` 2026-05-29 (startup log reads pixelDensity=1 — sampling 1:1 with logical coords, values trustworthy for Phase 6)
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
