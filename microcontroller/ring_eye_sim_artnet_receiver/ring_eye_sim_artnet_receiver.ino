#include <Adafruit_NeoPixel.h>
#include <ArtnetWiFi.h>  // for chips that has wifi
// #include <Artnet.h>     // can use both WiFi and Ethernet

// LED stuff
#define LED_PIN 2     // ESP32 GPIO14 connects to LED data input
#define LED_COUNT 12  // 8x8 matrix = 64 LEDs
Adafruit_NeoPixel pixels(LED_COUNT, LED_PIN, NEO_GRB + NEO_KHZ800);

void initNeoPixelLEDs() {
  pixels.begin();             // Initialize NeoPixel strip
  pixels.setBrightness(127);  // Set brightness (max 255)
  pixels.clear();             // Set all pixels to 'off'
}


unsigned long prevWiFiBlinkMillis = 0;
bool wifiLEDState = false;
const int wifiLEDPin = 8;  // ESP32 C3 Super Mini on-board LED (works with inverted logic)

void initWiFiLED() {
  pinMode(wifiLEDPin, OUTPUT);
}

void showWiFiConnecting() {
  unsigned long currWiFiBlinkMillis = millis();
  if (currWiFiBlinkMillis - prevWiFiBlinkMillis >= 100) {
    prevWiFiBlinkMillis = currWiFiBlinkMillis;
    wifiLEDState = !wifiLEDState;
    if (wifiLEDState) {
      digitalWrite(wifiLEDPin, LOW);  // ON (works with inverted logic for this board)
    } else {
      digitalWrite(wifiLEDPin, HIGH);  // OFF (works with inverted logic for this board)
    }
  }
}


void showWiFiConnected() {
  digitalWrite(wifiLEDPin, LOW);  // ON (works with inverted logic for this board)
  delay(2500);
  digitalWrite(wifiLEDPin, HIGH);  // OFF (works with inverted logic for this board)
}

// WiFi& Artnet stuff
const char *ssid = "***REMOVED***";
const char *pwd = "***REMOVED***";

// const IPAddress ip(192, 168, 1, 201); // Adjust based on your router's DNS Settings
// // const IPAddress ip(192, 168, 1, 202); // Adjust based on your router's DNS Settings; **but give the send setup a diff IP

// const IPAddress gateway(192, 168, 1, 1); // Adjust based on your router's DNS Settings
// const IPAddress subnet_mask(255, 255, 255, 0);  // Adjust based on your router's DNS Settings

// ArtnetWiFiReceiver artnet;

// uint16_t universe0 = 0;  // 0 - 32767
// uint8_t net = 0;         // 0 - 127
// uint8_t subnet = 0;      // 0 - 15

void setup() {
  initWiFiLED();
  initNeoPixelLEDs();

  Serial.begin(115200);
  delay(2000);

  // WiFi stuff
  Serial.print("Connecting to Wifi:\t");
  Serial.println(ssid);

  WiFi.begin(ssid, pwd);
  // WiFi.config(ip, gateway, subnet_mask);

  while (WiFi.status() != WL_CONNECTED) {
    showWiFiConnecting();
    Serial.print(".");
    delay(1000);
  }

  showWiFiConnected();

  Serial.println("\n");
  Serial.print("WiFi connected, IP = ");
  Serial.println(WiFi.localIP());

  delay(1000);
}

void loop() {
  for (int i = 0; i < LED_COUNT; i++) {
    pixels.clear();

    uint8_t red = 127;
    uint8_t green = 0;
    uint8_t blue = 0;

    pixels.setPixelColor(i, pixels.Color(red, green, blue));
    pixels.show();
    delay(1000);
  }
}
