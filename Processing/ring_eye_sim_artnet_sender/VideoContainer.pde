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
// Phase 11 (this version): render()'s blit is wrapped in pushMatrix() +
// negative scale() about the canvas CENTER when mirrorH/mirrorV are set, so
// each ring samples its own (possibly flipped) content. A per-container
// DMXSender + universe arrives in phase 12. For now both containers display
// ONE shared decode and only the right (main) ring is wired to DMX.
// =============================================================

class VideoContainer {
  Canvas   canvas;
  RingGrid ring;
  boolean  isMain;
  String   label;            // "right" / "left" (logs / clarity)

  // Mirror — stubs in phase 10, wired in phase 11.
  boolean mirrorH = false;
  boolean mirrorV = false;

  // Art-Net (phase 12a/b) — this eye's own sender, universe + target.
  DMXSender sender;          // lazy: built on startSender(), torn down on stopSender()
  int       universe = 0;    // this eye's universe (right=0, left=1 by default)
  String    targetIP = "255.255.255.255";   // this eye's unicast target (ignored under broadcast)

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
  // When mirrorH/mirrorV are set, wrap the blit in a negative scale() about the
  // CANVAS center (= ring center), so the ring samples flipped content and the
  // two eyes read as mirror images of each other. The main marker is drawn
  // AFTER popMatrix so it stays upright. Null-safe: with no video the canvas is
  // just cleared; the marker still shows.
  void render(PImage frame, MediaHandler media) {
    if (frame != null) {
      Rect b = media.getDisplayBounds(canvas);
      if (mirrorH || mirrorV) {
        float cx = canvas.x + canvas.width  / 2.0;
        float cy = canvas.y + canvas.height / 2.0;
        pushMatrix();
        translate(cx, cy);
        scale(mirrorH ? -1 : 1, mirrorV ? -1 : 1);
        translate(-cx, -cy);
        image(frame, b.x, b.y, b.w, b.h);
        popMatrix();
      } else {
        image(frame, b.x, b.y, b.w, b.h);
      }
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

  // Mirror — set/toggle pairs (UI-driven; no hotkeys in phase 11). Log on change.
  void setMirrorH(boolean on) {
    if (on == mirrorH) return;
    mirrorH = on;
    log("[" + label + "] mirror H: " + (mirrorH ? "ON" : "OFF"));
  }
  void toggleMirrorH() { setMirrorH(!mirrorH); }

  void setMirrorV(boolean on) {
    if (on == mirrorV) return;
    mirrorV = on;
    log("[" + label + "] mirror V: " + (mirrorV ? "ON" : "OFF"));
  }
  void toggleMirrorV() { setMirrorV(!mirrorV); }

  // --- Art-Net (phase 12a) — this eye's own sender on its own universe ---

  // Build (or rebuild) this eye's sender from the shared params + its universe.
  void startSender(boolean useBroadcast, String ip, int port, int subnet, int uni) {
    universe = uni;
    if (sender != null) sender.stop();
    sender = new DMXSender(useBroadcast, ip, port, universe, subnet);
    sender.connect();
  }

  // Send an all-zero frame on this universe (blackout). Reuses the shared buffer.
  void blackout(byte[] dmxData) {
    if (sender == null) return;
    java.util.Arrays.fill(dmxData, (byte) 0);
    sender.sendDMXData(dmxData);
  }

  // Tear down this eye's sender (call after blackout + a short flush).
  void stopSender() {
    if (sender != null) { sender.stop(); sender = null; }
  }

  // Zero the shared scratch, write THIS ring through the pipeline, send on THIS
  // universe. No-op if the sender isn't up.
  void writeAndSend(byte[] dmxData, ColorPipeline pipeline, boolean hasContent) {
    if (sender == null) return;
    java.util.Arrays.fill(dmxData, (byte) 0);
    if (hasContent) ring.writeToDMXBuffer(dmxData, pipeline);
    sender.sendDMXData(dmxData);
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
