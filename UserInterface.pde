// =============================================================
// UserInterface — ControlP5 panel below the canvas
// =============================================================
// Phase 4 (+ patch):
//   - Panel background + top divider
//   - OPEN VIDEO button (mirrors the 'O' key file picker)
//   - GRID toggle (mirrors 'G'), LABELS toggle (mirrors 'L')
//   - PIXELS (N) slider, 8–60 snapped to even (mirrors RingGrid.setN)
//   - Console Textarea (auto-scroll, buffer-limit clear) — log() routes here
//   - FPS readout drawn as text (no more console spam)
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
  color bgColor          = color(25);
  color textColor        = color(220);
  color accentColor      = color(57, 184, 213);
  color disabledColor    = color(15);    // locked textfield bg (broadcast mode)
  color dimmedTextColor  = color(120);   // locked textfield text

  // Layout
  int padding       = 12;
  int elementHeight = 20;
  int rowHeight     = 44;

  // Control references
  Slider nSlider;
  Toggle gridToggle;
  Toggle labelsToggle;

  // Art-Net controls (phase 6b)
  Textfield ipField;
  Textfield portField;
  Textfield subnetField;
  Textfield universeField;
  Toggle    broadcastToggle;
  Toggle    dmxToggle;            // START/STOP DMX (caption flips with state)

  // Guards programmatic toggle updates from firing the change callbacks
  boolean uiSyncing = false;

  // FPS readout (updated each frame from the main sketch)
  float displayFps = 0;

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

    // ----- Art-Net section (phase 6b) — left half, below a divider -----
    // Patterns follow humanoid_face_twin/Processing/ArtNetSender:
    //   broadcast toggle locks/dims the IP field; INTEGER input filters on the
    //   numeric fields; a single START/STOP toggle (caption flips) that
    //   (re)builds the sender from the current field values via startDMX().
    int anLabelY = row2Y + rowHeight;        // ~580, sits just under the divider
    int anRow1Y  = anLabelY + 24;            // broadcast + IP + port
    int anRow2Y  = anRow1Y  + 40;            // subnet + universe + START/STOP

    cp5.addTextlabel("artnetLabel")
      .setText("ARTNET DMX")
      .setPosition(col1, anLabelY)
      .setColor(textColor);

    // IP field is created BEFORE the broadcast toggle so the toggle's initial
    // setValue() can dim/lock it through updateIPField() without a null ref.
    ipField = cp5.addTextfield("ipField")
      .setPosition(col1 + 48, anRow1Y)
      .setSize(110, elementHeight)
      .setText(targetIP)
      .setColor(textColor)
      .setColorCaptionLabel(textColor);
    ipField.setCaptionLabel("TARGET IP");

    portField = cp5.addTextfield("portField")
      .setPosition(col1 + 166, anRow1Y)
      .setSize(50, elementHeight)
      .setText(str(artNetPort))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .setInputFilter(ControlP5.INTEGER);
    portField.setCaptionLabel("PORT");

    broadcastToggle = cp5.addToggle("broadcastToggle")
      .setPosition(col1, anRow1Y)
      .setSize(elementHeight, elementHeight)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          useBroadcast = event.getController().getValue() > 0;
          updateIPField();
        }
      });
    broadcastToggle.setCaptionLabel("BCAST");
    broadcastToggle.setValue(useBroadcast ? 1 : 0);   // fires onChange -> sets initial IP lock/dim

    subnetField = cp5.addTextfield("subnetField")
      .setPosition(col1, anRow2Y)
      .setSize(34, elementHeight)
      .setText(str(subnet))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .setInputFilter(ControlP5.INTEGER);
    subnetField.setCaptionLabel("SUBNET");

    universeField = cp5.addTextfield("universeField")
      .setPosition(col1 + 52, anRow2Y)
      .setSize(34, elementHeight)
      .setText(str(universe))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .setInputFilter(ControlP5.INTEGER);
    universeField.setCaptionLabel("UNIV");

    dmxToggle = cp5.addToggle("dmxToggle")
      .setPosition(col1 + 104, anRow2Y)
      .setSize(elementHeight, elementHeight)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (uiSyncing) return;                 // ignore programmatic sync from 'A'
          if (event.getController().getValue() > 0) startDMX();
          else                                      stopDMX();
          updateDmxCaption();
        }
      });
    dmxToggle.setCaptionLabel("START DMX");

    // ----- Console (right half, beside the Art-Net cluster) -----
    setupConsole();
  }

  void setupConsole() {
    // Right-half layout: the Art-Net cluster occupies the left half below the
    // divider, so the console sits beside it on the right half, leaving a
    // ~16px strip at the bottom for the FPS readout. (log() also mirrors to the
    // Processing IDE console, which keeps the full history.)
    int consoleX = x + width / 2 + 6;
    int consoleY = y + padding + rowHeight * 2 + 2;
    int consoleW = (x + width - padding) - consoleX;
    int consoleH = (y + height - padding - 16) - consoleY;

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

  void syncToggles() {
    uiSyncing = true;
    gridToggle.setValue(ringGrid.gridEnabled ? 1 : 0);
    labelsToggle.setValue(ringGrid.labelsEnabled ? 1 : 0);
    uiSyncing = false;
  }

  void syncN() {
    nSlider.setValue(ringGrid.N);
  }

  // -------------------------------------------------------------
  // Art-Net (phase 6b) — fields drive the globals; START (re)builds the sender
  // from the current values so an ESP32 can be retargeted without code edits.
  // -------------------------------------------------------------

  // Broadcast mode pins the IP to 255.255.255.255 and locks/dims the field;
  // unicast mode unlocks it for a real ESP32 address. (Mirrors the reference.)
  void updateIPField() {
    if (ipField == null) return;
    if (useBroadcast) {
      ipField.setText("255.255.255.255");
      ipField.setLock(true);
      ipField.setColorBackground(disabledColor);
      ipField.setColor(dimmedTextColor);
    } else {
      ipField.setLock(false);
      ipField.setColorBackground(color(60));
      ipField.setColor(textColor);
    }
  }

  // Pull the field values into the globals, tear down any existing sender, and
  // build a fresh one so changed target/port/universe/subnet take effect.
  void startDMX() {
    artNetPort = parseInt(portField.getText());
    subnet     = parseInt(subnetField.getText());
    universe   = parseInt(universeField.getText());
    targetIP   = useBroadcast ? "255.255.255.255" : ipField.getText().trim();

    if (dmxSender != null) dmxSender.stop();      // rebuild from current values
    dmxSender = new DMXSender(useBroadcast, targetIP, artNetPort, universe, subnet);
    dmxSender.connect();
    enableDMX = true;

    log("[artnet] START -> " + (useBroadcast ? "broadcast" : targetIP)
      + ":" + artNetPort + ", universe " + universe + ", subnet " + subnet
      + " (" + (ringGrid.N * 3) + " ch active)");
  }

  // Blackout the ring, flush, and tear down. enableDMX off; sender kept (a
  // following START rebuilds it, so this also covers retargeting cleanly).
  void stopDMX() {
    if (dmxSender != null) {
      resetDMXData();                  // global blackout buffer
      dmxSender.sendDMXData(dmxData);
      delay(100);                      // let the packet flush
      dmxSender.stop();
    }
    enableDMX = false;
    log("[artnet] STOP (blackout sent)");
  }

  void updateDmxCaption() {
    if (dmxToggle != null) dmxToggle.setCaptionLabel(enableDMX ? "STOP DMX" : "START DMX");
  }

  // Push the current enableDMX state into the toggle without re-firing start/
  // stop (the 'A' key has already done the work). Guarded by uiSyncing.
  void syncDmxToggle() {
    uiSyncing = true;
    if (dmxToggle != null) dmxToggle.setValue(enableDMX ? 1 : 0);
    uiSyncing = false;
    updateDmxCaption();
  }

  // -------------------------------------------------------------
  // FPS readout
  // -------------------------------------------------------------

  void setFps(float fps) {
    displayFps = fps;
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
  // Render — panel background + top divider + FPS text. ControlP5 draws its
  // own controls on top automatically (post-draw hook).
  // -------------------------------------------------------------

  void render() {
    fill(bgColor);
    noStroke();
    rect(x, y, width, height);

    stroke(60);
    strokeWeight(1);
    line(x, y, x + width, y);
    noStroke();

    // Divider between the top controls (file/grid/labels/N) and the Art-Net
    // + console section below.
    stroke(textColor, 60);
    strokeWeight(1);
    float midY = y + padding + rowHeight * 2;
    line(x + padding, midY, x + width - padding, midY);
    noStroke();

    // FPS readout — bottom-left of the panel, clear of all controls
    fill(textColor);
    textAlign(LEFT, BOTTOM);
    textSize(12);
    text("FPS: " + nf(displayFps, 0, 1), x + padding, y + height - padding);
  }
}
