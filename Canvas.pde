// =============================================================
// Canvas — the 1024×1024 display region for video + ring overlay
// =============================================================
// Minimal in phase 1; same role as in the existing humanoid_face_twin
// project. Holds bounds, renders its background. Kept as a separate
// class so later phases can reposition or repaint without touching
// the main sketch.
// =============================================================

class Canvas {
  int x, y, width, height;

  Canvas(int x, int y, int width, int height) {
    this.x      = x;
    this.y      = y;
    this.width  = width;
    this.height = height;
  }

  void render() {
    fill(0);
    noStroke();
    rect(x, y, width, height);
  }
}
