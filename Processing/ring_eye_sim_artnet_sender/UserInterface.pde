// =============================================================
// UserInterface — ControlP5 panel below the canvas
// =============================================================
// Phase 6c (this version): layout polish + colored console.
//   TOP-LEFT  : OPEN VIDEO button + GRID / LABELS / PREVIEW toggles on one row
//               (tight grouped spacing); N slider below — shortened, caption to
//               the RIGHT for legibility, accent foreground so the value fill is
//               always visible (not only on hover).
//   TOP-RIGHT : Art-Net cluster — BCAST / TARGET IP / PORT, then
//               SUBNET / UNIV / START-STOP.
//   A light vertical separator divides the left controls from the cluster.
//   BOTTOM    : full-width custom console under a horizontal separator.
//
// Console: a hand-drawn colored log (ControlP5's Textarea can't color per
//   line). Each line is stored with its own color; severities info (grey) /
//   ok (green) / warn (amber) / err (red) are emitted from the main sketch via
//   log() / logOk() / logWarn() / logErr().
//
// Keyboard <-> UI sync: the uiSyncing flag guards toggle callbacks so a
//   key-driven change pushed back into a toggle doesn't double-fire.
//
// Future phases:
//   - phase 7: brightness slider + gamma mode selector
// =============================================================

class UserInterface {
  PApplet   parent;
  int       x, y, width, height;
  ControlP5 cp5;

  // Colors
  color bgColor          = color(25);
  color textColor        = color(220);
  color accentColor      = color(57, 184, 213);
  color disabledColor    = color(15);    // locked textfield bg (broadcast mode)
  color dimmedTextColor  = color(120);   // locked textfield text

  // Console severity colors
  color cInfo = color(185);              // normal
  color cOk   = color(90, 200, 130);     // green  (success / status)
  color cWarn = color(235, 170, 70);     // amber  (warning)
  color cErr  = color(225, 85, 85);      // red    (error)

  // Layout
  int padding       = 12;
  int elementHeight = 20;

  // Vertical separator x + console rect (computed in setupControls)
  int sepX;
  int consoleX, consoleY, consoleW, consoleH;

  // Control references
  Slider nSlider;
  Toggle gridToggle;
  Toggle labelsToggle;
  Toggle previewToggle;

  // Art-Net controls (phase 6b)
  Textfield ipField;
  Textfield portField;
  Textfield subnetField;
  Textfield universeField;
  Toggle    broadcastToggle;
  Toggle    dmxToggle;            // START/STOP DMX (caption flips with state)

  // MQTT controls — host/port editable only while the toggle is OFF
  Textfield mqttHostField;
  Textfield mqttPortField;
  Toggle    mqttToggle;          // MQTT on/off (default on)

  // Mirror toggles (phase 11) — per-container H/V flip (UI-only, no hotkeys)
  Toggle    rMirrorHToggle, rMirrorVToggle;
  Toggle    lMirrorHToggle, lMirrorVToggle;

  // Color pipeline controls (phase 7)
  Slider    brightnessSlider;
  Textfield gammaField;
  Button    modeButton;          // cycles RAW -> GAMMA -> GAMMA+BRIGHT

  // Guards programmatic toggle updates from firing the change callbacks
  boolean uiSyncing = false;

  // FPS readout (updated each frame from the main sketch)
  float displayFps = 0;

  // Custom colored console buffer (parallel arrays: text + color per line)
  java.util.ArrayList<String>  conLines  = new java.util.ArrayList<String>();
  java.util.ArrayList<Integer> conColors = new java.util.ArrayList<Integer>();

  UserInterface(PApplet parent, int x, int y, int width, int height) {
    this.parent = parent;
    this.x      = x;
    this.y      = y;
    this.width  = width;
    this.height = height;

    cp5 = new ControlP5(parent);
    setupControls();

    printToConsole("ring_eye_sim console ready");
    printToConsole("-------------------------------");
  }

  // -------------------------------------------------------------
  // Control setup
  // -------------------------------------------------------------

  void setupControls() {
    cp5.setColorForeground(color(50));
    cp5.setColorBackground(color(50));
    cp5.setColorActive(accentColor);

    int col1 = x + padding;

    // ===== TOP-LEFT: file + toggles row, slider row =====
    int row1Y = y + padding;            // button + GRID/LABELS/PREVIEW
    int row2Y = row1Y + 38;             // N slider

    cp5.addButton("openVideoBtn")
      .setPosition(col1, row1Y)
      .setSize(84, elementHeight)
      .setColorCaptionLabel(textColor)
      .onClick(new CallbackListener() {
        public void controlEvent(CallbackEvent event) { openFilePicker(); }
      });
    cp5.getController("openVideoBtn").setCaptionLabel("OPEN VIDEO");

    int togX     = col1 + 96;           // toggles start just right of the button
    int togPitch = 46;                  // tight, grouped spacing

    gridToggle = cp5.addToggle("gridToggle")
      .setPosition(togX, row1Y)
      .setSize(elementHeight, elementHeight)
      .setValue(ringGrid.gridEnabled)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (uiSyncing) return;
          applyGrid(event.getController().getValue() > 0);
        }
      });
    gridToggle.setCaptionLabel("GRID");

    labelsToggle = cp5.addToggle("labelsToggle")
      .setPosition(togX + togPitch, row1Y)
      .setSize(elementHeight, elementHeight)
      .setValue(ringGrid.labelsEnabled)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (uiSyncing) return;
          applyLabels(event.getController().getValue() > 0);
        }
      });
    labelsToggle.setCaptionLabel("LABELS");

    previewToggle = cp5.addToggle("previewToggle")
      .setPosition(togX + togPitch * 2, row1Y)
      .setSize(elementHeight, elementHeight)
      .setValue(ringGrid.previewEnabled)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (uiSyncing) return;
          applyPreview(event.getController().getValue() > 0);
        }
      });
    previewToggle.setCaptionLabel("PREVIEW");

    // N slider — shortened; caption to the RIGHT; fill always visible (accent
    // foreground) so it reads at the default value without hovering.
    nSlider = cp5.addSlider("nSlider")
      .setPosition(col1, row2Y)
      .setSize(108, elementHeight)
      .setRange(RingGrid.N_MIN, RingGrid.N_MAX)
      .setNumberOfTickMarks((RingGrid.N_MAX - RingGrid.N_MIN) / 2 + 1)
      .snapToTickMarks(true)
      .setValue(ringGrid.N)
      .setColorForeground(accentColor)
      .setColorActive(accentColor)
      .setColorValueLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          applyN((int) event.getController().getValue());   // both rings + MQTT publish
        }
      });
    nSlider.getCaptionLabel()
      .align(ControlP5.RIGHT_OUTSIDE, ControlP5.CENTER)
      .setPaddingX(8)
      .setText("PIXELS (N)")
      .setColor(textColor);

    // ----- Color pipeline (phase 7): BRIGHT % + GAMMA, then MODE cycle -----
    int row3Y = row2Y + 38;             // brightness slider + gamma field
    int row4Y = row3Y + 36;             // mode cycle button (clears the GAMMA field's caption)

    brightnessSlider = cp5.addSlider("brightnessSlider")
      .setPosition(col1, row3Y)
      .setSize(108, elementHeight)
      .setRange(0, 100)
      .setValue(colorPipeline.brightness * 100.0)
      .setColorForeground(accentColor)
      .setColorActive(accentColor)
      .setColorValueLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (uiSyncing) return;
          colorPipeline.setBrightness(event.getController().getValue() / 100.0);
        }
      });
    brightnessSlider.getCaptionLabel()
      .align(ControlP5.RIGHT_OUTSIDE, ControlP5.CENTER)
      .setPaddingX(8)
      .setText("BRIGHT %")
      .setColor(textColor);

    gammaField = cp5.addTextfield("gammaField")
      .setPosition(col1 + 178, row3Y)
      .setSize(40, elementHeight)
      .setAutoClear(false)                          // keep the text after Enter (default blanks it)
      .setText(nf(colorPipeline.gamma, 1, 2))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          float g = float(gammaField.getText());
          if (!Float.isNaN(g)) colorPipeline.setGamma(g);
          // Reflect the applied (clamped) value back into the field. setText
          // doesn't re-fire onChange, so no recursion.
          gammaField.setText(nf(colorPipeline.gamma, 1, 2));
        }
      });
    gammaField.setCaptionLabel("GAMMA");

    modeButton = cp5.addButton("modeButton")
      .setPosition(col1, row4Y)
      .setSize(150, elementHeight)
      .setColorCaptionLabel(textColor)
      .onClick(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          colorPipeline.cycleMode();
          modeButton.setCaptionLabel("MODE: " + colorPipeline.getModeName());
        }
      });
    modeButton.setCaptionLabel("MODE: " + colorPipeline.getModeName());

    // ===== TOP-RIGHT: Art-Net cluster =====
    sepX         = x + 242;             // vertical separator between L / R
    int anX      = sepX + 10;           // right region left edge
    int anLabelY = row1Y;
    int anRow1Y  = row1Y + 22;          // BCAST + IP + PORT
    int anRow2Y  = anRow1Y + 36;        // SUBNET + UNIV + START/STOP

    cp5.addTextlabel("artnetLabel")
      .setText("ARTNET DMX")
      .setPosition(anX, anLabelY)
      .setColor(textColor);

    // IP field is created BEFORE the broadcast toggle so the toggle's initial
    // setValue() can dim/lock it through updateIPField() without a null ref.
    ipField = cp5.addTextfield("ipField")
      .setPosition(anX + 32, anRow1Y)
      .setSize(110, elementHeight)
      .setText(targetIP)
      .setColor(textColor)
      .setColorCaptionLabel(textColor);
    ipField.setCaptionLabel("TARGET IP");

    portField = cp5.addTextfield("portField")
      .setPosition(anX + 150, anRow1Y)
      .setSize(48, elementHeight)
      .setText(str(artNetPort))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .setInputFilter(ControlP5.INTEGER);
    portField.setCaptionLabel("PORT");

    broadcastToggle = cp5.addToggle("broadcastToggle")
      .setPosition(anX, anRow1Y)
      .setSize(elementHeight, elementHeight)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          useBroadcast = event.getController().getValue() > 0;
          updateIPField();
        }
      });
    broadcastToggle.setCaptionLabel("BCAST");
    broadcastToggle.setValue(useBroadcast ? 1 : 0);   // fires onChange -> initial IP lock/dim

    subnetField = cp5.addTextfield("subnetField")
      .setPosition(anX, anRow2Y)
      .setSize(34, elementHeight)
      .setText(str(subnet))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .setInputFilter(ControlP5.INTEGER);
    subnetField.setCaptionLabel("SUBNET");

    universeField = cp5.addTextfield("universeField")
      .setPosition(anX + 52, anRow2Y)
      .setSize(34, elementHeight)
      .setText(str(universe))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .setInputFilter(ControlP5.INTEGER);
    universeField.setCaptionLabel("UNIV");

    dmxToggle = cp5.addToggle("dmxToggle")
      .setPosition(anX + 128, anRow2Y)
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

    // ===== TOP-RIGHT: MQTT cluster (below the Art-Net cluster) =====
    int mqLabelY = y + 116;
    int mqRowY   = y + 138;             // MQTT toggle + BROKER IP + PORT

    cp5.addTextlabel("mqttLabel")
      .setText("MQTT SYNC")
      .setPosition(anX, mqLabelY)
      .setColor(textColor);

    // Host field created BEFORE the toggle so the toggle's initial setValue()
    // can lock/dim it via updateMqttFieldsLock() without a null ref (same
    // pattern as ipField / broadcastToggle).
    mqttHostField = cp5.addTextfield("mqttHostField")
      .setPosition(anX + 32, mqRowY)
      .setSize(110, elementHeight)
      .setText(mqttHost)
      .setColor(textColor)
      .setColorCaptionLabel(textColor);
    mqttHostField.setCaptionLabel("BROKER IP");

    mqttPortField = cp5.addTextfield("mqttPortField")
      .setPosition(anX + 150, mqRowY)
      .setSize(48, elementHeight)
      .setText(str(mqttPort))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .setInputFilter(ControlP5.INTEGER);
    mqttPortField.setCaptionLabel("PORT");

    mqttToggle = cp5.addToggle("mqttToggle")
      .setPosition(anX, mqRowY)
      .setSize(elementHeight, elementHeight)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (uiSyncing) return;
          if (event.getController().getValue() > 0) startMQTT();
          else                                      stopMQTT();
        }
      });
    mqttToggle.setCaptionLabel("ENABLE");
    mqttToggle.setValue(enableMQTT ? 1 : 0);   // default ON -> fires onChange -> startMQTT (connect) + field lock

    // ===== MIRROR cluster (right half of the panel; full relay out is 12b) =====
    // Per-container H/V flip. R = right/main, L = left/clone. UI-only (no keys).
    int mirX      = x + 520;
    int mirLabelY = y + padding;        // aligns with the Art-Net label row
    int mirRow1Y  = mirLabelY + 22;     // RIGHT: H / V
    int mirRow2Y  = mirRow1Y + 36;      // LEFT:  H / V
    int mirPitch  = 56;

    cp5.addTextlabel("mirrorLabel")
      .setText("MIRROR (R / L)")
      .setPosition(mirX, mirLabelY)
      .setColor(textColor);

    rMirrorHToggle = cp5.addToggle("rMirrorHToggle")
      .setPosition(mirX, mirRow1Y)
      .setSize(elementHeight, elementHeight)
      .setValue(rightContainer.mirrorH)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (uiSyncing) return;
          rightContainer.setMirrorH(event.getController().getValue() > 0);
        }
      });
    rMirrorHToggle.setCaptionLabel("R-H");

    rMirrorVToggle = cp5.addToggle("rMirrorVToggle")
      .setPosition(mirX + mirPitch, mirRow1Y)
      .setSize(elementHeight, elementHeight)
      .setValue(rightContainer.mirrorV)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (uiSyncing) return;
          rightContainer.setMirrorV(event.getController().getValue() > 0);
        }
      });
    rMirrorVToggle.setCaptionLabel("R-V");

    lMirrorHToggle = cp5.addToggle("lMirrorHToggle")
      .setPosition(mirX, mirRow2Y)
      .setSize(elementHeight, elementHeight)
      .setValue(leftContainer.mirrorH)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (uiSyncing) return;
          leftContainer.setMirrorH(event.getController().getValue() > 0);
        }
      });
    lMirrorHToggle.setCaptionLabel("L-H");

    lMirrorVToggle = cp5.addToggle("lMirrorVToggle")
      .setPosition(mirX + mirPitch, mirRow2Y)
      .setSize(elementHeight, elementHeight)
      .setValue(leftContainer.mirrorV)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
        public void controlEvent(CallbackEvent event) {
          if (uiSyncing) return;
          leftContainer.setMirrorV(event.getController().getValue() > 0);
        }
      });
    lMirrorVToggle.setCaptionLabel("L-V");

    // ===== Console rect (full width, bottom) =====
    int hDivY = y + 184;                // horizontal separator above console (clears the color + Art-Net + MQTT rows)
    consoleX = col1;
    consoleY = hDivY + 6;
    consoleW = width - padding * 2;
    consoleH = (y + height - padding - 16) - consoleY;
  }

  // -------------------------------------------------------------
  // Keyboard -> UI sync
  // -------------------------------------------------------------

  void syncToggles() {
    uiSyncing = true;
    gridToggle.setValue(ringGrid.gridEnabled ? 1 : 0);
    labelsToggle.setValue(ringGrid.labelsEnabled ? 1 : 0);
    previewToggle.setValue(ringGrid.previewEnabled ? 1 : 0);
    uiSyncing = false;
  }

  void syncN() {
    nSlider.setValue(ringGrid.N);
  }

  // Push the color pipeline state back into its controls after a hotkey change
  // (M / [ / ]). The brightness slider is guarded so it doesn't re-fire.
  void syncColorControls() {
    uiSyncing = true;
    if (brightnessSlider != null) brightnessSlider.setValue(colorPipeline.brightness * 100.0);
    uiSyncing = false;
    if (gammaField != null) gammaField.setText(nf(colorPipeline.gamma, 1, 2));
    if (modeButton != null) modeButton.setCaptionLabel("MODE: " + colorPipeline.getModeName());
  }

  // True if any editable text field currently has keyboard focus. The main
  // sketch checks this at the top of keyPressed() and bails, so typing (incl.
  // Backspace) in a field isn't ALSO interpreted as a global hotkey — otherwise
  // Backspace in the GAMMA/IP/etc. field would clear the loaded video.
  boolean isTextfieldFocused() {
    return (ipField       != null && ipField.isFocus())
        || (portField     != null && portField.isFocus())
        || (subnetField   != null && subnetField.isFocus())
        || (universeField != null && universeField.isFocus())
        || (gammaField    != null && gammaField.isFocus())
        || (mqttHostField != null && mqttHostField.isFocus())
        || (mqttPortField != null && mqttPortField.isFocus());
  }

  // -------------------------------------------------------------
  // Art-Net (phase 6b) — fields drive the globals; START (re)builds the sender
  // from the current values so an ESP32 can be retargeted without code edits.
  // -------------------------------------------------------------

  // Broadcast mode pins the IP to 255.255.255.255 and locks/dims the field;
  // unicast mode unlocks it for a real ESP32 address.
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

    logOk("[artnet] START -> " + (useBroadcast ? "broadcast" : targetIP)
      + ":" + artNetPort + ", universe " + universe + ", subnet " + subnet
      + " (" + (ringGrid.N * 3) + " ch active)");

    publishRingConfig();   // universe/subnet may have changed — keep receiver in sync
  }

  // Blackout the ring, flush, and tear down. enableDMX off; a following START
  // rebuilds the sender, so this also covers retargeting cleanly.
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
  // MQTT — the toggle (re)connects / disconnects; host & port are editable only
  // while it's OFF (locked + dimmed when ON, same model as the broadcast IP).
  // -------------------------------------------------------------

  // Lock + dim (or unlock + restore) a text field. Shared by the MQTT fields.
  void lockField(Textfield f, boolean locked) {
    if (f == null) return;
    f.setLock(locked);
    f.setColorBackground(locked ? disabledColor : color(60));
    f.setColor(locked ? dimmedTextColor : textColor);
  }

  void updateMqttFieldsLock() {
    lockField(mqttHostField, enableMQTT);   // ON = locked, OFF = editable
    lockField(mqttPortField, enableMQTT);
  }

  // Pull host/port from the fields and (re)connect. clientConnected() then flips
  // mqttReady on and publishes the retained config. Non-fatal: a missing broker
  // just logs a warning — Art-Net is unaffected. (connect() blocks ~2 s then
  // throws when there's no broker.)
  void startMQTT() {
    mqttHost = mqttHostField.getText().trim();
    if (mqttHost.length() == 0) mqttHost = "localhost";
    mqttPort = parseInt(mqttPortField.getText());
    enableMQTT = true;
    updateMqttFieldsLock();
    try {
      if (mqtt == null) mqtt = new MQTTClient(parent);
      else { try { mqtt.disconnect(); } catch (Exception ignore) { } }   // drop old session first
      mqttReady = false;
      mqtt.connect(mqttBrokerURI(), "ring_eye_sim_server");
      logOk("[mqtt] connecting -> " + mqttBrokerURI());
    } catch (Exception e) {
      mqttReady = false;
      logWarn("[mqtt] no broker at " + mqttBrokerURI() + " — toggle ENABLE off/on to retry. (Art-Net unaffected.)");
    }
  }

  void stopMQTT() {
    enableMQTT = false;
    updateMqttFieldsLock();
    if (mqtt != null) { try { mqtt.disconnect(); } catch (Exception ignore) { } }
    mqttReady = false;
    log("[mqtt] disconnected (sync off)");
  }

  // -------------------------------------------------------------
  // FPS readout
  // -------------------------------------------------------------

  void setFps(float fps) {
    displayFps = fps;
  }

  // -------------------------------------------------------------
  // Console — custom colored log (per-line color; drawn in render()).
  // -------------------------------------------------------------

  void printToConsole(String message) {
    printToConsole(message, cInfo);
  }

  void printToConsole(String message, color c) {
    conLines.add(message);
    conColors.add(c);
    while (conLines.size() > CONSOLE_BUFFER_LIMIT) {
      conLines.remove(0);
      conColors.remove(0);
    }
  }

  // -------------------------------------------------------------
  // Render — panel bg, separators, custom console, FPS. ControlP5 draws its
  // own controls on top automatically after draw() returns.
  // -------------------------------------------------------------

  void render() {
    fill(bgColor);
    noStroke();
    rect(x, y, width, height);

    // Top boundary (canvas | panel)
    stroke(60);
    strokeWeight(1);
    line(x, y, x + width, y);

    // Light separators: vertical (left controls | art-net) + horizontal (above console)
    stroke(textColor, 55);
    strokeWeight(1);
    line(sepX, y + 8, sepX, consoleY - 8);
    line(x + padding, consoleY - 6, x + width - padding, consoleY - 6);
    noStroke();

    // ----- custom colored console (newest line at the bottom) -----
    fill(18);
    rect(consoleX, consoleY, consoleW, consoleH);

    textAlign(LEFT, BOTTOM);
    textSize(11);
    float lh = 14;
    float ty = consoleY + consoleH - 4;
    for (int i = conLines.size() - 1; i >= 0; i--) {
      if (ty < consoleY + lh - 2) break;          // ran out of vertical room
      fill(conColors.get(i));
      text(conLines.get(i), consoleX + 6, ty);
      ty -= lh;
    }

    // FPS readout — bottom-left strip, below the console
    fill(textColor);
    textAlign(LEFT, BOTTOM);
    textSize(12);
    text("FPS: " + nf(displayFps, 0, 1), x + padding, y + height - padding);
  }
}
