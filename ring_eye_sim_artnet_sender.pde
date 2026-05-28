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
final int UI_H     = 300;   // panel taller than the video so the color controls + console fit (video area unchanged)
final int SKETCH_W = CANVAS_W;
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

Canvas        canvas;
MediaHandler  mediaHandler;
RingGrid      ringGrid;
ColorPipeline colorPipeline;       // phase 7 — gamma/brightness applied to preview + DMX
UserInterface ui;
SDrop         drop;
DMXSender     dmxSender;            // created lazily on first Art-Net enable

// =============================================================
// Art-Net config (phase 6) — defaults from project brief; UI fields in 6b
// =============================================================

byte[]  dmxData      = new byte[512];      // one DMX universe, zeroed each send
boolean enableDMX    = false;              // toggled with 'A'
boolean useBroadcast = true;               // broadcast vs unicast
String  targetIP     = "255.255.255.255";          // broadcast address
int     artNetPort   = 6454;               // standard Art-Net port
int     universe     = 0;
int     subnet       = 0;

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
// gets the current value. Optional: if no broker is up the sketch runs normally
// (Art-Net is unaffected); see the connect() try/catch in setup().
MQTTClient    mqtt;
boolean       mqttReady          = false;
final String  MQTT_BROKER        = "mqtt://localhost:1883";
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

  canvas        = new Canvas(0, 0, CANVAS_W, CANVAS_H);
  mediaHandler  = new MediaHandler(this, canvas);
  ringGrid      = new RingGrid(canvas);
  colorPipeline = new ColorPipeline();      // before loadConfig + UI

  // Phase 8: restore saved state (ring N + toggles, color, Art-Net target,
  // last video + transform) BEFORE building the UI so the controls initialize
  // to the restored values. Art-Net is NOT auto-started.
  loadConfig();

  ui            = new UserInterface(this, 0, CANVAS_H, SKETCH_W, UI_H);

  // SDrop kept registered (no-op under P3D). Restores drag-drop if P3D is off.
  drop         = new SDrop(this);

  // MQTT side-channel (optional). connect() blocks ~2 s then throws if no broker
  // is reachable, so it's wrapped: Art-Net keeps working regardless. The retained
  // config is (re)published from clientConnected(), which also fires on reconnect.
  try {
    mqtt = new MQTTClient(this);
    mqtt.connect(MQTT_BROKER, "ring_eye_sim_server");
  } catch (Exception e) {
    logWarn("[mqtt] no broker at " + MQTT_BROKER + " — receiver won't auto-sync. Start mosquitto and relaunch. (Art-Net is unaffected.)");
  }

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

  // Canvas region
  canvas.render();

  // Draw the current video frame (produced by the PREVIOUS frame's update()).
  if (mediaHandler.hasContent()) {
    PImage frame = mediaHandler.getCurrentFrame();
    if (frame != null) {
      Rect b = mediaHandler.getDisplayBounds();
      image(frame, b.x, b.y, b.w, b.h);
    }
  }

  // P3D zero-image trick — keeps the video pipeline alive under P3D renderer.
  // Done right after display, BEFORE the read — matching the old project's
  // renderCanvasContent() order. See: https://github.com/processing/processing-video/issues/207
  if (ENABLE_P3D && mediaHandler.isVideo && mediaHandler.loadedVideo != null) {
    image(mediaHandler.loadedVideo, 0, 0, 0, 0);
  }

  // Phase 6: is it time to push an Art-Net frame? Throttled on its own timer
  // (DMX_SEND_INTERVAL_MS), independent of the uncapped draw rate.
  boolean dmxTick = enableDMX && dmxSender != null
    && (millis() - lastDmxSendMillis >= DMX_SEND_INTERVAL_MS);

  // Phase 5/6: sample the video colors under each cell BEFORE the overlay is
  // drawn (otherwise we'd average our own red cell strokes). Sample if the
  // preview is on OR we're about to send a DMX frame.
  if (mediaHandler.hasContent() && (ringGrid.previewEnabled || dmxTick)) {
    ringGrid.sampleColors();
  }

  // Ring grid overlay — drawn ON TOP of the video, INSIDE the canvas region
  ringGrid.drawOverlay();

  // Phase 5: preview discs of the sampled colors (toggle 'C'), on top of overlay.
  // Phase 7: discs are run through the color pipeline so they match the ring (WYSIWYG).
  ringGrid.drawPreview(colorPipeline);

  // Phase 6: push one Art-Net frame on the throttle tick. Zero the buffer first
  // so a cleared video (no content) blanks the ring instead of holding stale.
  if (dmxTick) {
    resetDMXData();
    if (mediaHandler.hasContent()) ringGrid.writeToDMXBuffer(dmxData, colorPipeline);
    dmxSender.sendDMXData(dmxData);
    lastDmxSendMillis = millis();
  }

  // Transient adjustment guides — drawn AFTER sampling + the DMX write so they
  // never affect the sampled cell colors or the bytes on the wire. Auto-hidden
  // a short while after the last move/scale (and immediately on reset).
  if (mediaHandler.hasContent() && showAdjustGuides()) {
    drawAdjustGuides();
  }

  // UI panel background + divider + FPS readout. ControlP5 draws its controls
  // on top automatically after draw() returns.
  ui.setFps(frameRate);
  ui.render();

  // Read the NEXT video frame LAST — matches the old humanoid_face_twin project,
  // which calls update (the read) at the very end of draw(). Decouples frame
  // delivery from the texture upload above, narrowing the AppSink race window.
  // Costs one frame of display latency, which is imperceptible.
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
    ringGrid.toggleGrid();
    ui.syncToggles();    // keep UI toggle in sync
    return;
  }
  if (key == 'l' || key == 'L') {
    ringGrid.toggleLabels();
    ui.syncToggles();
    return;
  }
  if (key == 'c' || key == 'C') {
    ringGrid.togglePreview();
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
// MQTT — publish ring layout so the preview receiver mirrors it live.
// Callbacks (clientConnected/connectionLost/messageReceived) are invoked by the
// library ON THE MAIN THREAD via a post-draw() hook, so they're render-safe.
// =============================================================

// Fired on every (re)connect. Re-publish the retained config so a fresh broker
// session always has the current value.
void clientConnected() {
  mqttReady = true;
  publishRingConfig();
  logOk("[mqtt] connected -> " + MQTT_BROKER + " (published " + MQTT_TOPIC_CONFIG + ")");
}

void connectionLost() {
  mqttReady = false;
  logWarn("[mqtt] connection lost (auto-reconnecting)");
}

// Required by the MQTT library's reflective callback lookup even though the
// server only publishes — the client constructor throws if it's absent.
void messageReceived(String topic, byte[] payload) {
  // no-op — this sketch only publishes, but the method must exist or the MQTTClient constructor throws.
}

// Publish {n, universe, subnet} retained. No-op if MQTT isn't connected, so it's
// safe to call from anywhere N or the Art-Net target changes.
void publishRingConfig() {
  if (mqtt == null || !mqttReady) return;
  JSONObject j = new JSONObject();
  j.setInt("n",        ringGrid.N);
  j.setInt("universe", universe);
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

void drawAdjustGuides() {
  Rect b = mediaHandler.getDisplayBounds();           // video extent on screen
  float vcx = canvas.x + mediaHandler.videoX;         // video center on screen
  float vcy = canvas.y + mediaHandler.videoY;

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
  JSONObject a = new JSONObject();
  a.setBoolean("useBroadcast", useBroadcast);
  a.setString("targetIP", targetIP);
  a.setInt("port", artNetPort);
  a.setInt("universe", universe);
  a.setInt("subnet", subnet);
  root.setJSONObject("artnet", a);

  JSONObject c = new JSONObject();
  c.setInt("mode", colorPipeline.mode);          // 0=RAW, 1=GAMMA, 2=GAMMA+BRIGHT
  c.setFloat("gamma", colorPipeline.gamma);
  c.setFloat("brightness", colorPipeline.brightness);
  root.setJSONObject("color", c);

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
    ringGrid.setN(r.getInt("n", ringGrid.N));
    ringGrid.setGrid(r.getBoolean("gridEnabled", ringGrid.gridEnabled));
    ringGrid.setLabels(r.getBoolean("labelsEnabled", ringGrid.labelsEnabled));
    ringGrid.setPreview(r.getBoolean("previewEnabled", ringGrid.previewEnabled));
  }

  if (root.hasKey("color")) {
    JSONObject c = root.getJSONObject("color");
    colorPipeline.setMode(c.getInt("mode", colorPipeline.mode));
    colorPipeline.setGamma(c.getFloat("gamma", colorPipeline.gamma));
    colorPipeline.setBrightness(c.getFloat("brightness", colorPipeline.brightness));
  }

  // Art-Net: restore the target config only — leave sending OFF (opt-in via A).
  if (root.hasKey("artnet")) {
    JSONObject a = root.getJSONObject("artnet");
    useBroadcast = a.getBoolean("useBroadcast", useBroadcast);
    targetIP     = a.getString("targetIP", targetIP);
    artNetPort   = a.getInt("port", artNetPort);
    universe     = a.getInt("universe", universe);
    subnet       = a.getInt("subnet", subnet);
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
  // Art-Net blackout — zero all channels and send once so the ring goes dark.
  if (enableDMX && dmxSender != null) {
    resetDMXData();
    dmxSender.sendDMXData(dmxData);
    delay(100);                 // let the packet flush before tear-down
    dmxSender.stop();
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

