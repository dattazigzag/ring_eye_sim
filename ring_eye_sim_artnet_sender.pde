// =============================================================
// Ring Eye Sim — Art-Net Sender
// Phase 3 (continued): ring grid overlay + P3D switch for performance
// =============================================================
// See contexts/02_build_plan.md for full phase plan.
//
// Phase 3 covers (cumulative since phase 1):
//   - Drag-and-drop video (DISABLED under P3D — see below)
//   - Keyboard-controlled video transform (move/scale/reset)
//   - togglePlayPause via SPACE (uses .play() to resume — loop flag persists)
//   - RingGrid overlay (stroke-only red cells, no fill so video shows through)
//   - G toggle grid, L toggle labels
//   - N hardcoded to 12 (slider lands in phase 4)
//   - frameRate diagnostic every ~2s
//
// Performance note (Phase 3 patch, post-test):
//   Java2D rendering of 1024×1024 video runs at ~8 fps on this machine.
//   P3D (GPU-accelerated) handles it at ~30 fps. So we switch back to P3D
//   and accept the loss of drag-drop, replacing it with a file picker on
//   the 'O' key. See contexts/99_gotchas.md.
//
// Hotkeys (cumulative):
//   O                    open file picker (use this under P3D — drag-drop dead)
//   SPACE                toggle play/pause
//   ←/→                  move video x  ±2 px
//   ↑/↓                  move video y  ±2 px
//   Shift+←/→            move video x  ±20 px
//   Shift+↑/↓            move video y  ±20 px
//   Cmd+↑                scale × 1.05
//   Cmd+↓                scale ÷ 1.05
//   R                    reset transform (centered + fit)
//   G                    toggle ring grid
//   L                    toggle cell labels
//   BACKSPACE            clear loaded video
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
// P3D is needed for acceptable video performance at 1024×1024. The trade-off
// is that SDrop drag-and-drop is broken under P3D in Processing 3.x/4.x — so
// we register a file picker via the 'O' key instead. See contexts/99_gotchas.md.
final boolean ENABLE_P3D = true;

// Transform step sizes
final int   MOVE_STEP_SMALL = 2;
final int   MOVE_STEP_LARGE = 20;
final float SCALE_STEP      = 1.05;  // 5% per press

// =============================================================
// Main objects
// =============================================================

Canvas        canvas;
MediaHandler  mediaHandler;
RingGrid      ringGrid;
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

  // 30 Hz — clean Art-Net send rate later, smooth video playback under P3D
  frameRate(30);

  canvas       = new Canvas(0, 0, CANVAS_W, CANVAS_H);
  mediaHandler = new MediaHandler(this, canvas);
  ringGrid     = new RingGrid(canvas);

  // SDrop registration is kept in the code (harmless under P3D — events never
  // fire, no error) so that flipping ENABLE_P3D off restores drag-drop without
  // a code change. The primary load path under P3D is the 'O' key picker.
  drop         = new SDrop(this);

  log("[setup] ring_eye_sim_artnet_sender started");
  log("[setup] canvas: " + CANVAS_W + "x" + CANVAS_H + ", ui region: " + UI_H + "px below");
  log("[setup] renderer: " + (ENABLE_P3D ? "P3D (drag-drop disabled, use O for file picker)"
                                          : "default Java2D (drag-drop active)"));
  log("[setup] ring: N=" + ringGrid.N + ", R=" + RingGrid.RING_R + ", cellSize=" + nf(ringGrid.cellSize(), 0, 1));
  log("[setup] keys: O open file picker, SPACE pause/play, arrows move (Shift = 10x),");
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

  // Framerate diagnostic — log every ~2 seconds (60 frames at 30 fps target).
  if (frameCount > 0 && frameCount % 60 == 0) {
    log("[perf] frameRate=" + nf(frameRate, 0, 1));
  }

  // UI region — empty for phase 3, just a slightly lighter background
  fill(25);
  noStroke();
  rect(0, CANVAS_H, SKETCH_W, UI_H);

  // Thin divider between canvas and UI
  stroke(60);
  strokeWeight(1);
  line(0, CANVAS_H, SKETCH_W, CANVAS_H);
  noStroke();

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
    return;  // resetTransform() logs its own confirmation
  }
  if (key == 'g' || key == 'G') {
    ringGrid.toggleGrid();
    return;
  }
  if (key == 'l' || key == 'L') {
    ringGrid.toggleLabels();
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
// Logging — still routes to console only; UI textarea in phase 4
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
