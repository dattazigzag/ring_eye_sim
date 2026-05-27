// =============================================================
// RingGrid — parametric ring of cells (visual + sampling)
// =============================================================
// Phase 3 (this version): visual overlay only.
//   - N hardcoded to 12 (slider comes in phase 4)
//   - Geometry matches the Figma component set exactly:
//       RING_R   = 350.0  (centerline radius)
//       cellSize = 2*R*sin(π/N) / (1 + sin(π/N)) * BREATHE
//       BREATHE  = 0.95
//   - Cells: solid red rotated radial squares
//   - Labels: red, positioned OUTSIDE each cell along the ring direction,
//             not rotated (always upright for readability)
//   - Guides: dim red dashed centerline circle + center crosshair (~40% alpha)
//   - LED 0 at 12 o'clock, CW around the ring
//
// Future phases:
//   - phase 4: setN() via ControlP5 slider
//   - phase 5: sampleColors() + preview circles
//   - phase 6: writeToDMXBuffer()
// =============================================================

class RingGrid {
  // Geometry constants — match Figma
  static final float RING_R  = 350.0;
  static final float BREATHE = 0.95;

  Canvas canvas;
  int    N = 12;

  boolean gridEnabled   = true;
  boolean labelsEnabled = true;

  RingGrid(Canvas canvas) {
    this.canvas = canvas;
  }

  // -------------------------------------------------------------
  // Geometry
  // -------------------------------------------------------------

  float cellSize() {
    float s = sin(PI / N);
    return 2.0 * RING_R * s / (1.0 + s) * BREATHE;
  }

  // World-space (sketch coords) center of cell i.
  // LED 0 at 12 o'clock, CW around the ring.
  PVector cellCenter(int i) {
    float phi = i * TWO_PI / N;
    float cx  = canvas.x + canvas.width  / 2.0 + RING_R * sin(phi);
    float cy  = canvas.y + canvas.height / 2.0 - RING_R * cos(phi);
    return new PVector(cx, cy);
  }

  float cellRotation(int i) {
    return i * TWO_PI / N;
  }

  // -------------------------------------------------------------
  // Toggles
  // -------------------------------------------------------------

  void toggleGrid() {
    gridEnabled = !gridEnabled;
    log("[ring] grid: " + (gridEnabled ? "ON" : "OFF"));
  }

  void toggleLabels() {
    labelsEnabled = !labelsEnabled;
    log("[ring] labels: " + (labelsEnabled ? "ON" : "OFF"));
  }

  // -------------------------------------------------------------
  // Render
  // -------------------------------------------------------------

  void drawOverlay() {
    if (!gridEnabled) return;

    pushStyle();
    drawGuides();
    drawCells();
    if (labelsEnabled) drawLabels();
    popStyle();
  }

  // Dim red dashed centerline circle + center crosshair (~40% alpha)
  void drawGuides() {
    float cx = canvas.x + canvas.width  / 2.0;
    float cy = canvas.y + canvas.height / 2.0;

    stroke(255, 0, 0, 100);   // 100/255 ≈ 40% alpha
    strokeWeight(1);
    noFill();

    // Dashed centerline circle at radius R
    drawDashedCircle(cx, cy, RING_R, 6, 6);

    // Center crosshair
    int crossLen = 10;
    line(cx - crossLen, cy, cx + crossLen, cy);
    line(cx, cy - crossLen, cx, cy + crossLen);
  }

  // Solid red rotated radial squares (matches Figma cell visual)
  void drawCells() {
    fill(255, 0, 0);
    noStroke();
    rectMode(CENTER);

    float s = cellSize();
    for (int i = 0; i < N; i++) {
      PVector c   = cellCenter(i);
      float   phi = cellRotation(i);

      pushMatrix();
      translate(c.x, c.y);
      rotate(phi);
      rect(0, 0, s, s);
      popMatrix();
    }

    rectMode(CORNER);  // restore Processing default
  }

  // Red labels positioned OUTSIDE each cell along the ring direction.
  // Always drawn upright (no rotate) for readability.
  void drawLabels() {
    fill(255, 0, 0);
    textAlign(CENTER, CENTER);

    float s  = cellSize();
    float ts = constrain(s * 0.2, 8, 20);
    textSize(ts);

    float labelOffset = s / 2.0 + ts;  // outside the cell edge, by ~one text-size gap
    for (int i = 0; i < N; i++) {
      float phi = cellRotation(i);
      float cx  = canvas.x + canvas.width  / 2.0 + (RING_R + labelOffset) * sin(phi);
      float cy  = canvas.y + canvas.height / 2.0 - (RING_R + labelOffset) * cos(phi);
      text(str(i), cx, cy);
    }
  }

  // -------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------

  // Approximates a dashed circle by drawing short straight line segments
  // between arc-spaced points. Good enough for guide lines at R=350.
  void drawDashedCircle(float cx, float cy, float r, float dashLen, float gapLen) {
    float circumference   = TWO_PI * r;
    int   totalSegments   = int(circumference / (dashLen + gapLen));
    float anglePerSegment = TWO_PI / totalSegments;
    float dashAngle       = (dashLen / (dashLen + gapLen)) * anglePerSegment;

    for (int i = 0; i < totalSegments; i++) {
      float a1 = i * anglePerSegment;
      float a2 = a1 + dashAngle;
      float x1 = cx + r * cos(a1);
      float y1 = cy + r * sin(a1);
      float x2 = cx + r * cos(a2);
      float y2 = cy + r * sin(a2);
      line(x1, y1, x2, y2);
    }
  }
}
