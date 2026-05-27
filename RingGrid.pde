// =============================================================
// RingGrid — parametric ring of cells (visual + sampling)
// =============================================================
// Phase 3 (this version): visual overlay only.
//   - N hardcoded to 12 (slider comes in phase 4)
//   - Geometry matches the Figma component set exactly:
//       RING_R   = 350.0  (centerline radius)
//       cellSize = 2*R*sin(π/N) / (1 + sin(π/N)) * BREATHE
//       BREATHE  = 0.95
//   - Cells: stroked red rotated radial squares (no fill — video shows through)
//   - Labels: red, positioned OUTSIDE each cell along the ring direction,
//             not rotated (always upright for readability)
//   - Guides: dim red dashed centerline circle + center crosshair (~40% alpha)
//   - LED 0 at 12 o'clock, CW around the ring
//
// Performance: cell centers and rotations are PRE-COMPUTED into primitive
// arrays in precomputeCells(). The draw loop has zero allocations from
// this class.
//
// Future phases:
//   - phase 4: setN() via ControlP5 slider — calls precomputeCells() to refresh
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

  // ---- precomputed per-cell geometry (refreshed when N changes) ----
  float[] cellCx;        // cell center x in sketch coords
  float[] cellCy;        // cell center y in sketch coords
  float[] cellRot;       // cell rotation in radians
  float[] labelCx;       // label center x in sketch coords
  float[] labelCy;       // label center y in sketch coords
  float   cachedCellSize;
  float   cachedTextSize;

  RingGrid(Canvas canvas) {
    this.canvas = canvas;
    precomputeCells();
  }

  // -------------------------------------------------------------
  // Geometry
  // -------------------------------------------------------------

  float cellSize() {
    return cachedCellSize;
  }

  // Re-fill all the cached arrays. Call after constructing OR after setN().
  void precomputeCells() {
    float s        = sin(PI / N);
    cachedCellSize = 2.0 * RING_R * s / (1.0 + s) * BREATHE;
    cachedTextSize = constrain(cachedCellSize * 0.2, 8, 20);
    float labelR   = RING_R + cachedCellSize / 2.0 + cachedTextSize;

    cellCx  = new float[N];
    cellCy  = new float[N];
    cellRot = new float[N];
    labelCx = new float[N];
    labelCy = new float[N];

    float canvasCx = canvas.x + canvas.width  / 2.0;
    float canvasCy = canvas.y + canvas.height / 2.0;

    for (int i = 0; i < N; i++) {
      float phi    = i * TWO_PI / N;
      float sinPhi = sin(phi);
      float cosPhi = cos(phi);

      cellCx[i]  = canvasCx + RING_R * sinPhi;
      cellCy[i]  = canvasCy - RING_R * cosPhi;
      cellRot[i] = phi;
      labelCx[i] = canvasCx + labelR * sinPhi;
      labelCy[i] = canvasCy - labelR * cosPhi;
    }
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

  // Stroked red rotated radial squares — no fill, video shows through
  void drawCells() {
    noFill();
    stroke(255, 0, 0);
    strokeWeight(2);
    rectMode(CENTER);

    float s = cachedCellSize;
    for (int i = 0; i < N; i++) {
      pushMatrix();
      translate(cellCx[i], cellCy[i]);
      rotate(cellRot[i]);
      rect(0, 0, s, s);
      popMatrix();
    }

    rectMode(CORNER);  // restore Processing default
  }

  // Red labels positioned OUTSIDE each cell along the ring direction.
  // Always drawn upright (no rotate) for readability.
  void drawLabels() {
    fill(255, 0, 0);
    noStroke();
    textAlign(CENTER, CENTER);
    textSize(cachedTextSize);

    for (int i = 0; i < N; i++) {
      text(str(i), labelCx[i], labelCy[i]);
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
