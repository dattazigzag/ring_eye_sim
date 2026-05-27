// =============================================================
// MediaHandler — video load, playback, transform, frame access
// =============================================================
// Phase 1: drop loads video, auto-fit-centered playback, BACKSPACE clears.
// Phase 2 (this version): user-controlled transform via keyboard
//   - videoX, videoY (center of display in canvas coords)
//   - videoScale (multiplier on top of fit-to-canvas baseline)
//   - moveX / moveY / scaleBy / resetTransform
//   - togglePlayPause uses .loop() on resume (per user requirement:
//     video always loops unless paused)
//
// Future phases:
//   - phase 8: state restoration from config.json
// =============================================================

class MediaHandler {
  PApplet parent;
  Canvas  canvas;

  Movie   loadedVideo  = null;
  PImage  currentFrame = null;  // points at loadedVideo once a frame is ready

  boolean isVideo = false;

  // ---- transform state (phase 2) ----
  // videoX, videoY = center of the displayed video, in canvas-local coords
  // videoScale     = multiplier on top of fit-to-canvas baseline (1.0 = fit)
  float videoX, videoY, videoScale;

  // Scale clamp (keep video visible but not absurd)
  static final float MIN_SCALE = 0.05;
  static final float MAX_SCALE = 10.0;

  MediaHandler(PApplet parent, Canvas canvas) {
    this.parent = parent;
    this.canvas = canvas;
    resetTransform();
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
      loadedVideo.loop();          // always loop on load
      isVideo = true;
      resetTransform();             // each new video lands centered + fit
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
  // Playback control (phase 2)
  // -------------------------------------------------------------

  void togglePlayPause() {
    if (loadedVideo == null) {
      log("[media] no video loaded");
      return;
    }
    if (loadedVideo.isPlaying()) {
      loadedVideo.pause();
      log("[media] paused");
    } else {
      // Resume with .loop() (NOT .play()) — Processing's .play() would
      // play once to end and stop, breaking the always-loop semantics.
      loadedVideo.loop();
      log("[media] resumed (looping)");
    }
  }

  // -------------------------------------------------------------
  // Transform control (phase 2)
  // -------------------------------------------------------------

  void resetTransform() {
    videoX     = canvas.width  / 2.0;
    videoY     = canvas.height / 2.0;
    videoScale = 1.0;
    log("[media] transform reset (center + fit)");
  }

  void moveX(int delta) {
    videoX += delta;
  }

  void moveY(int delta) {
    videoY += delta;
  }

  void scaleBy(float factor) {
    videoScale = constrain(videoScale * factor, MIN_SCALE, MAX_SCALE);
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
  // Display geometry — honors transform state set by keyboard.
  //   baseScale = fit-to-canvas (preserve aspect ratio)
  //   finalScale = baseScale * videoScale
  //   center anchor at (videoX, videoY) in canvas-local coords
  // -------------------------------------------------------------

  Rect getDisplayBounds() {
    if (currentFrame == null) {
      return new Rect(canvas.x, canvas.y, canvas.width, canvas.height);
    }

    float scaleX    = (float) canvas.width  / currentFrame.width;
    float scaleY    = (float) canvas.height / currentFrame.height;
    float baseScale = min(scaleX, scaleY);
    float s         = baseScale * videoScale;

    float w = currentFrame.width  * s;
    float h = currentFrame.height * s;
    float x = canvas.x + videoX - w / 2.0;
    float y = canvas.y + videoY - h / 2.0;

    return new Rect(x, y, w, h);
  }
}
