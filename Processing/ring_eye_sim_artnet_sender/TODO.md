# TODO

## Done (2026-05-29)
- [x] **Phase 12b** — Art-Net UI rework + full panel relay out. **Done + tested 2026-05-29.**
  - Banded panel (window 960×920, `UI_H` 440): a SHARED band (source/view · color · art-net transport · mqtt) over a PER-EYE band split at center (`LEFT EYE - clone` | `RIGHT EYE - main`, right header in cyan accent). Each eye is ONE row — FLIP H/V on the left, UNIVERSE + IP in the column's spare width (spacing polish 2026-05-29). Full-width console below.
  - Per-eye ownership: each eye column owns FLIP + UNIVERSE + IP; only BROADCAST/PORT/SUBNET/START are shared. BCAST locks BOTH eye IP fields.
  - Per-eye target persistence: nested `artnet.{right,left}.{ip,universe}` + shared `{useBroadcast,port,subnet}`; legacy flat `targetIP`/`universe` falls back onto the right (main) eye.
  - Files: `ring_eye_sim_artnet_sender.pde` (`UI_H` 440; per-eye `universe` defaults; nested save/load; `publishRingConfig` → right eye; removed dead `targetIP`/`universe` globals); `VideoContainer.pde` (`targetIP` field); `UserInterface.pde` (full `setupControls` relay out, `updateIPField` both eyes, `startDMX` per-eye, `isTextfieldFocused`, `render` separators).

## Up next — two-container build (right=main + left=clone)
- [ ] **Phase 13** — Config persistence for mirror flags (per-eye H/V). The art-net per-eye persistence is already folded into 12b.

See `contexts/02_build_plan.md` for full scope + test steps per phase.

## Decisions (two-container — confirmed 2026-05-29)
- **Single decode, shared frame.** One `Movie`; both containers display the same frame. NOT two decodes + `jump()`-sync (that was only for the reference's two *different* videos). Frame-perfect sync, half the decode, one pipeline to babysit.
- **Two rings, two universes, two ESP32s.** Right (main) = universe 0, left (clone) = universe 1; shared subnet 0. Each ring owns channels `[0,3N)` of its own universe. Broadcast (single 255.255.255.255, differ by universe) or unicast (per-container IPs).
- **Mirror = per-container H + V**, applied at blit time; sampling reads the framebuffer after the blit so each ring follows its mirror with no sampler change. Mirror is the ONLY per-container property — transform/playback/N/color/grid-labels-preview are shared.
- **Right = main** (screen x=480), marked with a constant 12.5×12.5 no-stroke cyan `(57,184,213)` square (top-left inset). Left = clone (x=0). Loading is via the `O` picker / OPEN VIDEO (no drag-and-drop under P3D); the one video fills both.
- **Tester (`tools/`) mirrors the main/right only** — publishes the right ring's `{n,universe,subnet}`; no tester code change needed.
- Mirror controls are **UI toggles only** (no hotkeys for now).
- `frameRate(30)` stays commented out — sketch runs uncapped (~56 fps). Decided 2026-05-29: NOT restoring it. Art-Net send is throttled independently to ~30 Hz via a millis timer (`DMX_SEND_INTERVAL_MS`) so the receivers aren't flooded.

## Deferred
- [ ] **Phase 14** — ESP32 NeoPixel ring receivers **×2** (right→U0, left→U1; distinct static IPs). Build only when Saurabh asks. The `tools/` tester covers the right eye in the meantime.

## Done
- [x] **Phase 12a** — Dual-universe Art-Net SEND (per-container `DMXSender`). Tested + committed 2026-05-29. (Per-eye left universe is now its own UNIVERSE field, set in 12b — no longer right+1.)
- [x] **Phase 11 — Per-container H/V mirror** ✓ tested working 2026-05-29
  - `VideoContainer.render()` wraps the blit in `pushMatrix()` + `scale(±1,±1)` about the canvas/ring center when `mirrorH`/`mirrorV` are set; marker + ring overlay stay upright; sampling reads the framebuffer after the blit so each ring follows its own mirror (no sampler change)
  - `setMirrorH/V` + `toggleMirrorH/V` (logged); UI MIRROR cluster (R-H/R-V/L-H/L-V) in the right half of the panel
- [x] **Phase 10 — Dual canvas + shared-frame display via `VideoContainer`** ✓ tested working 2026-05-29
  - Window 480→960; two 480 canvases (left=clone x=0, right=main x=480) from ONE decode; thin divider; cyan main marker top-left of the right canvas
  - `VideoContainer` (Canvas + RingGrid + isMain + mirror stubs); `containers[]`; `ringGrid` alias = right/main ring; `apply*` fan-out (N + grid/labels/preview → both rings); one shared `loadPixels()` per frame feeds both samplers
  - `MediaHandler.getDisplayBounds(Canvas)`; `RingGrid.sampleColors()` no longer self-calls `loadPixels()`; UI N/G/L/P callbacks route through `apply*`
  - DMX still right-only (dual-universe is phase 12); tester unchanged
- [x] **Preview receiver sync (MQTT side-channel)** ✓ tested working 2026-05-29 — `tools/tailored_dmx_receiver`
  - Receiver renders a NeoPixel-ring twin of the server: discs + index labels + faint ring outline, mirroring server geometry (`ringR = w*350/1024`, same cellSize formula, LED 0 at 12 o'clock CW)
  - PIXELS over Art-Net (post gamma/brightness → accurate hardware preview); LAYOUT (`{n, universe, subnet}`) over MQTT topic `ring/config` (retained, qos 1)
  - Server publishes on connect + on N change (slider) + on Art-Net retarget (`startDMX`); MQTT is optional/non-fatal (Art-Net unaffected if no broker). `messageReceived` is an empty stub the library's callback lookup requires
  - Joël Gähwiler's MQTT library (Paho-based); subscription in `clientConnected()` so it survives reconnects
  - prereq: local mosquitto (`brew install mosquitto` → `brew services start mosquitto`). Start order: mosquitto → server → receiver. Receiver key: `L` toggles labels
  - **Config persistence added 2026-05-29**: `mqtt` block (`enabled`/`host`/`port`) now saved + restored alongside the others. Unlike Art-Net (target only, never auto-started), the MQTT on/off state IS persisted — it only publishes layout to a local broker, no hardware driven, so it's harmless and matches its default-ON. Restored in `loadConfig()` before the UI builds → host/port fields show the values and the toggle's initial `setValue` fires `startMQTT`/`stopMQTT`
  - Future hook: same broker can carry video-trigger / control topics later
- [x] **pixelDensity 2 (high-DPI) + density-aware sampling** ✓ tested working 2026-05-29 (display crisp, Art-Net correct)
  - `sampleColors()` reads `pixels[(y*d)*pixelWidth + (x*d)]` (`d = pixelDensity`) — correct at any density; d=1 is the old 1:1 path
  - `pixelDensity(1)` commented out in `settings()`; startup "INVALID" warning softened to an info line. Re-enable the line if the GStreamer freeze / a perf drop returns (sampler works either way)
- [x] **Adjustment guides** (video outline + center cross + x/y/scale readout) ✓ tested working 2026-05-29
  - Cyan video outline + cyan cross at the VIDEO center + x/y/scale readout that travels with the cross; auto-hide ~1000 ms after the last move/scale (`ADJUST_GUIDE_LINGER_MS`) and on reset
  - Drawn after sampling + the DMX write → never touches `cellColors` or the wire. No new hotkeys
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
