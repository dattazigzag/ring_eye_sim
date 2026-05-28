// =============================================================
// UserInterface — ControlP5 panel below the canvas
// =============================================================
// Phase 4 (this version):
//   - Panel background + top divider
//   - OPEN VIDEO button (mirrors the 'O' key file picker)
//   - GRID toggle (mirrors 'G'), LABELS toggle (mirrors 'L')
//   - PIXELS (N) slider, 8–60 snapped to even (mirrors RingGrid.setN)
//   - Console Textarea (auto-scroll, buffer-limit clear) — log() routes here
//
// Colors / styling follow the existing humanoid_face_twin project:
//   accent cyan = (57,184,213), bg = (25), text = (220).
//
// Keyboard <-> UI sync:
//   The uiSyncing flag guards toggle callbacks. When a keypress changes
//   state, syncToggles() pushes the new value into the toggles with
//   uiSyncing=true so the callback ignores the programmatic change (no
//   double-toggle). User clicks have uiSyncing=false and act normally.
//
// Future phases:
//   - phase 6: Art-Net fields (IP / port / subnet / universe / broadcast /
//     START-STOP) — left half, below the N slider
//   - phase 7: brightness slider + gamma mode selector
// =============================================================

class UserInterface {
  PApplet   parent;
  int       x, y, width, height;
  ControlP5 cp5;
  Textarea  console;

  // Colors (match existing project)
  color bgColor        = color(25);
  color textColor      = color(220);
  color accentColor    = color(57, 184, 213);

  // Layout
  int padding       = 12;
  int elementHeight = 20;
  int rowHeight     = 44;

  // Control references
  Slider nSlider;
  Toggle gridToggle;
  Toggle labelsToggle;

  // Guards programmatic toggle updates from firing the change callbacks
  boolean uiSyncing = false;

  UserInterface(PApplet parent, int x, int y, int width, int height) {
    this.parent = parent;
    this.x      = x;
    this.y      = y;
    this.width  = width;
    this.height = height;

    cp5 = new ControlP5(parent);
    setupControls();
  }

  // -------------------------------------------------------------
  // Control setup
  // -------------------------------------------------------------

  void setupControls() {
    cp5.setColorForeground(color(50));
    cp5.setColorBackground(color(50));
    cp5.setColorActive(accentColor);

    int col1   = x + padding;
    int row1Y  = y + padding;
    int row2Y  = row1Y + rowHeight;

    // ----- Row 1: file picker + grid/labels toggles -----

    cp5.addButton("openVideoBtn")
      .setPosition(col1, row1Y)
      .setSize(110, elementHeight)
      .setColorCaptionLabel(textColor)
      .onClick(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          openFilePicker();   // global in main sketch
        }
      });
    cp5.getController("openVideoBtn").setCaptionLabel("OPEN VIDEO");

    gridToggle = cp5.addToggle("gridToggle")
      .setPosition(col1 + 140, row1Y)
      .setSize(elementHeight, elementHeight)
      .setValue(ringGrid.gridEnabled)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (uiSyncing) return;       // ignore programmatic sync
          ringGrid.setGrid(event.getController().getValue() > 0);
        }
      });
    gridToggle.setCaptionLabel("GRID");

    labelsToggle = cp5.addToggle("labelsToggle")
      .setPosition(col1 + 230, row1Y)
      .setSize(elementHeight, elementHeight)
      .setValue(ringGrid.labelsEnabled)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (uiSyncing) return;
          ringGrid.setLabels(event.getController().getValue() > 0);
        }
      });
    labelsToggle.setCaptionLabel("LABELS");

    // ----- Row 2: PIXELS (N) slider -----
    // 8..60 with tick marks every 2 → 27 stops. snapToTickMarks keeps the
    // value on the even grid; setN() also snaps defensively.
    int nStops = (RingGrid.N_MAX - RingGrid.N_MIN) / 2 + 1;   // 27

    nSlider = cp5.addSlider("nSlider")
      .setPosition(col1, row2Y)
      .setSize(220, elementHeight)
      .setRange(RingGrid.N_MIN, RingGrid.N_MAX)
      .setNumberOfTickMarks(nStops)
      .snapToTickMarks(true)
      .setValue(ringGrid.N)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          ringGrid.setN((int) event.getController().getValue());
        }
      });
    nSlider.getCaptionLabel()
      .align(ControlP5.LEFT, ControlP5.BOTTOM_OUTSIDE)
      .setPaddingY(4)
      .setText("PIXELS (N)")
      .setColor(textColor);
    nSlider.getValueLabel().setColor(textColor);

    // ----- Console (right half) -----
    setupConsole();
  }

  void setupConsole() {
    int consoleX = x + width / 2;
    int consoleY = y + padding;
    int consoleW = width / 2 - padding;
    int consoleH = height - padding * 2;

    console = cp5.addTextarea("console")
      .setPosition(consoleX, consoleY)
      .setSize(consoleW, consoleH)
      .setLineHeight(14)
      .setColor(color(180))
      .setColorForeground(color(255, 50))
      .scroll(1.0)
      .showScrollbar();
    console.getCaptionLabel().setText("");

    printToConsole("ring_eye_sim console ready");
    printToConsole("-------------------------------");
  }

  // -------------------------------------------------------------
  // Keyboard -> UI sync
  // -------------------------------------------------------------

  // Push current RingGrid toggle state into the UI without firing callbacks.
  void syncToggles() {
    uiSyncing = true;
    gridToggle.setValue(ringGrid.gridEnabled ? 1 : 0);
    labelsToggle.setValue(ringGrid.labelsEnabled ? 1 : 0);
    uiSyncing = false;
  }

  // Push current RingGrid N into the slider without firing the callback.
  void syncN() {
    nSlider.setValue(ringGrid.N);   // value matches → setN() early-returns anyway
  }

  // -------------------------------------------------------------
  // Console
  // -------------------------------------------------------------

  void printToConsole(String message) {
    if (console == null) return;
    console.append(message + "\n");
    console.scroll(1.0);
    if (countLines(console.getText()) > CONSOLE_BUFFER_LIMIT) {
      console.clear();
      console.append("(console cleared at buffer limit)\n");
    }
  }

  int countLines(String text) {
    if (text == null || text.isEmpty()) return 0;
    return text.split("\n").length;
  }

  // -------------------------------------------------------------
  // Render — panel background + top divider. ControlP5 draws its own
  // controls on top automatically (post-draw hook).
  // -------------------------------------------------------------

  void render() {
    fill(bgColor);
    noStroke();
    rect(x, y, width, height);

    stroke(60);
    strokeWeight(1);
    line(x, y, x + width, y);
    noStroke();
  }
}
