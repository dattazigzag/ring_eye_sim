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
  color accentColor      = color(217, 119, 87);   // ~#D97757 — Anthropic clay-orange: the single accent (sliders, toggles ON, "main" label, canvas marker)
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
  Toggle screenToggle;     // Extension A — screen-capture input source (SOURCE / VIEW row)
  Toggle gridToggle;
  Toggle labelsToggle;
  Toggle previewToggle;

  // Art-Net controls — shared transport (phase 6b) + per-eye target (phase 12b)
  Textfield portField;
  Textfield subnetField;
  Toggle    broadcastToggle;
  Toggle    dmxToggle;            // START/STOP DMX (caption flips with state)
  Textfield rUnivField, lUnivField;   // per-eye universe (right=main, left=clone)
  Textfield rIpField, lIpField;     // per-eye unicast IP (locked under broadcast)

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
    cp5.setColorActive(accentColor);   // toggles + sliders light up in the accent (Anthropic orange)

    int col1  = x + padding;            // gutter: row tags + console
    int chipX = x + 104;                // shared-band controls start after the tag gutter

    // ===== SHARED band: row1 = source/view, row2 = color =====
    int row1Y = y + 34;                 // open video + grid/labels/preview + N
    int row2Y = y + 72;                 // bright + gamma + mode

    cp5.addTextlabel("tagSource").setText("SOURCE / VIEW").setPosition(col1, row1Y + 5).setColor(textColor);
    cp5.addTextlabel("tagColor").setText("COLOR").setPosition(col1, row2Y + 5).setColor(textColor);

    cp5.addButton("openVideoBtn")
      .setPosition(chipX, row1Y)
      .setSize(84, elementHeight)
      .setColorCaptionLabel(textColor)
      .onClick(new CallbackListener() {
      public void controlEvent(CallbackEvent event) {
        openFilePicker();
      }
    }
    );
    cp5.getController("openVideoBtn").setCaptionLabel("OPEN VIDEO");

    int togPitch = 46;                  // tight, grouped spacing
    int srcX     = chipX + 96;          // SCREEN source toggle — just right of OPEN VIDEO
    int togX     = srcX + togPitch;     // view toggles start one pitch past SCREEN

    // SCREEN — screen-capture input source (Extension A), an alternative to
    // video. onChange starts/stops the grabber via MediaHandler (mutually
    // exclusive with video). Kept in sync with the 'D' hotkey + video-load via
    // syncSourceToggle().
    screenToggle = cp5.addToggle("screenToggle")
      .setPosition(srcX, row1Y)
      .setSize(elementHeight, elementHeight)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
      public void controlEvent(CallbackEvent event) {
        if (uiSyncing) return;
        if (event.getController().getValue() > 0) mediaHandler.startScreenCapture();
        else                                      mediaHandler.stopScreenCapture();
      }
    }
    );
    screenToggle.setCaptionLabel("SCREEN");

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
    }
    );
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
    }
    );
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
    }
    );
    previewToggle.setCaptionLabel("PREVIEW");

    // N slider — shortened; caption to the RIGHT; fill always visible (accent
    // foreground) so it reads at the default value without hovering.
    nSlider = cp5.addSlider("nSlider")
      .setPosition(chipX + 260, row1Y)
      .setSize(160, elementHeight)
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
    }
    );
    nSlider.getCaptionLabel()
      .align(ControlP5.RIGHT_OUTSIDE, ControlP5.CENTER)
      .setPaddingX(8)
      .setText("PIXELS (N)")
      .setColor(textColor);

    // ----- Color pipeline (phase 7): BRIGHT % + GAMMA + MODE on the color row -----
    brightnessSlider = cp5.addSlider("brightnessSlider")
      .setPosition(chipX, row2Y)
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
    }
    );
    brightnessSlider.getCaptionLabel()
      .align(ControlP5.RIGHT_OUTSIDE, ControlP5.CENTER)
      .setPaddingX(8)
      .setText("BRIGHT %")
      .setColor(textColor);

    gammaField = cp5.addTextfield("gammaField")
      .setPosition(chipX + 200, row2Y)
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
    }
    );
    gammaField.setCaptionLabel("GAMMA");

    modeButton = cp5.addButton("modeButton")
      .setPosition(chipX + 260, row2Y)
      .setSize(160, elementHeight)
      .setColorCaptionLabel(textColor)
      .onClick(new CallbackListener() {
      public void controlEvent(CallbackEvent event) {
        colorPipeline.cycleMode();
        modeButton.setCaptionLabel("MODE: " + colorPipeline.getModeName());
      }
    }
    );
    modeButton.setCaptionLabel("MODE: " + colorPipeline.getModeName());

    // ===== SHARED band: row3 = ART-NET transport (bcast / port / subnet / start) =====
    int row3Y = y + 110;
    cp5.addTextlabel("tagArtnet").setText("ART-NET").setPosition(col1, row3Y + 5).setColor(textColor);

    broadcastToggle = cp5.addToggle("broadcastToggle")
      .setPosition(chipX, row3Y)
      .setSize(elementHeight, elementHeight)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
      public void controlEvent(CallbackEvent event) {
        useBroadcast = event.getController().getValue() > 0;
        updateIPField();                       // locks/unlocks BOTH eye IP fields
      }
    }
    );
    broadcastToggle.setCaptionLabel("BCAST");

    portField = cp5.addTextfield("portField")
      .setPosition(chipX + 70, row3Y)
      .setSize(48, elementHeight)
      .setText(str(artNetPort))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .setInputFilter(ControlP5.INTEGER);
    portField.setCaptionLabel("PORT");

    subnetField = cp5.addTextfield("subnetField")
      .setPosition(chipX + 150, row3Y)
      .setSize(40, elementHeight)
      .setText(str(subnet))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .setInputFilter(ControlP5.INTEGER);
    subnetField.setCaptionLabel("SUBNET");

    dmxToggle = cp5.addToggle("dmxToggle")
      .setPosition(chipX + 200, row3Y)
      .setSize(elementHeight, elementHeight)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
      public void controlEvent(CallbackEvent event) {
        if (uiSyncing) return;                 // ignore programmatic sync from 'A'
        if (event.getController().getValue() > 0) startDMX();
        else                                      stopDMX();
        updateDmxCaption();
      }
    }
    );
    dmxToggle.setCaptionLabel("START DMX");

    // ===== SHARED band: row4 = MQTT (enable / broker / port) =====
    int row4Y = y + 148;
    cp5.addTextlabel("tagMqtt").setText("MQTT").setPosition(col1, row4Y + 5).setColor(textColor);

    mqttHostField = cp5.addTextfield("mqttHostField")
      .setPosition(chipX + 70, row4Y)
      .setSize(120, elementHeight)
      .setText(mqttHost)
      .setColor(textColor)
      .setColorCaptionLabel(textColor);
    mqttHostField.setCaptionLabel("BROKER IP");

    mqttPortField = cp5.addTextfield("mqttPortField")
      .setPosition(chipX + 200, row4Y)
      .setSize(48, elementHeight)
      .setText(str(mqttPort))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .setInputFilter(ControlP5.INTEGER);
    mqttPortField.setCaptionLabel("PORT");

    mqttToggle = cp5.addToggle("mqttToggle")
      .setPosition(chipX, row4Y)
      .setSize(elementHeight, elementHeight)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
      public void controlEvent(CallbackEvent event) {
        if (uiSyncing) return;
        if (event.getController().getValue() > 0) startMQTT();
        else                                      stopMQTT();
      }
    }
    );
    mqttToggle.setCaptionLabel("ENABLE");
    mqttToggle.setValue(enableMQTT ? 1 : 0);   // default ON -> fires onChange -> startMQTT (connect) + field lock

    // ===== PER-EYE band: two columns split at x+480 (echoes the canvas gap) =====
    // Each eye owns its FLIP H/V + UNIVERSE + IP on ONE row — flips on the left,
    // then UNIVERSE + IP in the column's spare width. Left = clone, right = main.
    int eyeHeadY  = y + 196;
    int flipY     = y + 226;        // single per-eye control row
    int addrY     = flipY;          // UNIVERSE + IP sit to the right of the flips
    int lColX     = x + 12;
    int rColX     = x + 492;
    int flipPitch = 50;

    cp5.addTextlabel("leftEyeLabel")
      .setText("LEFT EYE - clone")
      .setPosition(lColX, eyeHeadY)
      .setColor(textColor);
    cp5.addTextlabel("rightEyeLabel")
      .setText("RIGHT EYE - main")
      .setPosition(rColX, eyeHeadY)
      .setColor(accentColor);          // orange accent — ties to the on-canvas main marker

    // --- left eye (clone) ---
    lMirrorHToggle = cp5.addToggle("lMirrorHToggle")
      .setPosition(lColX, flipY)
      .setSize(elementHeight, elementHeight)
      .setValue(leftContainer.mirrorH)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
      public void controlEvent(CallbackEvent event) {
        if (uiSyncing) return;
        leftContainer.setMirrorH(event.getController().getValue() > 0);
      }
    }
    );
    lMirrorHToggle.setCaptionLabel("FLIP H");

    lMirrorVToggle = cp5.addToggle("lMirrorVToggle")
      .setPosition(lColX + flipPitch, flipY)
      .setSize(elementHeight, elementHeight)
      .setValue(leftContainer.mirrorV)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
      public void controlEvent(CallbackEvent event) {
        if (uiSyncing) return;
        leftContainer.setMirrorV(event.getController().getValue() > 0);
      }
    }
    );
    lMirrorVToggle.setCaptionLabel("FLIP V");

    lUnivField = cp5.addTextfield("lUnivField")
      .setPosition(lColX + 100, addrY)
      .setSize(44, elementHeight)
      .setText(str(leftContainer.universe))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .setInputFilter(ControlP5.INTEGER);
    lUnivField.setCaptionLabel("UNIVERSE");

    lIpField = cp5.addTextfield("lIpField")
      .setPosition(lColX + 168, addrY)
      .setSize(150, elementHeight)
      .setText(leftContainer.targetIP)
      .setColor(textColor)
      .setColorCaptionLabel(textColor);
    lIpField.setCaptionLabel("IP");

    // --- right eye (main) ---
    rMirrorHToggle = cp5.addToggle("rMirrorHToggle")
      .setPosition(rColX, flipY)
      .setSize(elementHeight, elementHeight)
      .setValue(rightContainer.mirrorH)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
      public void controlEvent(CallbackEvent event) {
        if (uiSyncing) return;
        rightContainer.setMirrorH(event.getController().getValue() > 0);
      }
    }
    );
    rMirrorHToggle.setCaptionLabel("FLIP H");

    rMirrorVToggle = cp5.addToggle("rMirrorVToggle")
      .setPosition(rColX + flipPitch, flipY)
      .setSize(elementHeight, elementHeight)
      .setValue(rightContainer.mirrorV)
      .setColorCaptionLabel(textColor)
      .onChange(new CallbackListener() {
      public void controlEvent(CallbackEvent event) {
        if (uiSyncing) return;
        rightContainer.setMirrorV(event.getController().getValue() > 0);
      }
    }
    );
    rMirrorVToggle.setCaptionLabel("FLIP V");

    rUnivField = cp5.addTextfield("rUnivField")
      .setPosition(rColX + 100, addrY)
      .setSize(44, elementHeight)
      .setText(str(rightContainer.universe))
      .setColor(textColor)
      .setColorCaptionLabel(textColor)
      .setInputFilter(ControlP5.INTEGER);
    rUnivField.setCaptionLabel("UNIVERSE");

    rIpField = cp5.addTextfield("rIpField")
      .setPosition(rColX + 168, addrY)
      .setSize(150, elementHeight)
      .setText(rightContainer.targetIP)
      .setColor(textColor)
      .setColorCaptionLabel(textColor);
    rIpField.setCaptionLabel("IP");

    // Both IP fields now exist — set the broadcast toggle's initial state; its
    // onChange locks/dims both eye IP fields via updateIPField().
    broadcastToggle.setValue(useBroadcast ? 1 : 0);

    // ===== Console rect (full width, bottom) =====
    int hDivY = y + 272;                // separator above console (below the single per-eye row)
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

  // Reflect the current input source (screen on/off) into the SCREEN toggle
  // without re-firing its onChange. Called from the 'D' hotkey and after a
  // video loads (which turns screen off). Guarded by uiSyncing.
  void syncSourceToggle() {
    if (screenToggle == null) return;
    uiSyncing = true;
    screenToggle.setValue(mediaHandler.isScreen ? 1 : 0);
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
    return (rIpField      != null && rIpField.isFocus())
      || (lIpField      != null && lIpField.isFocus())
      || (rUnivField    != null && rUnivField.isFocus())
      || (lUnivField    != null && lUnivField.isFocus())
      || (portField     != null && portField.isFocus())
      || (subnetField   != null && subnetField.isFocus())
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
    for (Textfield f : new Textfield[] { rIpField, lIpField }) {
      if (f == null) continue;                 // may not exist yet during setup
      if (useBroadcast) {
        f.setText("255.255.255.255");
        f.setLock(true);
        f.setColorBackground(disabledColor);
        f.setColor(dimmedTextColor);
      } else {
        f.setLock(false);
        f.setColorBackground(color(60));
        f.setColor(textColor);
      }
    }
  }

  // Pull the field values into each container, tear down any existing sender,
  // and build a fresh one so changed target/port/universe/subnet take effect.
  void startDMX() {
    artNetPort = parseInt(portField.getText());
    subnet     = parseInt(subnetField.getText());

    // Phase 12b: each eye owns its universe + IP from its column's fields.
    rightContainer.universe = parseInt(rUnivField.getText());
    leftContainer.universe  = parseInt(lUnivField.getText());
    rightContainer.targetIP = useBroadcast ? "255.255.255.255" : rIpField.getText().trim();
    leftContainer.targetIP  = useBroadcast ? "255.255.255.255" : lIpField.getText().trim();

    rightContainer.startSender(useBroadcast, rightContainer.targetIP, artNetPort, subnet, rightContainer.universe);
    leftContainer.startSender( useBroadcast, leftContainer.targetIP, artNetPort, subnet, leftContainer.universe);
    enableDMX = true;

    logOk("[artnet] START -> " + (useBroadcast ? "broadcast" : "unicast")
      + " port " + artNetPort + ", subnet " + subnet
      + "  | R=U" + rightContainer.universe + (useBroadcast ? "" : " " + rightContainer.targetIP)
      + "  | L=U" + leftContainer.universe  + (useBroadcast ? "" : " " + leftContainer.targetIP)
      + "  (" + (ringGrid.N * 3) + " ch/ring)");

    publishRingConfig();   // main (right) universe/subnet — keep the tester in sync
  }

  // Blackout the ring, flush, and tear down. enableDMX off; a following START
  // rebuilds the sender, so this also covers retargeting cleanly.
  void stopDMX() {
    // Blackout + tear down BOTH universes (right + left).
    for (VideoContainer c : containers) c.blackout(dmxData);
    delay(100);                        // let the packets flush
    for (VideoContainer c : containers) c.stopSender();
    enableDMX = false;
    log("[artnet] STOP (blackout sent on both universes)");
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
      else {
        try {
          mqtt.disconnect();
        }
        catch (Exception ignore) {
        }
      }   // drop old session first
      mqttReady = false;
      mqtt.connect(mqttBrokerURI(), "ring_eye_sim_server");
      logOk("[mqtt] connecting -> " + mqttBrokerURI());
    }
    catch (Exception e) {
      mqttReady = false;
      logWarn("[mqtt] no broker at " + mqttBrokerURI() + " — toggle ENABLE off/on to retry. (Art-Net unaffected.)");
    }
  }

  void stopMQTT() {
    enableMQTT = false;
    updateMqttFieldsLock();
    if (mqtt != null) {
      try {
        mqtt.disconnect();
      }
      catch (Exception ignore) {
      }
    }
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

    // Separators: shared-band underline, per-eye center split (echoes the canvas
    // gap), and the line above the console.
    stroke(textColor, 55);
    strokeWeight(1);
    line(x + padding, y + 182, x + width - padding, y + 182);          // shared | per-eye
    line(x + padding, consoleY - 6, x + width - padding, consoleY - 6); // per-eye | console
    for (float yy = y + 190; yy < y + 266; yy += 7) {                  // dashed center split
      line(x + 480, yy, x + 480, min(yy + 3, y + 266));
    }
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

    // Credit — bottom-right, mirrors the FPS readout on the left
    fill(dimmedTextColor);
    textAlign(RIGHT, BOTTOM);
    textSize(11);
    text("CREATED BY SAURABH DATTA (zigzag.is)", x + width - padding, y + height - padding);
    textAlign(LEFT, BASELINE);   // restore Processing default for any later text()
  }
}
