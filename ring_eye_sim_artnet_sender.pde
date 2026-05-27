// =============================================================
// Ring Eye Sim — Art-Net Sender
// Phase 1: skeleton + video drag-and-drop
// =============================================================
// See contexts/02_build_plan.md for full phase plan.
// Phase 1 scope:
//   - 1024×1224 sketch (1024×1024 canvas + 200px UI region, UI empty for now)
//   - Drag-and-drop video file into canvas → auto-fit-centered playback
//   - Backspace clears the loaded video
//   - log() routes to Processing console only (UI textarea comes in phase 4)
// =============================================================

// Drop library for file drag-and-drop
import drop.*;

// Video library
import processing.video.*;

// =============================================================
// Constants
// =============================================================

final int CANVAS_W = 1024;
final int CANVAS_H = 1024;
final int UI_H     = 200;
final int SKETCH_W = CANVAS_W;
final int SKETCH_H = CANVAS_H + UI_H;

// Rendering mode.
// IMPORTANT: SDrop drag-and-drop is broken under P3D in Processing 3.x/4.x
// (P3D uses a JOGL GLWindow which doesn't expose AWT drag-and-drop).
// Keep this false so dropEvent() actually fires. If we ever need P3D for
// performance reasons we'll have to add a GUI file picker fallback.
// Ref: https://forum.processing.org/two/discussion/17092/
final boolean ENABLE_P3D = false;

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
  log("[setup] BACKSPACE clears the loaded video");
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

  // Draw the current video frame at its display bounds
  if (mediaHandler.hasContent()) {
    PImage frame = mediaHandler.getCurrentFrame();
    if (frame != null) {
      Rect b = mediaHandler.getDisplayBounds();
      image(frame, b.x, b.y, b.w, b.h);
    }
  }

  // UI region — empty for phase 1, just a slightly lighter background
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
  // If this line never prints, SDrop is not delivering events (renderer/registration issue).
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
// Keys (phase 1: only BACKSPACE)
// =============================================================

void keyPressed() {
  if (key == BACKSPACE || key == DELETE) {
    mediaHandler.clearMedia();
    log("[key] cleared media");
  }
}

// =============================================================
// Logging — phase 1 routes to console only; phase 4 will also write to UI
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
