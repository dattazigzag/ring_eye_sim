#include "config.h"
#include <Adafruit_NeoPixel.h>
#include <ArtnetWiFi.h>  // for chips that have WiFi
// #include <Artnet.h>   // can use both WiFi and Ethernet

// =============================================================
// ring_eye_sim - Art-Net receiver (RIGHT eye = universe 0)
// =============================================================
// Receives one DMX universe of ring pixels from the Processing sender
// (ring_eye_sim_artnet_sender) and drives a NeoPixel ring.
//
// Sender packing (RingGrid.writeToDMXBuffer):
//   LED i -> DMX channels [i*3, i*3+1, i*3+2] = R, G, B, starting at ch 0.
//   Colors are ALREADY gamma + brightness corrected by the sender's
//   ColorPipeline, so do NOT re-gamma here - just display them.
//   Sender pixel 0 = 12 o'clock, increasing CLOCKWISE.
// Art-Net address (data/config.json "artnet"): net 0, subnet 0,
//   universe 0 = RIGHT eye (left eye = universe 1). Sender broadcasts to
//   255.255.255.255:6454, so this board receives over broadcast; it also
//   works if the sender is switched to unicast at this board's static IP.
// =============================================================


// ---- WiFi -----------------------------------------------------
const char *ssid = WiFi_SSID;   // from config.h (keeps creds out of git)
const char *pwd  = WiFi_PASS;

// Static IP: needed if the sender ever UNICASTS to this board, and it makes the
// device findable. Must be UNIQUE on the LAN - different from the sender Mac
// and from the other eye's receiver. (Broadcast works even without this.)
const IPAddress ip(192, 168, 1, 229);
const IPAddress gateway(192, 168, 1, 1);
const IPAddress subnet_mask(255, 255, 255, 0);


// ---- WiFi status LED (onboard) --------------------------------
unsigned long prevWiFiBlinkMillis = 0;
bool wifiLEDState = false;
const int wifiLEDPin = 8;  // ESP32-C3 Super Mini onboard LED

void initWiFiLED() {
  pinMode(wifiLEDPin, OUTPUT);
}

void showWiFiConnecting() {
  unsigned long now = millis();
  if (now - prevWiFiBlinkMillis >= 100) {
    prevWiFiBlinkMillis = now;
    wifiLEDState = !wifiLEDState;
    digitalWrite(wifiLEDPin, wifiLEDState ? HIGH : LOW);
  }
}

void showWiFiConnected() {
  digitalWrite(wifiLEDPin, HIGH);
  delay(2500);
  digitalWrite(wifiLEDPin, LOW);
}


// ---- Art-Net --------------------------------------------------
ArtnetWiFiReceiver artnet;
uint16_t universe = 0;   // RIGHT eye. net0/subnet0/uni0 -> 15-bit address 0
uint8_t  net    = 0;      // 0 - 127  (must match sender)
uint8_t  subnet = 0;      // 0 - 15   (must match sender "artnet.subnet")


// ---- NeoPixel ring --------------------------------------------
// LED_PIN 0: NOTE GPIO0 is a BOOT strapping pin on the C3. A NeoPixel data line
//   idles LOW, which can disturb boot/flashing on some boards. If boots get
//   flaky, move the data line to another free GPIO (e.g. 2, 3, 4, 10).
#define LED_PIN    0
// LED_COUNT MUST equal the sender ring N (data/config.json "ring.n" = 12).
#define LED_COUNT  12
#define BRIGHTNESS 127   // hardware cap ON TOP of the sender's pipeline.
                         // 255 = exactly what the sender computed; lower to
                         // dim / limit current (eye displays sit close).
Adafruit_NeoPixel pixels(LED_COUNT, LED_PIN, NEO_GRB + NEO_KHZ800);

void initNeoPixelLEDs() {
  pixels.begin();
  pixels.setBrightness(BRIGHTNESS);
  pixels.clear();
  pixels.show();
}


// ---- Ring orientation (physical calibration) ------------------
// Sender pixel 0 = 12 o'clock, increasing CLOCKWISE. Your ring's data-in pixel
// and winding direction (and which face you view) probably differ, so map the
// sender's sample index -> physical pixel here. Tune on the bench:
//   1) leave OFFSET 0 / REVERSE false, run the sender, watch pixel 0.
//   2) if the ring runs the wrong way, set LED_REVERSE true.
//   3) rotate the start point with LED_OFFSET until physical pixel 0 lines up
//      with on-screen pixel 0.
#define LED_OFFSET   0       // 0 .. LED_COUNT-1
#define LED_REVERSE  false   // true = ring runs CCW relative to the sender

static inline int ringIndex(int sampleIdx) {
  int idx = LED_REVERSE ? (LED_COUNT - 1 - sampleIdx) : sampleIdx;
  idx = (idx + LED_OFFSET) % LED_COUNT;
  if (idx < 0) idx += LED_COUNT;
  return idx;
}


// ---- Debug ----------------------------------------------------
#define DEBUG_ARTNET 0   // 1 = print received frames/sec once per second
#if DEBUG_ARTNET
unsigned long frames = 0, lastReport = 0;
#endif


void setup() {
  initWiFiLED();
  initNeoPixelLEDs();

  Serial.begin(115200);
  delay(2000);

  Serial.print("Connecting to WiFi:\t");
  Serial.println(ssid);

  WiFi.begin(ssid, pwd);
  WiFi.config(ip, gateway, subnet_mask);   // static IP. If it won't take,
                                           // move this line ABOVE WiFi.begin().

  while (WiFi.status() != WL_CONNECTED) {
    showWiFiConnecting();
    Serial.print(".");
    delay(50);
  }

  showWiFiConnected();
  Serial.print("\nWiFi connected, IP = ");
  Serial.println(WiFi.localIP());
  delay(500);

  // Start Art-Net, listen for the RIGHT eye (universe 0).
  artnet.begin();

  // Sender net/subnet are both 0, so universe (=0) is the full Art-Net
  // address. If you ever change the sender's subnet/net, switch to the explicit
  // overload: artnet.subscribeArtDmxUniverse(net, subnet, universe, cb);
  artnet.subscribeArtDmxUniverse(universe,
    [&](const uint8_t *data, uint16_t size, const ArtDmxMetadata &metadata, const ArtNetRemoteInfo &remote) {
      int n = size / 3;                 // whole pixels present in this packet
      if (n > LED_COUNT) n = LED_COUNT;

      pixels.clear();                   // unwritten pixels go dark (no stale)
      for (int i = 0; i < n; i++) {
        int base = i * 3;
        pixels.setPixelColor(
          ringIndex(i),
          pixels.Color(data[base], data[base + 1], data[base + 2])  // R, G, B
        );
      }
      pixels.show();

      #if DEBUG_ARTNET
      frames++;
      #endif
    });

  Serial.println("Art-Net ready: listening for universe 0 (right eye).");
}


void loop() {
  artnet.parse();   // poll UDP; the callback runs when a packet arrives

  #if DEBUG_ARTNET
  unsigned long now = millis();
  if (now - lastReport >= 1000) {
    Serial.printf("[artnet] %lu fps\n", frames);
    frames = 0;
    lastReport = now;
  }
  #endif
}
