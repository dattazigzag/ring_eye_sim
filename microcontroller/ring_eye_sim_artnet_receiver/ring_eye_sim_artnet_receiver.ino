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
