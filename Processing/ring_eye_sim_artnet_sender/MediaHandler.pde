// =============================================================
// MediaHandler — video load, playback, transform, frame access
// =============================================================
// Phase 1: drop loads video, auto-fit-centered playback, BACKSPACE clears.
// Phase 2: user-controlled transform via keyboard
//   - videoX, videoY (center of display in canvas coords)
//   - videoScale (multiplier on top of fit-to-canvas baseline)
//   - togglePlayPause uses .play() on resume — loop flag set by initial
//     .loop() persists across pause/play cycles.
// Phase 3 perf patch + race fix (this version): each new Movie frame is
//   detached immediately via read() -> loadPixels() -> System.arraycopy into a
//   native-size `loadedImage`, then resized off THAT detached copy into a
//   canvas-fit `processedImage`. We never call copy() on the live Movie —
//   doing so kept the Movie's GPU texture/buffer path active and raced with
//   the GStreamer AppSink callback (LinkedList NPE in Texture.bufferUpdate,
//   plus the "disposed" warnings). The read() is also called LAST in draw(),
//   after the zero-image trick. Both mirror the known-stable
//   humanoid_face_twin/Processing/ArtNetSender project on this machine.
//
// Watchdog patch (this version): if the GStreamer AppSink stops delivering
//   frames (the "Native object has been disposed" freeze), auto-reload the
//   same file. Masks the upstream race; see contexts/99_gotchas.md.
//
// Future phases:
//   - phase 5: sample from processedImage in sampleColors()
//   - phase 8: state restoration from config.json
// =============================================================

class MediaHandler {
  PApplet parent;
  Canvas  canvas;

  Movie   loadedVideo    = null;
  PImage  loadedImage    = null;   // detached native-size copy of the latest Movie frame
  PImage  processedImage = null;   // loadedImage resized to canvas-fit size (CPU-side)
  PImage  currentFrame   = null;   // -> processedImage once a frame is ready

  boolean isVideo = false;

  // ---- transform state (phase 2) ----
  // videoX, videoY = center of the displayed video, in canvas-local coords
  // videoScale     = multiplier on top of fit-to-canvas baseline (1.0 = fit)
  float videoX, videoY, videoScale;

  // Scale clamp (keep video visible but not absurd)
  static final float MIN_SCALE = 0.05;
  static final float MAX_SCALE = 10.0;

  // ---- watchdog (auto-recover from the GStreamer AppSink freeze) ----
  // When the AppSink wedges, available() stops returning true so no new frame
  // arrives. We track the time of the last successful read(); if the video
  // should be playing but no frame has landed for WATCHDOG_TIMEOUT_MS, tear
  // down and reload the same file. shouldBePlaying gates this so a user pause
  // (legitimately no frames) never triggers a reload.
  static final int WATCHDOG_TIMEOUT_MS  = 3000;  // no-frame stall before reload
  static final int WATCHDOG_MAX_RELOADS = 5;     // consecutive reloads before giving up
  String  currentPath        = null;             // last loaded file (for reload)
  int     lastFrameMillis    = 0;                // millis() of last successful read()
  boolean shouldBePlaying    = false;            // playback intent — gates the watchdog
  int     consecutiveReloads = 0;                // reset to 0 on any successful frame

  // ---- screen-capture source (Extension A) — alternative to video ----
  // The lens + Robot live in ScreenGrabber; MediaHandler drives a throttled
  // grab() into the SAME pipeline (loadedImage -> updateProcessedImage ->
  // currentFrame), so the two containers / sampler / DMX stay unchanged. A raw
  // grab is fed (the ring sampler does the per-cell reduction). Mutually
  // exclusive with video. Session-only (never restored on launch).
  ScreenGrabber grabber;
  boolean       isScreen = false;
  static final int SCREEN_GRAB_INTERVAL_MS = 33;   // ~30 Hz (matches the DMX tick)
  int           lastScreenGrabMillis = 0;

  MediaHandler(PApplet parent, Canvas canvas) {
    this.parent = parent;
    this.canvas = canvas;
    grabber     = new ScreenGrabber(parent);   // Extension A — lens shown on demand
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
    loadedImage    = null;
    processedImage = null;
    currentFrame   = null;
    isVideo        = false;

    try {
      loadedVideo = new Movie(parent, filePath);
      // .loop() sets the internal loop flag AND starts playback. The loop
      // flag persists across subsequent pause()/play() cycles, so we never
      // have to call loop() again — play() on resume is enough.
      loadedVideo.loop();
      isVideo = true;
      currentPath        = filePath;   // remember for watchdog reload
      shouldBePlaying    = true;
      lastFrameMillis    = millis();   // start the stall timer fresh
      consecutiveReloads = 0;
      resetTransform();             // each new video lands centered + fit
      log("[media] loaded video: " + filePath);
    }
    catch (Exception e) {
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
      if (ENABLE_P3D) loadedVideo.loadPixels();   // mirror old project under P3D
      updateVideoFrame();                          // detach the frame, then resize the copy
      currentFrame       = processedImage;
      lastFrameMillis    = millis();   // watchdog: a frame landed
      consecutiveReloads = 0;          // pipeline is healthy again
    } else if (isScreen) {
      // Throttled desktop grab -> same resize pipeline as video. The grab is a
      // RAW frame (the ring sampler does the per-cell reduction). No watchdog /
      // zero-image keepalive needed — those are video/GStreamer-only (gated on
      // isVideo). The grabber reuses its output PImage; we consume it at once.
      if (millis() - lastScreenGrabMillis >= SCREEN_GRAB_INTERVAL_MS) {
        PImage g = grabber.grab();
        if (g != null) {
          loadedImage  = g;             // feed the grab as the detached source
          updateProcessedImage();       // resize to canvas-fit -> processedImage
          currentFrame = processedImage;
        }
        lastScreenGrabMillis = millis();
      }
    }
    checkWatchdog();
  }

  // -------------------------------------------------------------
  // Watchdog — detect the GStreamer freeze and reload the file.
  // -------------------------------------------------------------

  void checkWatchdog() {
    if (!isVideo || !shouldBePlaying || loadedVideo == null || currentPath == null) return;
    if (millis() - lastFrameMillis <= WATCHDOG_TIMEOUT_MS) return;

    if (consecutiveReloads >= WATCHDOG_MAX_RELOADS) {
      log("[watchdog] " + WATCHDOG_MAX_RELOADS + " reloads without recovery — giving up. Reload manually with O.");
      shouldBePlaying = false;   // stop hammering reload
      return;
    }
    reloadCurrentVideo();
  }

  // Tear down the (likely wedged) Movie and reload the same file. Transform
  // state is preserved; playback restarts from the start via a fresh loop()
  // rather than a jump() — an explicit seek is what triggers the
  // gst_segment_clip assertion. processedImage/currentFrame are kept so the
  // canvas keeps showing the last good frame until new frames arrive.
  void reloadCurrentVideo() {
    consecutiveReloads++;
    log("[watchdog] no frame for >" + WATCHDOG_TIMEOUT_MS + "ms — reloading ("
      + consecutiveReloads + "/" + WATCHDOG_MAX_RELOADS + "): " + currentPath);

    Movie old = loadedVideo;
    loadedVideo = null;
    if (old != null) {
      try {
        old.stop();
      }
      catch (Exception e) { /* native may already be disposed */
      }
    }

    try {
      loadedVideo = new Movie(parent, currentPath);
      loadedVideo.loop();
      isVideo         = true;
      shouldBePlaying = true;
      lastFrameMillis = millis();      // restart the stall timer
    }
    catch (Exception e) {
      log("[watchdog] reload failed: " + e.getMessage());
      isVideo     = false;
      loadedVideo = null;
    }
  }

  // Detach the just-read Movie frame into a native-size PImage, then resize
  // that detached copy. Old humanoid_face_twin pattern: arraycopy the live
  // Movie's pixels[] out ONCE, synchronously, right after read(); everything
  // downstream works off loadedImage, so the live Movie is never handed to
  // copy()/resize on the render thread (which raced the GStreamer AppSink
  // callback and crashed in Texture.bufferUpdate).
  void updateVideoFrame() {
    if (loadedVideo == null || loadedVideo.width <= 0 || loadedVideo.height <= 0) return;

    // (Re)create the detached buffer only when the native dims change.
    if (loadedImage == null
      || loadedImage.width  != loadedVideo.width
      || loadedImage.height != loadedVideo.height) {
      loadedImage = createImage(loadedVideo.width, loadedVideo.height, RGB);
    }

    loadedVideo.loadPixels();
    loadedImage.loadPixels();
    if (loadedVideo.pixels.length == loadedImage.pixels.length) {
      System.arraycopy(loadedVideo.pixels, 0, loadedImage.pixels, 0, loadedVideo.pixels.length);
    } else {
      int minLength = min(loadedVideo.pixels.length, loadedImage.pixels.length);
      for (int i = 0; i < minLength; i++) loadedImage.pixels[i] = loadedVideo.pixels[i];
    }
    loadedImage.updatePixels();

    updateProcessedImage();
  }

  // Resize the DETACHED loadedImage into processedImage at canvas-fit size.
  // Source is loadedImage (a plain PImage), never the live Movie. The buffer
  // is reused across frames; only re-created when the source dims change.
  void updateProcessedImage() {
    if (loadedImage == null || loadedImage.width <= 0 || loadedImage.height <= 0) return;

    // Calculate the canvas-fit target size (preserve aspect ratio)
    float scaleX   = (float) canvas.width  / loadedImage.width;
    float scaleY   = (float) canvas.height / loadedImage.height;
    float fitScale = min(scaleX, scaleY);

    int targetW = max(1, (int)(loadedImage.width  * fitScale));
    int targetH = max(1, (int)(loadedImage.height * fitScale));

    // (Re)create the buffer only when the target dimensions change
    if (processedImage == null
      || processedImage.width  != targetW
      || processedImage.height != targetH) {
      processedImage = createImage(targetW, targetH, RGB);
      log("[media] processedImage buffer: " + targetW + "x" + targetH
        + " (source " + loadedImage.width + "x" + loadedImage.height + ")");
    }

    // Resize-copy from the detached copy to the canvas-fit target. PImage.copy()
    // with different src/dst sizes performs a bilinear resize internally.
    processedImage.copy(loadedImage,
      0, 0, loadedImage.width, loadedImage.height,
      0, 0, targetW, targetH);
  }

  // -------------------------------------------------------------
  // Playback control (phase 2)
  // -------------------------------------------------------------

  void togglePlayPause() {
    if (loadedVideo == null) {
      log("[media] toggle: no video loaded");
      return;
    }
    boolean playingNow = loadedVideo.isPlaying();
    log("[media] toggle: isPlaying=" + playingNow);
    if (playingNow) {
      loadedVideo.pause();
      shouldBePlaying = false;     // user pause — watchdog stands down
      log("[media] -> paused");
    } else {
      // Processing's Movie.pause() reference:
      //   "If a movie is started again with play(), it will continue from
      //    where it was paused."
      // The internal loop flag set by loadVideoFile()'s .loop() persists,
      // so play() resumes AND the video keeps looping at end-of-video.
      loadedVideo.play();
      shouldBePlaying = true;
      lastFrameMillis = millis();  // don't let the paused gap trip the watchdog
      log("[media] -> resumed");
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
  // Screen-capture source (Extension A) — start/stop. Mutually exclusive with
  // video: starting screen tears down any video first; the lens window is
  // shown/disposed by the ScreenGrabber. update() then feeds throttled grabs
  // through the same resize pipeline as video.
  // -------------------------------------------------------------

  void startScreenCapture() {
    // Tear down any video first — one input at a time.
    if (loadedVideo != null) { loadedVideo.stop(); loadedVideo = null; }
    isVideo            = false;
    shouldBePlaying    = false;
    currentPath        = null;
    consecutiveReloads = 0;
    loadedImage        = null;
    processedImage     = null;
    currentFrame       = null;

    isScreen             = true;
    lastScreenGrabMillis = 0;        // grab immediately on the next update()
    resetTransform();                // center + fit the grab in the canvas
    grabber.start();
    log("[media] screen capture ON");
  }

  void stopScreenCapture() {
    grabber.stop();
    isScreen       = false;
    loadedImage    = null;
    processedImage = null;
    currentFrame   = null;
    log("[media] screen capture OFF");
  }

  // -------------------------------------------------------------
  // Clear
  // -------------------------------------------------------------

  void clearMedia() {
    if (loadedVideo != null) {
      loadedVideo.stop();
      loadedVideo = null;
    }
    if (grabber != null) grabber.stop();   // Extension A — also drop the lens
    isScreen           = false;
    loadedImage        = null;
    processedImage     = null;
    currentFrame       = null;
    isVideo            = false;
    shouldBePlaying    = false;   // watchdog off until next load
    currentPath        = null;
    consecutiveReloads = 0;
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
  //   currentFrame is now processedImage (already canvas-fit at scale 1.0).
  //   videoScale multiplies that to give the final display size.
  //   Center anchor at (videoX, videoY) in canvas-local coords.
  // -------------------------------------------------------------

  // Per-canvas placement: the SAME shared frame + transform placed relative to
  // whichever container's canvas is passed (two containers => two positions).
  Rect getDisplayBounds(Canvas c) {
    if (currentFrame == null) {
      return new Rect(c.x, c.y, c.width, c.height);
    }

    float w = currentFrame.width  * videoScale;
    float h = currentFrame.height * videoScale;
    float x = c.x + videoX - w / 2.0;
    float y = c.y + videoY - h / 2.0;

    return new Rect(x, y, w, h);
  }

  // Back-compat no-arg: uses this handler's reference canvas.
  Rect getDisplayBounds() {
    return getDisplayBounds(canvas);
  }
}

