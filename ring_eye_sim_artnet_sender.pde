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
//   BACKSPACE            clear loaded video
// =============================================================

// Drop library for file drag-and-drop
import drop.*;

// Video library
import processing.video.*;

// ControlP5 UI
import controlP5.*;

// Processing's KeyEvent (NOT java.awt.event.KeyEvent — different class)
import processing.event.KeyEvent;

// =============================================================
// Constants
// =============================================================

final int CANVAS_W = 480;
final int CANVAS_H = 480;
final int UI_H     = 240;   // taller than the 480 width so the console can stack below the controls
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

// =============================================================
// Main objects
// =============================================================

Canvas        canvas;
MediaHandler  mediaHandler;
RingGrid      ringGrid;
UserInterface ui;
SDrop         drop;

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
  // pixelDensity(1) also keeps pixels[] coordinates 1:1 with logical coords,
  // which Phase 5 (sampling) depends on. See contexts/99_gotchas.md.
  pixelDensity(1);
}

void setup() {
  background(0);

  if (ENABLE_P3D) {
    hint(DISABLE_DEPTH_TEST);
    hint(DISABLE_TEXTURE_MIPMAPS);
  }

  frameRate(30);

  canvas       = new Canvas(0, 0, CANVAS_W, CANVAS_H);
  mediaHandler = new MediaHandler(this, canvas);
  ringGrid     = new RingGrid(canvas);
  ui           = new UserInterface(this, 0, CANVAS_H, SKETCH_W, UI_H);

  // SDrop kept registered (no-op under P3D). Restores drag-drop if P3D is off.
  drop         = new SDrop(this);

  log("[setup] ring_eye_sim_artnet_sender started");
  log("[setup] canvas: " + CANVAS_W + "x" + CANVAS_H + ", pixelDensity=" + pixelDensity);
  log("[setup] renderer: " + (ENABLE_P3D ? "P3D (use O for file picker)" : "default Java2D"));
  log("[setup] ring: N=" + ringGrid.N + ", R=" + nf(ringGrid.ringR, 0, 1) + ", cellSize=" + nf(ringGrid.cellSize(), 0, 1));
  log("[setup] keys: O open, SPACE pause/play, arrows move (Shift=10x),");
  log("[setup]       Cmd+UP/DOWN scale, R reset, G grid, L labels, BACKSPACE clear");
}

void draw() {
  background(0);

  if (ENABLE_P3D) {
    hint(DISABLE_DEPTH_TEST);
  }

  // Canvas region
  canvas.render();

  // Poll for a new video frame
  mediaHandler.update();

  // Draw the current video frame at its display bounds (honoring transform)
  if (mediaHandler.hasContent()) {
    PImage frame = mediaHandler.getCurrentFrame();
    if (frame != null) {
      Rect b = mediaHandler.getDisplayBounds();
      image(frame, b.x, b.y, b.w, b.h);
    }
  }

  // Ring grid overlay — drawn ON TOP of the video, INSIDE the canvas region
  ringGrid.drawOverlay();

  // UI panel background + divider + FPS readout. ControlP5 draws its controls
  // on top automatically after draw() returns.
  ui.setFps(frameRate);
  ui.render();

  // P3D zero-image trick — keeps the video pipeline alive under P3D renderer.
  // See: https://github.com/processing/processing-video/issues/207
  if (ENABLE_P3D && mediaHandler.isVideo && mediaHandler.loadedVideo != null) {
    image(mediaHandler.loadedVideo, 0, 0, 0, 0);
  }
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
  }
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

// =============================================================
// Exit cleanup
// =============================================================

void exit() {
  log("[exit] shutting down");
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
