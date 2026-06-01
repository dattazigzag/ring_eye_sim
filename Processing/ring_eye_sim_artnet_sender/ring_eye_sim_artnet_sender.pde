// =============================================================
// Ring Eye Sim — Art-Net Sender
// Phase 4 (+ patch): UI panel + N slider + console; pixelDensity(1);
//                    FPS readout on the UI instead of console
// =============================================================
// See contexts/02_build_plan.md for full phase plan.
//
// Hotkeys (cumulative):
//   O                    open file picker
//   SPACE                toggle play/pause
//   ←/→ ↑/↓              move video ±2 px  (Shift = ±20 px)
//   Cmd+↑ / Cmd+↓        scale × / ÷ 1.05
//   R                    reset transform (centered + fit)
//   G                    toggle ring grid   (syncs UI toggle)
//   L                    toggle cell labels (syncs UI toggle)
//   C                    toggle sampled-color preview discs
//   A                    toggle Art-Net send (broadcast, universe 0)
//   BACKSPACE            clear loaded video
// =============================================================

// Drop library for file drag-and-drop
import drop.*;

// Video library
import processing.video.*;

// Art-Net (phase 6) — "Art-Net for Processing" library (ch.bildspur.artnet)
import ch.bildspur.artnet.*;
import java.net.InetAddress;

// ControlP5 UI
import controlP5.*;

// Processing's KeyEvent (NOT java.awt.event.KeyEvent — different class)
import processing.event.KeyEvent;

// MQTT side-channel (phase: receiver sync) — Joël Gähwiler's "MQTT" library
// (Paho-based). Publishes ring layout (N + universe/subnet) so the preview
// receiver can mirror it live. Optional: the sketch runs fine with no broker.
import mqtt.*;

// =============================================================
// Constants
// =============================================================

final int CANVAS_W = 480;
final int CANVAS_H = 480;
final int UI_H     = 440;   // banded panel (phase 12b): shared row band + per-eye band (left | right) + console
final int NUM_CONTAINERS = 2;                    // right (main) + left (clone)
final int SKETCH_W = CANVAS_W * NUM_CONTAINERS;  // 960 — two 480 canvases side by side
final int SKETCH_H = CANVAS_H + UI_H;

// P3D for video performance; SDrop drag-drop is dead under P3D so we use the
// 'O' key file picker. See contexts/99_gotchas.md.
final boolean ENABLE_P3D = true;

// Transform step sizes
final int   MOVE_STEP_SMALL = 2;
final int   MOVE_STEP_LARGE = 20;
final float SCALE_STEP      = 1.05;  // 5% per press

// Console
final int CONSOLE_BUFFER_LIMIT = 200;

// Config persistence (phase 8) — relative to the sketch folder
final String CONFIG_PATH = "data/config.json";

// =============================================================
// Main objects
// =============================================================

Canvas           leftCanvas, rightCanvas;
VideoContainer   leftContainer, rightContainer;
VideoContainer[] containers;        // {leftContainer, rightContainer}
RingGrid         ringGrid;          // ALIAS = rightContainer.ring (the MAIN/right ring). UI/DMX/MQTT/config track this; N + grid/labels/preview fan out to BOTH rings via the apply* helpers.
MediaHandler     mediaHandler;
ColorPipeline    colorPipeline;     // phase 7 — gamma/brightness applied to preview + DMX (shared)
UserInterface    ui;
SDrop            drop;
// Per-container DMXSender lives on each VideoContainer (phase 12a): right + left
// each send their own ring on their own universe. No single global sender.

// =============================================================
// Art-Net config (phase 6) — defaults from project brief; UI fields in 6b
// =============================================================

byte[]  dmxData      = new byte[512];      // one DMX universe, zeroed each send
boolean enableDMX    = false;              // toggled with 'A'
boolean useBroadcast = true;               // broadcast vs unicast (shared transport)
int     artNetPort   = 6454;               // standard Art-Net port
int     subnet       = 0;
// Per-eye universe + target IP live on the VideoContainers (phase 12b).

// Send throttle — frameRate() is uncapped (~56 fps), so the Art-Net send is
// capped to ~30 Hz on its own millis timer, decoupled from the draw rate, so
// the receiver isn't flooded. (See TODO 'Decisions'.)
final int DMX_SEND_INTERVAL_MS = 33;       // ~30 Hz
int       lastDmxSendMillis    = 0;

// Transient video-adjustment guides — shown briefly while moving/scaling the
// video, auto-hidden a short while after the last adjustment (and on reset).
final int ADJUST_GUIDE_LINGER_MS = 1000;
int       lastAdjustMillis       = -100000;   // far in the past = hidden at startup

// MQTT side-channel — publishes ring layout (N + universe/subnet) so the preview
// receiver mirrors it live. Retained, so a receiver that connects later still
// gets the current value. Driven by the UI MQTT toggle (default ON); host/port
// are editable only while the toggle is OFF. Optional: if no broker is up the
// sketch runs normally (Art-Net is unaffected) — see startMQTT()'s try/catch.
MQTTClient    mqtt;
boolean       mqttReady          = false;
boolean       enableMQTT         = true;          // default on (UI toggle)
String        mqttHost           = "localhost";   // editable when the toggle is OFF
int           mqttPort           = 1883;          // default MQTT port
final String  MQTT_TOPIC_CONFIG  = "ring/config";

// =============================================================
// Lifecycle
// =============================================================

void settings() {
  if (ENABLE_P3D) {
    size(SKETCH_W, SKETCH_H, P3D);
  } else {
    size(SKETCH_W, SKETCH_H);
  }

  // Force logical resolution. Processing 4.5+ defaults to pixelDensity(2) on
  // Retina/high-DPI screens, which renders at 4x the pixels — heavy memory +
  // GPU pressure that aggravates the GStreamer video pipeline and tanks perf.
  // pixelDensity(1) also keeps pixels[] coordinates 1:1 with logical coords.
  //
  // DISABLED 2026-05-29: letting the display default (2 on Retina) render so the
  // canvas looks crisp. sampleColors() is now density-aware (scales reads by
  // pixelDensity), so Art-Net/preview stay correct at any density. RE-ENABLE the
  // line below if the GStreamer freeze or a perf drop returns at density 2.
  // pixelDensity(1);
}

void setup() {
  background(0);

  if (ENABLE_P3D) {
    hint(DISABLE_DEPTH_TEST);
    hint(DISABLE_TEXTURE_MIPMAPS);
  }

  //frameRate(30);   // commented out while debugging the GStreamer video race (old project omits it). Don't delete — restore once stable.

  // Two side-by-side containers from ONE decode: left = clone (x=0),
  // right = main (x=480). Each owns its own RingGrid; the shared MediaHandler
  // places the same frame into each via getDisplayBounds(canvas).
  leftCanvas    = new Canvas(0,        0, CANVAS_W, CANVAS_H);
  rightCanvas   = new Canvas(CANVAS_W, 0, CANVAS_W, CANVAS_H);
  mediaHandler  = new MediaHandler(this, rightCanvas);   // rightCanvas is the 480 sizing/center reference
  leftContainer  = new VideoContainer(leftCanvas,  new RingGrid(leftCanvas),  false, "left");
  rightContainer = new VideoContainer(rightCanvas, new RingGrid(rightCanvas), true,  "right");
  containers     = new VideoContainer[] { leftContainer, rightContainer };
  rightContainer.universe = 0;              // main eye -> universe 0 (default; config may override)
  leftContainer.universe  = 1;              // clone eye -> universe 1
  ringGrid       = rightContainer.ring;     // MAIN alias (see globals)
  colorPipeline = new ColorPipeline();      // before loadConfig + UI

  // Phase 8: restore saved state (ring N + toggles, color, Art-Net target,
  // last video + transform) BEFORE building the UI so the controls initialize
  // to the restored values. Art-Net is NOT auto-started.
  loadConfig();

  ui            = new UserInterface(this, 0, CANVAS_H, SKETCH_W, UI_H);

  // SDrop kept registered (no-op under P3D). Restores drag-drop if P3D is off.
  drop         = new SDrop(this);

  // MQTT connect is driven by the UI MQTT toggle (default ON), which fires
  // startMQTT() as the panel is built — see UserInterface.startMQTT(). Nothing
  // to do here.

  log("[setup] ring_eye_sim_artnet_sender started");
  log("[setup] canvas: " + CANVAS_W + "x" + CANVAS_H + ", pixelDensity=" + pixelDensity);
  // pixelDensity no longer has to be 1 — sampleColors() scales reads by it. A
  // higher density just means a crisper display at more GPU/memory cost.
  if (pixelDensity != 1) {
    log("[setup] pixelDensity=" + pixelDensity + " (high-DPI): display crisp, sampling is density-aware. Drop to pixelDensity(1) in settings() if perf / the GStreamer freeze returns.");
  }
  log("[setup] renderer: " + (ENABLE_P3D ? "P3D (use O for file picker)" : "default Java2D"));
  log("[setup] ring: N=" + ringGrid.N + ", R=" + nf(ringGrid.ringR, 0, 1) + ", cellSize=" + nf(ringGrid.cellSize(), 0, 1));
  log("[setup] keys: O open, SPACE pause/play, arrows move (Shift=10x),");
  log("[setup]       Cmd+UP/DOWN scale, R reset, G grid, L labels, C preview, A artnet, BACKSPACE clear");
  log("[setup]       M color mode, [ / ] brightness -/+5%, S save config");
  log("[setup] state: N=" + ringGrid.N + ", mode=" + colorPipeline.getModeName()
    + ", brightness=" + round(colorPipeline.brightness * 100) + "%, gamma=" + nf(colorPipeline.gamma, 0, 1));
}

void draw() {
  background(0);

  if (ENABLE_P3D) {
    hint(DISABLE_DEPTH_TEST);
  }

  // Frame produced by the PREVIOUS update() (the read is LAST — race fix).
  // Shared by both containers (single decode).
  PImage frame = mediaHandler.getCurrentFrame();

  // 1) Render each container's canvas + the shared frame (+ main marker).
  for (VideoContainer c : containers) {
    c.canvas.render();
    c.render(frame, mediaHandler);
  }

  // P3D zero-image keepalive — ONCE (single decode), after the blits, BEFORE
  // the read. https://github.com/processing/processing-video/issues/207
  if (ENABLE_P3D && mediaHandler.isVideo && mediaHandler.loadedVideo != null) {
    image(mediaHandler.loadedVideo, 0, 0, 0, 0);
  }

  // Throttled Art-Net tick (DMX_SEND_INTERVAL_MS), independent of the draw rate.
  // Senders live per-container (phase 12a); each writeAndSend() no-ops if its
  // sender isn't up, so we only need the enable flag + timer here.
  boolean dmxTick = enableDMX
    && (millis() - lastDmxSendMillis >= DMX_SEND_INTERVAL_MS);

  // 2) Sample BOTH rings BEFORE any overlay (else we'd average our own red
  // cells). One loadPixels() read back feeds both rings. Sample if a preview is
  // on OR we're about to send a DMX frame. (ringGrid = the right/main ring; its
  // previewEnabled mirrors the left's — they're kept in sync.)
  if (frame != null && (ringGrid.previewEnabled || dmxTick)) {
    loadPixels();                       // single framebuffer read back for both
    for (VideoContainer c : containers) c.sampleRing();
  }

  // 3) Overlay + preview discs for both rings, on top of the video.
  for (VideoContainer c : containers) c.drawRing(colorPipeline);

  // 4) Phase 12b: on the tick, each container writes ITS ring and sends on ITS
  // own universe + target IP (set from that eye's column fields). Each zeroes the
  // shared scratch first so a cleared video blanks both rings.
  if (dmxTick) {
    boolean has = (frame != null);
    for (VideoContainer c : containers) c.writeAndSend(dmxData, colorPipeline, has);
    lastDmxSendMillis = millis();
  }

  // 5) Transient adjustment guides on BOTH containers — AFTER sampling + the
  // DMX write so they never touch the sampled colors or the bytes on the wire.
  if (mediaHandler.hasContent() && showAdjustGuides()) {
    for (VideoContainer c : containers) drawAdjustGuides(c.canvas);
  }

  // Thin divider between the two containers (drawn after the canvas content,
  // sits in the gap between the two rings — never sampled).
  stroke(60);
  strokeWeight(1);
  line(CANVAS_W, 0, CANVAS_W, CANVAS_H);
  noStroke();

  // UI panel + FPS. ControlP5 draws its controls on top after draw() returns.
  ui.setFps(frameRate);
  ui.render();

  // Read the NEXT frame LAST (single decode) — narrows the AppSink race.
  mediaHandler.update();
}

// =============================================================
// File loading — picker (P3D path) + drag-and-drop (Java2D path)
// =============================================================

void openFilePicker() {
  selectInput("Select a video file (.mp4 / .mov / .avi / .webm):", "videoFileSelected");
}

void videoFileSelected(File selection) {
  if (selection == null) {
    log("[picker] file selection canceled");
    return;
  }
  String path = selection.getAbsolutePath();
  log("[picker] " + path);
  mediaHandler.loadMedia(path);
}

void dropEvent(DropEvent event) {
  log("[drop] event received: isFile=" + event.isFile()
    + ", isImage=" + event.isImage()
    + ", isURL=" + event.isURL()
    + ", x=" + event.x() + ", y=" + event.y());

  if (!event.isFile()) {
    log("[drop] not a file — ignoring");
    return;
  }

  if (event.y() >= CANVAS_H) {
    log("[drop] dropped outside canvas region — ignoring");
    return;
  }

  String path = event.filePath();
  log("[drop] " + path);
  mediaHandler.loadMedia(path);
}

// =============================================================
// Keys — uses KeyEvent so we can access isMetaDown()/isShiftDown()
// reliably across renderers and operating systems.
// =============================================================

void keyPressed(KeyEvent event) {
  // If a ControlP5 text field has focus, let ControlP5 handle the key (typing,
  // Backspace = delete a char) and do NOT run the global hotkeys — otherwise
  // Backspace while editing the GAMMA/IP/port/etc. field would also clear the
  // video. (ControlP5's key handling and Processing's keyPressed both fire, so
  // we have to bail here.)
  if (ui != null && ui.isTextfieldFocused()) return;

  // ----- non-modifier keys -----
  if (key == ' ') {
    mediaHandler.togglePlayPause();
    return;
  }
  if (key == BACKSPACE || key == DELETE) {
    mediaHandler.clearMedia();
    log("[key] cleared media");
    return;
  }
  if (key == 'o' || key == 'O') {
    openFilePicker();
    return;
  }
  if (key == 'r' || key == 'R') {
    mediaHandler.resetTransform();
    lastAdjustMillis = -100000;     // reset hides the adjustment guides immediately
    return;
  }
  if (key == 'g' || key == 'G') {
    applyGrid(!ringGrid.gridEnabled);     // fan out to both rings
    ui.syncToggles();    // keep UI toggle in sync
    return;
  }
  if (key == 'l' || key == 'L') {
    applyLabels(!ringGrid.labelsEnabled);
    ui.syncToggles();
    return;
  }
  if (key == 'c' || key == 'C') {
    applyPreview(!ringGrid.previewEnabled);
    ui.syncToggles();    // keep the PREVIEW toggle in sync
    return;
  }
  if (key == 'a' || key == 'A') {
    toggleArtNet();
    return;
  }
  if (key == 'm' || key == 'M') {
    colorPipeline.cycleMode();
    log("[color] mode: " + colorPipeline.getModeName());
    ui.syncColorControls();
    return;
  }
  if (key == '[') {
    colorPipeline.setBrightness(colorPipeline.brightness - 0.05);
    log("[color] brightness: " + round(colorPipeline.brightness * 100) + "%");
    ui.syncColorControls();
    return;
  }
  if (key == ']') {
    colorPipeline.setBrightness(colorPipeline.brightness + 0.05);
    log("[color] brightness: " + round(colorPipeline.brightness * 100) + "%");
    ui.syncColorControls();
    return;
  }
  if (key == 's' || key == 'S') {
    saveConfig();          // phase 8 — manual checkpoint (exit() may not fire on a force-kill)
    return;
  }

  // ----- arrow / Cmd+arrow combos -----
  if (key == CODED) {
    int     kc    = event.getKeyCode();
    boolean shift = event.isShiftDown();
    boolean meta  = event.isMetaDown();   // Cmd on macOS

    if (meta && kc == UP) {
      mediaHandler.scaleBy(SCALE_STEP);
    } else if (meta && kc == DOWN) {
      mediaHandler.scaleBy(1.0 / SCALE_STEP);
    } else if (kc == LEFT) {
      mediaHandler.moveX(shift ? -MOVE_STEP_LARGE : -MOVE_STEP_SMALL);
    } else if (kc == RIGHT) {
      mediaHandler.moveX(shift ?  MOVE_STEP_LARGE :  MOVE_STEP_SMALL);
    } else if (kc == UP) {
      mediaHandler.moveY(shift ? -MOVE_STEP_LARGE : -MOVE_STEP_SMALL);
    } else if (kc == DOWN) {
      mediaHandler.moveY(shift ?  MOVE_STEP_LARGE :  MOVE_STEP_SMALL);
    }

    // Any move/scale key shows the transient adjustment guides (lingers briefly).
    if (kc == UP || kc == DOWN || kc == LEFT || kc == RIGHT) {
      lastAdjustMillis = millis();
    }
  }
}

// =============================================================
// Art-Net (phase 6) — toggle send on/off, zero the DMX buffer
// =============================================================

void toggleArtNet() {
  // Funnel the 'A' key through the same start/stop path as the UI toggle so the
  // sender is always (re)built from the current field values (6b), then push the
  // new state into the START/STOP toggle's visual without re-firing it.
  if (enableDMX) {
    ui.stopDMX();
  } else {
    ui.startDMX();
  }
  ui.syncDmxToggle();
}

void resetDMXData() {
  java.util.Arrays.fill(dmxData, (byte) 0);
}

// =============================================================
// Ring fan-out — N + grid/labels/preview are SHARED, so a change applies to
// BOTH containers' rings. The global `ringGrid` (right/main) is the value the
// UI/config read back from; both rings are kept identical through these.
// =============================================================

void applyN(int n) {
  leftContainer.ring.setN(n);
  rightContainer.ring.setN(n);
  publishRingConfig();        // publishes the main (right) ring's N
}

void applyGrid(boolean on) {
  leftContainer.ring.setGrid(on);
  rightContainer.ring.setGrid(on);
}

void applyLabels(boolean on) {
  leftContainer.ring.setLabels(on);
  rightContainer.ring.setLabels(on);
}

void applyPreview(boolean on) {
  leftContainer.ring.setPreview(on);
  rightContainer.ring.setPreview(on);
}

// =============================================================
// MQTT — publish ring layout so the preview receiver mirrors it live.
// Callbacks (clientConnected/connectionLost/messageReceived) are invoked by the
// library ON THE MAIN THREAD via a post-draw() hook, so they're render-safe.
// =============================================================

// Broker URI from the editable host/port (UI fields).
String mqttBrokerURI() {
  return "mqtt://" + mqttHost + ":" + mqttPort;
}

// Fired on every (re)connect. Re-publish the retained config so a fresh broker
// session always has the current value.
void clientConnected() {
  mqttReady = true;
  publishRingConfig();
  logOk("[mqtt] connected -> " + mqttBrokerURI() + " (published " + MQTT_TOPIC_CONFIG + ")");
}

void connectionLost() {
  mqttReady = false;
  logWarn("[mqtt] connection lost (auto-reconnecting)");
}

// Required by the MQTT library's reflective callback lookup even though the
// server only publishes — the client constructor throws if it's absent.
void messageReceived(String topic, byte[] payload) {
  // Parameters are unused; required by MQTTClient.
  // Prevent unused parameter warnings:
  if (topic != null && payload != null) { }
  // no-op — this sketch only publishes, but the method must exist or the MQTTClient constructor throws.
}

// Publish {n, universe, subnet} retained. No-op if MQTT isn't connected, so it's
// safe to call from anywhere N or the Art-Net target changes.
void publishRingConfig() {
  if (mqtt == null || !mqttReady) return;
  JSONObject j = new JSONObject();
  j.setInt("n",        ringGrid.N);
  j.setInt("universe", rightContainer.universe);   // tester mirrors the MAIN/right eye
  j.setInt("subnet",   subnet);
  try {
    mqtt.publish(MQTT_TOPIC_CONFIG, j.toString(), 1, true);   // qos 1, retained
  } catch (Exception e) {
    logWarn("[mqtt] publish failed: " + e.getMessage());
  }
}

// =============================================================
// Transient video-adjustment guides — purely visual, drawn after sampling/DMX
// so they never reach the wire. Shown while moving/scaling, hidden on idle/reset.
// =============================================================

boolean showAdjustGuides() {
  return millis() - lastAdjustMillis < ADJUST_GUIDE_LINGER_MS;
}

void drawAdjustGuides(Canvas c) {
  Rect b = mediaHandler.getDisplayBounds(c);          // video extent on screen
  float vcx = c.x + mediaHandler.videoX;              // video center on screen
  float vcy = c.y + mediaHandler.videoY;

  pushStyle();

  // Video outline (cyan) at the current display bounds.
  noFill();
  stroke(57, 184, 213);
  strokeWeight(1);
  rect(b.x, b.y, b.w, b.h);

  // Center cross at the VIDEO center — same cyan as the outline. Line it up
  // against the red ring crosshair (Grid View) to center the video on the ring.
  stroke(57, 184, 213);
  strokeWeight(1);
  float cl = 14;
  line(vcx - cl, vcy, vcx + cl, vcy);
  line(vcx, vcy - cl, vcx, vcy + cl);

  // x / y / scale readout, stacked just up-left of the cross so it travels with
  // the video center. RIGHT/BOTTOM align anchors the block at the cross and grows
  // it up and to the left.
  fill(57, 184, 213);
  noStroke();
  textAlign(RIGHT, BOTTOM);
  textSize(12);
  float tx = vcx - 8;
  float lh = 15;
  text("scale: " + round(mediaHandler.videoScale * 100) + "%", tx, vcy - 8);
  text("y: " + round(mediaHandler.videoY), tx, vcy - 8 - lh);
  text("x: " + round(mediaHandler.videoX), tx, vcy - 8 - lh * 2);

  popStyle();
}

// =============================================================
// Logging — routes to Processing console AND the UI console (once it exists)
// =============================================================

void log(String message) {
  println(message);
  if (ui != null) {
    ui.printToConsole(message);
  }
}

// Severity variants for the colored console (phase 6c). The Processing console
// only gets a plain prefix; the UI console gets the matching color.
void logOk(String message) {
  println(message);
  if (ui != null) ui.printToConsole(message, ui.cOk);
}

void logWarn(String message) {
  println("[WARN] " + message);
  if (ui != null) ui.printToConsole(message, ui.cWarn);
}

void logErr(String message) {
  println("[ERR] " + message);
  if (ui != null) ui.printToConsole(message, ui.cErr);
}

// =============================================================
// Config persistence (phase 8) — data/config.json
// Saved on exit() AND on the 'S' hotkey (exit() may not fire on a force-kill).
// Loaded in setup() BEFORE the UI is built so the controls show restored values.
// =============================================================

void saveConfig() {
  JSONObject root = new JSONObject();

  JSONObject v = new JSONObject();
  v.setString("lastPath", (mediaHandler != null && mediaHandler.currentPath != null) ? mediaHandler.currentPath : "");
  v.setFloat("x", mediaHandler != null ? mediaHandler.videoX     : 0);
  v.setFloat("y", mediaHandler != null ? mediaHandler.videoY     : 0);
  v.setFloat("scale", mediaHandler != null ? mediaHandler.videoScale : 1.0);
  root.setJSONObject("video", v);

  JSONObject r = new JSONObject();
  r.setInt("n", ringGrid.N);
  r.setBoolean("gridEnabled", ringGrid.gridEnabled);
  r.setBoolean("labelsEnabled", ringGrid.labelsEnabled);
  r.setBoolean("previewEnabled", ringGrid.previewEnabled);
  root.setJSONObject("ring", r);

  // Art-Net target only — NOT the on/off state (never auto-start on launch).
  // Phase 12b: shared transport + nested per-eye {ip, universe}.
  JSONObject a = new JSONObject();
  a.setBoolean("useBroadcast", useBroadcast);
  a.setInt("port", artNetPort);
  a.setInt("subnet", subnet);
  JSONObject ar = new JSONObject();
  ar.setString("ip", rightContainer.targetIP);
  ar.setInt("universe", rightContainer.universe);
  JSONObject al = new JSONObject();
  al.setString("ip", leftContainer.targetIP);
  al.setInt("universe", leftContainer.universe);
  a.setJSONObject("right", ar);
  a.setJSONObject("left", al);
  root.setJSONObject("artnet", a);

  // Per-eye mirror flags (phase 13) — H/V flip per container (UI toggles).
  // Persisted so each eye's orientation survives a relaunch.
  JSONObject ct = new JSONObject();
  JSONObject ctr = new JSONObject();
  ctr.setBoolean("mirrorH", rightContainer.mirrorH);
  ctr.setBoolean("mirrorV", rightContainer.mirrorV);
  JSONObject ctl = new JSONObject();
  ctl.setBoolean("mirrorH", leftContainer.mirrorH);
  ctl.setBoolean("mirrorV", leftContainer.mirrorV);
  ct.setJSONObject("right", ctr);
  ct.setJSONObject("left", ctl);
  root.setJSONObject("containers", ct);

  JSONObject c = new JSONObject();
  c.setInt("mode", colorPipeline.mode);          // 0=RAW, 1=GAMMA, 2=GAMMA+BRIGHT
  c.setFloat("gamma", colorPipeline.gamma);
  c.setFloat("brightness", colorPipeline.brightness);
  root.setJSONObject("color", c);

  // MQTT side-channel — host/port + the enable toggle. Unlike Art-Net (target
  // only, never auto-started), the on/off state IS persisted here: MQTT only
  // publishes the ring layout to a local broker — no hardware is driven — so
  // restoring the last choice on launch is harmless and matches its default-ON.
  JSONObject m = new JSONObject();
  m.setBoolean("enabled", enableMQTT);
  m.setString("host", mqttHost);
  m.setInt("port", mqttPort);
  root.setJSONObject("mqtt", m);

  try {
    saveJSONObject(root, CONFIG_PATH);           // creates data/ if needed
    logOk("[config] saved -> " + CONFIG_PATH);
  }
  catch (Exception e) {
    logErr("[config] save failed: " + e.getMessage());
  }
}

void loadConfig() {
  File f = new File(sketchPath(CONFIG_PATH));
  if (!f.exists()) {
    log("[config] no config.json — using defaults");
    return;
  }

  JSONObject root;
  try {
    root = loadJSONObject(f.getAbsolutePath());
  }
  catch (Exception e) {
    logWarn("[config] couldn't read config.json — using defaults: " + e.getMessage());
    return;
  }
  if (root == null) {
    logWarn("[config] config.json empty/invalid — using defaults");
    return;
  }

  if (root.hasKey("ring")) {
    JSONObject r = root.getJSONObject("ring");
    applyN(r.getInt("n", ringGrid.N));                                // both rings
    applyGrid(r.getBoolean("gridEnabled", ringGrid.gridEnabled));
    applyLabels(r.getBoolean("labelsEnabled", ringGrid.labelsEnabled));
    applyPreview(r.getBoolean("previewEnabled", ringGrid.previewEnabled));
  }

  if (root.hasKey("color")) {
    JSONObject c = root.getJSONObject("color");
    colorPipeline.setMode(c.getInt("mode", colorPipeline.mode));
    colorPipeline.setGamma(c.getFloat("gamma", colorPipeline.gamma));
    colorPipeline.setBrightness(c.getFloat("brightness", colorPipeline.brightness));
  }

  // Art-Net: restore the target config only — leave sending OFF (opt-in via A).
  // Phase 12b: shared transport + nested per-eye {ip, universe}; legacy flat
  // targetIP/universe falls back onto the right (main) eye.
  if (root.hasKey("artnet")) {
    JSONObject a = root.getJSONObject("artnet");
    useBroadcast = a.getBoolean("useBroadcast", useBroadcast);
    artNetPort   = a.getInt("port", artNetPort);
    subnet       = a.getInt("subnet", subnet);
    if (a.hasKey("right")) {
      JSONObject ar = a.getJSONObject("right");
      rightContainer.targetIP = ar.getString("ip", rightContainer.targetIP);
      rightContainer.universe = ar.getInt("universe", rightContainer.universe);
    } else {                                   // legacy flat schema -> right eye
      rightContainer.targetIP = a.getString("targetIP", rightContainer.targetIP);
      rightContainer.universe = a.getInt("universe", rightContainer.universe);
    }
    if (a.hasKey("left")) {
      JSONObject al = a.getJSONObject("left");
      leftContainer.targetIP = al.getString("ip", leftContainer.targetIP);
      leftContainer.universe = al.getInt("universe", leftContainer.universe);
    }
  }

  // Per-eye mirror flags (phase 13). Set the container fields directly — the UI
  // FLIP toggles read these for their initial state when the panel builds next.
  if (root.hasKey("containers")) {
    JSONObject ct = root.getJSONObject("containers");
    if (ct.hasKey("right")) {
      JSONObject ctr = ct.getJSONObject("right");
      rightContainer.mirrorH = ctr.getBoolean("mirrorH", rightContainer.mirrorH);
      rightContainer.mirrorV = ctr.getBoolean("mirrorV", rightContainer.mirrorV);
    }
    if (ct.hasKey("left")) {
      JSONObject ctl = ct.getJSONObject("left");
      leftContainer.mirrorH = ctl.getBoolean("mirrorH", leftContainer.mirrorH);
      leftContainer.mirrorV = ctl.getBoolean("mirrorV", leftContainer.mirrorV);
    }
  }

  // MQTT: restore host/port + the enable toggle. These globals are read when the
  // UI builds (after loadConfig) — the host/port fields show them, and the
  // toggle's initial setValue fires startMQTT/stopMQTT with the restored host.
  if (root.hasKey("mqtt")) {
    JSONObject m = root.getJSONObject("mqtt");
    enableMQTT = m.getBoolean("enabled", enableMQTT);
    mqttHost   = m.getString("host", mqttHost);
    mqttPort   = m.getInt("port", mqttPort);
  }

  // Video: load only if the saved file still exists, then re-apply the saved
  // transform (loadMedia resets it on success, so override AFTER).
  if (root.hasKey("video")) {
    JSONObject v = root.getJSONObject("video");
    String path = v.getString("lastPath", "");
    if (path != null && path.length() > 0) {
      if (new File(path).exists()) {
        mediaHandler.loadMedia(path);
        if (mediaHandler.isVideo) {
          mediaHandler.videoX     = v.getFloat("x", mediaHandler.videoX);
          mediaHandler.videoY     = v.getFloat("y", mediaHandler.videoY);
          mediaHandler.videoScale = v.getFloat("scale", mediaHandler.videoScale);
        }
      } else {
        logWarn("[config] saved video not found, skipping: " + path);
      }
    }
  }

  log("[config] restored from config.json");
}

// =============================================================
// Exit cleanup
// =============================================================

void exit() {
  log("[exit] shutting down");
  saveConfig();                // phase 8 — persist current state before teardown
  // Art-Net blackout — zero + send on BOTH universes, flush, then tear down.
  if (enableDMX) {
    for (VideoContainer c : containers) c.blackout(dmxData);
    delay(100);                 // let the packets flush before tear-down
    for (VideoContainer c : containers) c.stopSender();
  }
  if (mediaHandler != null) mediaHandler.clearMedia();
  super.exit();
}

// =============================================================
// Tiny value-object for display bounds
// =============================================================

class Rect {
  float x, y, w, h;
  Rect(float x, float y, float w, float h) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }
}

