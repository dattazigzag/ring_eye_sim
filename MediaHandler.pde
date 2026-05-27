// =============================================================
// MediaHandler — video load, playback, frame access
// =============================================================
// Phase 1 scope: drop a video, it auto-fit-centers in the canvas
// and loops. No transform controls (those come in phase 2).
//
// Future phases will extend this class:
//   - phase 2: videoX, videoY, videoScale + move/scale/reset/toggle methods
//   - phase 8: state restoration from config.json
// =============================================================

class MediaHandler {
  PApplet parent;
  Canvas  canvas;

  Movie   loadedVideo  = null;
  PImage  currentFrame = null;  // points at loadedVideo once a frame is ready

  boolean isVideo = false;

  MediaHandler(PApplet parent, Canvas canvas) {
    this.parent = parent;
    this.canvas = canvas;
  }

  // -------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------

  void loadMedia(String filePath) {
    if (filePath == null || filePath.isEmpty()) {
      log("[media] invalid file path");
      return;
    }

    int dotIdx = filePath.lastIndexOf(".");
    if (dotIdx < 0) {
      log("[media] file has no extension: " + filePath);
      return;
    }

    String ext = filePath.substring(dotIdx).toLowerCase();
    if (ext.equals(".mp4") || ext.equals(".mov") || ext.equals(".avi") || ext.equals(".webm")) {
      loadVideoFile(filePath);
    } else {
      log("[media] unsupported extension: " + ext + " (use mp4/mov/avi/webm)");
    }
  }

  void loadVideoFile(String filePath) {
    // Stop and release any existing video before swapping
    if (loadedVideo != null) {
      loadedVideo.stop();
      loadedVideo = null;
    }
    currentFrame = null;
    isVideo      = false;

    try {
      loadedVideo = new Movie(parent, filePath);
      loadedVideo.loop();
      isVideo = true;
      log("[media] loaded video: " + filePath);
    } catch (Exception e) {
      log("[media] error loading video: " + e.getMessage());
      isVideo     = false;
      loadedVideo = null;
    }
  }

  // -------------------------------------------------------------
  // Per-frame update
  // -------------------------------------------------------------

  void update() {
    if (isVideo && loadedVideo != null && loadedVideo.available()) {
      loadedVideo.read();

      if (ENABLE_P3D) {
        loadedVideo.loadPixels();
      }

      // Movie extends PImage — point currentFrame at it once a frame is ready
      currentFrame = loadedVideo;
    }
  }

  // -------------------------------------------------------------
  // Clear
  // -------------------------------------------------------------

  void clearMedia() {
    if (loadedVideo != null) {
      loadedVideo.stop();
      loadedVideo = null;
    }
    currentFrame = null;
    isVideo      = false;
  }

  // -------------------------------------------------------------
  // Frame access
  // -------------------------------------------------------------

  boolean hasContent() {
    return currentFrame != null;
  }

  PImage getCurrentFrame() {
    return currentFrame;
  }

  // -------------------------------------------------------------
  // Display geometry — phase 1: auto-fit-centered, preserve aspect ratio
  // Phase 2 will replace this with user-controlled position + scale.
  // -------------------------------------------------------------

  Rect getDisplayBounds() {
    if (currentFrame == null) {
      return new Rect(canvas.x, canvas.y, canvas.width, canvas.height);
    }

    float scaleX = (float) canvas.width  / currentFrame.width;
    float scaleY = (float) canvas.height / currentFrame.height;
    float s      = min(scaleX, scaleY);

    float w = currentFrame.width  * s;
    float h = currentFrame.height * s;
    float x = canvas.x + (canvas.width  - w) / 2.0;
    float y = canvas.y + (canvas.height - h) / 2.0;

    return new Rect(x, y, w, h);
  }
}
