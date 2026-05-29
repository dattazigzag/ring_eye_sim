// =============================================================
// VideoContainer — one "eye": a display region (Canvas) + its ring.
// =============================================================
// Phase 10: holds a Canvas + RingGrid + isMain (+ stub mirrorH/mirrorV).
//   render()     — blit the SHARED frame into this canvas at the shared
//                  transform; if main, draw the constant cyan marker.
//   sampleRing() — this ring samples its OWN canvas region from the
//                  framebuffer. The CALLER calls loadPixels() once per frame
//                  before sampling both containers, so the two share a single
//                  GPU readback.
//   drawRing()   — overlay (cells/labels/guides) + preview discs, both
//                  internally gated. Drawn AFTER sampling.
//
// Phase 11 wraps render()'s blit in a negative scale() for mirror. A
// per-container DMXSender + universe arrives in phase 12. For now both
// containers display ONE shared decode and only the right (main) ring is
// wired to DMX by the main sketch.
// =============================================================

class VideoContainer {
  Canvas   canvas;
  RingGrid ring;
  boolean  isMain;
  String   label;            // "right" / "left" (logs / clarity)

  // Mirror — stubs in phase 10, wired in phase 11.
  boolean mirrorH = false;
  boolean mirrorV = false;

  // Constant cyan main marker (same cyan as the adjust guides), top-left inset.
  static final float MARKER_SIZE  = 12.5;
  static final float MARKER_INSET = 8;

  VideoContainer(Canvas canvas, RingGrid ring, boolean isMain, String label) {
    this.canvas = canvas;
    this.ring   = ring;
    this.isMain = isMain;
    this.label  = label;
  }

  // Blit the shared frame into this canvas at the shared transform bounds.
  // (Phase 11 will wrap the blit in a negative-scale mirror.) Null-safe: with
  // no video the canvas is just cleared; the main marker still shows.
  void render(PImage frame, MediaHandler media) {
    if (frame != null) {
      Rect b = media.getDisplayBounds(canvas);
      image(frame, b.x, b.y, b.w, b.h);
    }
    if (isMain) drawMainMarker();
  }

  // Cyan square so it's unambiguous which container is the main/source — the
  // one to load against, and the one the tools/ tester mirrors.
  void drawMainMarker() {
    pushStyle();
    noStroke();
    fill(57, 184, 213);
    rectMode(CORNER);
    rect(canvas.x + MARKER_INSET, canvas.y + MARKER_INSET, MARKER_SIZE, MARKER_SIZE);
    popStyle();
  }

  // Sample this ring from the framebuffer. The CALLER calls loadPixels() once
  // per frame before sampling both containers, so we don't pay two GPU
  // readbacks. Each ring clamps to its own canvas region internally.
  void sampleRing() {
    ring.sampleColors();
  }

  // Overlay + preview, drawn AFTER sampling so we never sample our own cells.
  void drawRing(ColorPipeline pipeline) {
    ring.drawOverlay();
    ring.drawPreview(pipeline);
  }
}
