// =============================================================
// ColorPipeline — RAW / GAMMA / GAMMA+BRIGHTNESS (phase 7)
// =============================================================
// Maps a raw sampled color to what the LED should actually receive. LEDs are
// perceptually non-linear, so raw 8-bit values look wrong on the ring; a gamma
// curve (default 2.2) corrects that, and a brightness multiplier scales output.
//
// process() is the single entry point, used in TWO places so the on-screen
// preview matches the wire:
//   - RingGrid.writeToDMXBuffer()  — bytes sent over Art-Net
//   - RingGrid.drawPreview()       — the preview discs (WYSIWYG with the ring)
//
// Modes:
//   RAW           — pass through, no change
//   GAMMA         — gamma curve only
//   GAMMA_BRIGHT  — gamma curve, then brightness scale (default)
//
// gammaTable[256] is precomputed and only rebuilt when gamma changes.
// =============================================================

class ColorPipeline {
  static final int MODE_RAW          = 0;
  static final int MODE_GAMMA        = 1;
  static final int MODE_GAMMA_BRIGHT = 2;

  int   mode       = MODE_GAMMA_BRIGHT;   // default
  float gamma      = 2.2;                  // default
  float brightness = 0.5;                  // 0..1, default 50%

  int[] gammaTable = new int[256];

  ColorPipeline() {
    rebuildGammaTable();
  }

  void rebuildGammaTable() {
    for (int i = 0; i < 256; i++) {
      gammaTable[i] = (int) (pow(i / 255.0, gamma) * 255.0 + 0.5);
    }
  }

  void setGamma(float g) {
    gamma = constrain(g, 0.1, 5.0);
    rebuildGammaTable();
  }

  void setBrightness(float b) {
    brightness = constrain(b, 0.0, 1.0);
  }

  void setMode(int m) {
    mode = constrain(m, MODE_RAW, MODE_GAMMA_BRIGHT);
  }

  void cycleMode() {
    mode = (mode + 1) % 3;
  }

  String getModeName() {
    switch (mode) {
    case MODE_RAW:
      return "RAW";
    case MODE_GAMMA:
      return "GAMMA";
    default:
      return "GAMMA+BRIGHT";
    }
  }

  // Raw sampled color -> processed color (identical in preview and on the wire).
  color process(color c) {
    int r = (c >> 16) & 0xFF;
    int g = (c >> 8)  & 0xFF;
    int b =  c        & 0xFF;

    if (mode == MODE_RAW) return color(r, g, b);

    r = gammaTable[r];
    g = gammaTable[g];
    b = gammaTable[b];

    if (mode == MODE_GAMMA_BRIGHT) {
      r = (int) (r * brightness);
      g = (int) (g * brightness);
      b = (int) (b * brightness);
    }
    return color(r, g, b);
  }
}
