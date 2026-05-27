// =============================================================
// Ring Eye Sim — Art-Net Sender
// Phase 2: video transform via keyboard
// =============================================================
// See contexts/02_build_plan.md for full phase plan.
//
// Phase 2 scope:
//   - SPACE              toggle play/pause (resume via .loop(), not .play())
//   - ←/→                move video x  ±2 px
//   - ↑/↓                move video y  ±2 px
//   - Shift+←/→          move video x  ±20 px
//   - Shift+↑/↓          move video y  ±20 px
//   - Cmd+↑              scale × 1.05
//   - Cmd+↓              scale ÷ 1.05
//   - R                  reset transform (centered + fit-to-canvas)
//   - BACKSPACE          clear loaded video (from phase 1)
//
// Uses void keyPressed(KeyEvent event) so we can access isMetaDown() /
// isShiftDown() reliably across renderers.
// =============================================================

// Drop library for file drag-and-drop
import drop.*;

// Video library
import processing.video.*;

// Processing's KeyEvent (NOT java.awt.event.KeyEvent — different class)
import processing.event.KeyEvent;

// =============================================================
// Constants
// =============================================================

final int CANVAS_W = 1024;
final int CANVAS_H = 1024;
final int UI_H     = 200;
final int SKETCH_W = CANVAS_W;
final int SKETCH_H = CANVAS_H + UI_H;

// Rendering mode.
// IMPORTANT: SDrop drag-and-drop is broken under P3D in Processing 3.x/4.x.
// See contexts/99_gotchas.md.
final boolean ENABLE_P3D = false;

// Transform step sizes
final int   MOVE_STEP_SMALL = 2;
final int   MOVE_STEP_LARGE = 20;
final float SCALE_STEP      = 1.05;  // 5% per press

// =============================================================
// Main objects
// =============================================================

Canvas        canvas;
MediaHandler  mediaHandler;
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
}

void setup() {
  background(0);

  if (ENABLE_P3D) {
    hint(DISABLE_DEPTH_TEST);
    hint(DISABLE_TEXTURE_MIPMAPS);
  }

  // 30 Hz — clean Art-Net send rate later, smooth-enough video playback now
  frameRate(30);

  canvas       = new Canvas(0, 0, CANVAS_W, CANVAS_H);
  mediaHandler = new MediaHandler(this, canvas);
  drop         = new SDrop(this);

  log("[setup] ring_eye_sim_artnet_sender started");
  log("[setup] canvas: " + CANVAS_W + "x" + CANVAS_H + ", ui region: " + UI_H + "px below");
  log("[setup] renderer: " + (ENABLE_P3D ? "P3D" : "default (Java2D)"));
  log("[setup] drag a video (.mp4 / .mov / .avi / .webm) onto the canvas to begin");
  log("[setup] keys: SPACE pause/play, arrows move (Shift = 10x), Cmd+UP/DOWN scale,");
  log("[setup]       R reset transform, BACKSPACE clears video");
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

  // UI region — empty for phase 2, just a slightly lighter background
  fill(25);
  noStroke();
  rect(0, CANVAS_H, SKETCH_W, UI_H);

  // Thin divider between canvas and UI
  stroke(60);
  strokeWeight(1);
  line(0, CANVAS_H, SKETCH_W, CANVAS_H);
  noStroke();

  // P3D zero-image trick — only relevant if/when ENABLE_P3D is re-enabled.
  // See: https://github.com/processing/processing-video/issues/207
  if (ENABLE_P3D && mediaHandler.isVideo && mediaHandler.loadedVideo != null) {
    image(mediaHandler.loadedVideo, 0, 0, 0, 0);
  }
}

// =============================================================
// Drag-and-drop
// =============================================================

void dropEvent(DropEvent event) {
  // Unconditional log so we can verify dropEvent actually fires.
  log("[drop] event received: isFile=" + event.isFile()
        + ", isImage=" + event.isImage()
        + ", isURL=" + event.isURL()
        + ", x=" + event.x() + ", y=" + event.y());

  if (!event.isFile()) {
    log("[drop] not a file — ignoring");
    return;
  }

  // Only accept drops inside the canvas region (top 1024px)
  if (event.y() >= CANVAS_H) {
    log("[drop] dropped outside canvas region — ignoring");
    return;
  }

  String path = event.filePath();
  log("[drop] " + path);
  mediaHandler.loadMedia(path);
}

// =============================================================
// Keys (phase 2) — uses KeyEvent so we can access isMetaDown()/isShiftDown()
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
  if (key == 'r' || key == 'R') {
    mediaHandler.resetTransform();
    return;  // resetTransform() logs its own confirmation
  }

  // ----- arrow / Cmd+arrow combos -----
  // Processing's `key == CODED` indicates a non-printable key. Arrows are
  // always coded in normal operation. We still use the event for modifiers
  // (more reliable than the global `keyCode` per Processing's own docs).
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
// Logging — phase 2 still routes to console only; UI textarea in phase 4
// =============================================================

void log(String message) {
  println(message);
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
    this.x = x; this.y = y; this.w = w; this.h = h;
  }
}
