// tailored_dmx_receiver — preview "NeoPixel ring" that mirrors the output of
// ring_eye_sim_artnet_sender.
//   - PIXELS arrive over Art-Net DMX (subnet/universe synced below). The bytes
//     are already post gamma/brightness, so this is an accurate hardware preview.
//   - LAYOUT (N + universe/subnet) arrives over MQTT topic "ring/config"
//     (retained), so the ring follows the server live. Geometry mirrors the
//     server's RingGrid: ringR = w*350/1024,
//     cellSize = 2*ringR*sin(PI/N)/(1+sin(PI/N))*0.95, LED 0 at 12 o'clock CW.
//
// Start order: mosquitto -> server -> receiver (retained config = instant sync).
// Keys: L toggles labels.

import ch.bildspur.artnet.*;
import mqtt.*;

// ---- transport ----
ArtNetClient artnet;
MQTTClient   mqtt;
boolean      mqttReady = false;

final String MQTT_BROKER       = "mqtt://localhost:1883";
final String MQTT_TOPIC_CONFIG = "ring/config";

// ---- ring layout (synced from the server) ----
int N        = 12;
int universe = 0;
int subnet   = 0;

// ---- derived geometry (rebuilt on N change) ----
float   ringR, cellSize;
float[] cx, cy;     // disc centers
float[] lx, ly;     // label centers

// ---- display ----
boolean showLabels = true;

void settings() {
  size(480, 480);
  // No pixelDensity(1) here: this sketch never reads pixels[], so let high-DPI
  // render the discs crisp.
}

void setup() {
  surface.setTitle("tailored_dmx_receiver");
  textAlign(CENTER, CENTER);

  artnet = new ArtNetClient();
  artnet.start();

  rebuildLayout();

  // MQTT (optional). connect() blocks ~2 s then throws if no broker is up, so
  // it's guarded — the receiver still renders (with the default/last N) without
  // a broker. Subscription is done in clientConnected() so it survives reconnects.
  try {
    mqtt = new MQTTClient(this);
    mqtt.connect(MQTT_BROKER, "ring_receiver");
  } catch (Exception e) {
    println("[mqtt] no broker at " + MQTT_BROKER + " — using default N=" + N
      + ". Start mosquitto and relaunch for live sync.");
  }
}

// ---- MQTT callbacks (invoked on the main thread via a post-draw hook) ----

// Fired on every (re)connect — (re)subscribe so it survives auto-reconnects.
void clientConnected() {
  mqttReady = true;
  try { mqtt.subscribe(MQTT_TOPIC_CONFIG, 1); }
  catch (Exception e) { println("[mqtt] subscribe failed: " + e.getMessage()); }
  println("[mqtt] connected + subscribed " + MQTT_TOPIC_CONFIG);
}

void connectionLost() {
  mqttReady = false;
  println("[mqtt] connection lost (auto-reconnecting)");
}

// Render-safe (main thread). Parse {n, universe, subnet}; rebuild on N change.
void messageReceived(String topic, byte[] payload) {
  if (!MQTT_TOPIC_CONFIG.equals(topic)) return;
  JSONObject j = parseJSONObject(new String(payload));
  if (j == null) return;
  universe = j.getInt("universe", universe);
  subnet   = j.getInt("subnet",   subnet);
  int newN = j.getInt("n", N);
  if (newN >= 1 && newN != N) {
    N = newN;
    rebuildLayout();
    println("[ring] N=" + N + "  U" + universe + " S" + subnet);
  }
}

// Mirror the server's RingGrid geometry for the current N.
void rebuildLayout() {
  ringR = width * (350.0 / 1024.0);
  float s = sin(PI / N);
  cellSize = 2.0 * ringR * s / (1.0 + s) * 0.95;

  cx = new float[N];  cy = new float[N];
  lx = new float[N];  ly = new float[N];

  float ccx = width / 2.0, ccy = height / 2.0;
  float labelR = ringR + cellSize / 2.0 + constrain(cellSize * 0.2, 8, 20);
  for (int i = 0; i < N; i++) {
    float phi = i * TWO_PI / N;
    cx[i] = ccx + ringR * sin(phi);
    cy[i] = ccy - ringR * cos(phi);
    lx[i] = ccx + labelR * sin(phi);
    ly[i] = ccy - labelR * cos(phi);
  }
}

void draw() {
  background(18);

  byte[] data = artnet.readDmxData(subnet, universe);   // latest frame, or null

  // faint centerline ring outline
  noFill();
  stroke(55);
  strokeWeight(1);
  ellipse(width / 2.0, height / 2.0, ringR * 2, ringR * 2);

  textSize(constrain(cellSize * 0.28, 8, 16));
  for (int i = 0; i < N; i++) {
    int r = 0, g = 0, b = 0;
    int base = i * 3;
    if (data != null && base + 2 < data.length) {
      r = data[base]     & 0xFF;
      g = data[base + 1] & 0xFF;
      b = data[base + 2] & 0xFF;
    }
    // LED disc
    noStroke();
    fill(r, g, b);
    ellipse(cx[i], cy[i], cellSize, cellSize);
    // thin rim so dark / black LEDs stay visible against the background
    noFill();
    stroke(70);
    strokeWeight(1);
    ellipse(cx[i], cy[i], cellSize, cellSize);
    // index label
    if (showLabels) {
      noStroke();
      fill(170);
      text(i, lx[i], ly[i]);
    }
  }

  drawHud(data != null);
}

void drawHud(boolean haveDmx) {
  noStroke();
  fill(150);
  textAlign(LEFT, TOP);
  textSize(11);
  text("N=" + N + "  U" + universe + " S" + subnet
     + "   DMX " + (haveDmx ? "ok" : "waiting")
     + "   MQTT " + (mqttReady ? "ok" : "off")
     + "   " + nf(frameRate, 0, 0) + " fps", 8, 8);
  textAlign(CENTER, CENTER);   // restore for the disc labels next frame
}

void keyPressed() {
  if (key == 'l' || key == 'L') showLabels = !showLabels;
}
