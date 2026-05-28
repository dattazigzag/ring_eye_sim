// =============================================================
// RingGrid — parametric ring of cells (visual + sampling)
// =============================================================
// Phase 3: visual overlay (stroked red cells, labels, guides).
// Phase 4 (this version): N is now adjustable via setN() (driven by the
//   ControlP5 slider). Toggles refactored into set/toggle pairs so the
//   keyboard and the UI can both drive them without double-toggling.
//
//   - Geometry matches the Figma component set, scaled to the canvas:
//       ringR    = canvas.width * (350.0 / 1024.0)   (centerline radius)
//       cellSize = 2*ringR*sin(π/N) / (1 + sin(π/N)) * BREATHE
//       BREATHE  = 0.95
//   - Cells: stroked red rotated radial squares (no fill — video shows through)
//   - Labels: red, outside each cell, upright
//   - Guides: dim red dashed centerline circle + center crosshair
//   - LED 0 at 12 o'clock, CW around the ring
//   - Per-cell geometry pre-computed into primitive arrays (zero per-frame alloc)
//
// Phase 5 (this version): sampleColors() averages the video pixels inside each
//   cell's inscribed circle into cellColors[]; drawPreview() shows them as
//   filled discs (toggle 'C'). Sampling reads the framebuffer AFTER the video
//   is drawn but BEFORE the overlay, so we never average our own red cells.
//
// Future phases:
//   - phase 6: writeToDMXBuffer()
// =============================================================

class RingGrid {
  // Geometry constants — match Figma.
  // RING_R was a fixed 350.0 tuned for a 1024 canvas. It's now derived from the
  // canvas size (in the constructor) so the ring keeps the same 350/1024
  // proportion at any canvas size — e.g. ~164 on a 480 canvas.
  static final float RING_R_REF = 350.0;    // reference centerline radius @ 1024 canvas
  static final float CANVAS_REF = 1024.0;   // reference canvas size for the ratio
  float ringR;                              // actual centerline radius (set in constructor)
  static final float BREATHE    = 0.95;

  // N range (matches the ControlP5 slider)
  static final int N_MIN = 8;
  static final int N_MAX = 60;

  Canvas canvas;
  int    N = 12;

  boolean gridEnabled    = true;
  boolean labelsEnabled  = true;
  boolean previewEnabled = false;   // sampled-color preview discs (toggle 'C')

  // ---- precomputed per-cell geometry (refreshed when N changes) ----
  float[] cellCx;        // cell center x in sketch coords
  float[] cellCy;        // cell center y in sketch coords
  float[] cellRot;       // cell rotation in radians
  float[] labelCx;       // label center x in sketch coords
  float[] labelCy;       // label center y in sketch coords
  color[] cellColors;    // latest sampled color per cell (phase 5)
  float   cachedCellSize;
  float   cachedTextSize;

  RingGrid(Canvas canvas) {
    this.canvas = canvas;
    ringR = canvas.width * (RING_R_REF / CANVAS_REF);  // keep the Figma 350/1024 proportion
    precomputeCells();
  }

  // -------------------------------------------------------------
  // N control
  // -------------------------------------------------------------

  // Set the pixel count. Clamps to [N_MIN, N_MAX] and snaps to an even number
  // (NeoPixel rings come in even counts; keeps the slider behavior clean).
  void setN(int newN) {
    newN = constrain(newN, N_MIN, N_MAX);
    if (newN % 2 != 0) newN++;        // snap up to even
    newN = constrain(newN, N_MIN, N_MAX);
    if (newN == N) return;            // no change → skip recompute
    N = newN;
    precomputeCells();
    log("[ring] N=" + N + ", cellSize=" + nf(cachedCellSize, 0, 1));
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
    cachedCellSize = 2.0 * ringR * s / (1.0 + s) * BREATHE;
    cachedTextSize = constrain(cachedCellSize * 0.2, 8, 20);
    float labelR   = ringR + cachedCellSize / 2.0 + cachedTextSize;

    cellCx  = new float[N];
    cellCy  = new float[N];
    cellRot = new float[N];
    labelCx = new float[N];
    labelCy = new float[N];
    cellColors = new color[N];

    float canvasCx = canvas.x + canvas.width  / 2.0;
    float canvasCy = canvas.y + canvas.height / 2.0;

    for (int i = 0; i < N; i++) {
      float phi    = i * TWO_PI / N;
      float sinPhi = sin(phi);
      float cosPhi = cos(phi);

      cellCx[i]  = canvasCx + ringR * sinPhi;
      cellCy[i]  = canvasCy - ringR * cosPhi;
      cellRot[i] = phi;
      labelCx[i] = canvasCx + labelR * sinPhi;
      labelCy[i] = canvasCy - labelR * cosPhi;
    }
  }

  // -------------------------------------------------------------
  // Toggles — set/toggle pairs so keyboard and UI can both drive state.
  // setX() is the single source of truth; it logs only on actual change.
  // -------------------------------------------------------------

  void setGrid(boolean on) {
    if (on == gridEnabled) return;
    gridEnabled = on;
    log("[ring] grid: " + (gridEnabled ? "ON" : "OFF"));
  }

  void toggleGrid() {
    setGrid(!gridEnabled);
  }

  void setLabels(boolean on) {
    if (on == labelsEnabled) return;
    labelsEnabled = on;
    log("[ring] labels: " + (labelsEnabled ? "ON" : "OFF"));
  }

  void toggleLabels() {
    setLabels(!labelsEnabled);
  }

  void setPreview(boolean on) {
    if (on == previewEnabled) return;
    previewEnabled = on;
    log("[ring] preview: " + (previewEnabled ? "ON" : "OFF"));
  }

  void togglePreview() {
    setPreview(!previewEnabled);
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

    drawDashedCircle(cx, cy, ringR, 6, 6);

    int crossLen = 10;
    line(cx - crossLen, cy, cx + crossLen, cy);
    line(cx, cy - crossLen, cx, cy + crossLen);
  }

  // Stroked red rotated radial squares — no fill, video shows through
  void drawCells() {
    noFill();
    stroke(255, 0, 0);
    strokeWeight(1);
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
  // Sampling (phase 5)
  // -------------------------------------------------------------

  // Average the rendered video color inside each cell's inscribed circle into
  // cellColors[]. Reads the sketch framebuffer directly via loadPixels() —
  // relies on pixelDensity(1) (pixels[] is 1:1 with logical coords). MUST be
  // called after the video is drawn but BEFORE drawOverlay(), otherwise we'd
  // average our own red cell strokes. Uses bit-shift channel extraction (no
  // red()/green()/blue() calls) and primitive accumulators to stay alloc-free.
  void sampleColors() {
    loadPixels();                 // sketch framebuffer -> pixels[]
    int sw = width;               // sketch (= pixels[]) width

    // Clamp sampling to the canvas region so we never read the UI panel below.
    int minX = (int) canvas.x;
    int minY = (int) canvas.y;
    int maxX = (int) (canvas.x + canvas.width)  - 1;
    int maxY = (int) (canvas.y + canvas.height) - 1;

    float r  = cachedCellSize / 2.0;
    int   ri = max(1, (int) r);
    float r2 = r * r;

    for (int i = 0; i < N; i++) {
      int ccx = (int) cellCx[i];
      int ccy = (int) cellCy[i];

      int sumR = 0, sumG = 0, sumB = 0, count = 0;
      for (int dy = -ri; dy <= ri; dy++) {
        int y = ccy + dy;
        if (y < minY || y > maxY) continue;
        for (int dx = -ri; dx <= ri; dx++) {
          if (dx * dx + dy * dy > r2) continue;   // inside the inscribed circle
          int x = ccx + dx;
          if (x < minX || x > maxX) continue;
          int c = pixels[y * sw + x];
          sumR += (c >> 16) & 0xFF;
          sumG += (c >> 8)  & 0xFF;
          sumB +=  c        & 0xFF;
          count++;
        }
      }
      cellColors[i] = (count > 0)
        ? color(sumR / count, sumG / count, sumB / count)
        : color(0);
    }
  }

  // Filled disc of the sampled color at each cell center — visual confirmation
  // that sampleColors() reads the right pixels. Toggled by 'C'. A thin dark
  // ring keeps light samples visible against light video.
  void drawPreview() {
    if (!previewEnabled || cellColors == null) return;

    pushStyle();
    float pr = constrain(cachedCellSize * 0.30, 4, 20);   // preview disc radius
    stroke(0, 120);
    strokeWeight(1);
    for (int i = 0; i < N; i++) {
      fill(cellColors[i]);
      ellipse(cellCx[i], cellCy[i], pr * 2, pr * 2);
    }
    popStyle();
  }

  // -------------------------------------------------------------
  // DMX (phase 6)
  // -------------------------------------------------------------

  // Write each cell's RAW sampled RGB into the DMX buffer: channels
  // i*3, i*3+1, i*3+2 = R, G, B for LED i. No color pipeline yet (phase 7).
  // Reads cellColors[] — caller must run sampleColors() first this frame.
  // Java bytes are signed; the 0xFF-masked cast preserves the raw 0..255 byte
  // on the wire, which is what Art-Net expects.
  void writeToDMXBuffer(byte[] dmxData) {
    if (cellColors == null) return;
    for (int i = 0; i < N; i++) {
      int base = i * 3;
      if (base + 2 >= dmxData.length) break;   // 512-channel safety
      int c = cellColors[i];
      dmxData[base]     = (byte) ((c >> 16) & 0xFF);  // R
      dmxData[base + 1] = (byte) ((c >> 8)  & 0xFF);  // G
      dmxData[base + 2] = (byte) ( c        & 0xFF);  // B
    }
  }

  // -------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------

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
