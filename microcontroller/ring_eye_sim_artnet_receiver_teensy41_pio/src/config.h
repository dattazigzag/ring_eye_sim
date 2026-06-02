/**
 * @brief
 *
 */

// ------------------------------------------------------------------------------------------------------------ //
// Enable/disable Serial print functionalities
// ------------------------------------------------------------------------------------------------------------ //
// Un-commenting => Enables and comment out => Disables, Serial interface for messages (e.g: for debug logs)
// #define DEBUG

// ------------------------------------------------------------------------------------------------------------ //
// For SSD1306 OLED 128x32 screen related
// ------------------------------------------------------------------------------------------------------------ //
#define OLED_RESET_PIN 17                    // Reset pin # (or -1 if sharing Arduino reset pin)
uint8_t SSD1306_ADDRESSES[2] = {0x3c, 0x3D}; // LUT for ssd1306 oled displays, used to validate discovered addr.
uint8_t OLED_SCREEN_ADDRESS = 0x3C;          //< See datasheet for Address; 0x3D for 128x64, 0x3C for 128x32
// On board OLED display's parameters (for our SSD1306-128x32)
// Note: If you are using another SSD1306 screen resolution, say 128x64, then change the screen height ...
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 32

// ------------------------------------------------------------------------------------------------------------ //
// ------ NEOPIXEL / WS281x LED STRIP SETTINGS ------ //
// ------------------------------------------------------------------------------------------------------------ //
#define ledsPerStrip 12                    // LEDs per ring/port (one Art-Net universe per port; max 170)
const byte numLEDStripsPerStripSocket = 1; // strips chained per port socket
const int channelsPerLed = 3;              // 3 = RGB/GRB, 4 = RGBW/GRBW

// PCB ports. Port 1 = strips[0] = pin 24, Port 2 = strips[1] = pin 25, Port 3 = pin 26, Port 4 = pin 27.
const int  totalLEDStrips                = 4;
const byte stripPins[totalLEDStrips]     = {24, 25, 26, 27};
// Which ports are populated (1 = enabled).
bool       stripsEnabled[totalLEDStrips] = {1, 1, 0, 0};

// Physical pixel color order. NEO_GRB for most rings; switch to NEO_RGB if red/green look swapped.
// (Expanded where the strips are constructed, after Adafruit_NeoPixel.h is included.)
#define STRIP_COLOR_ORDER NEO_GRB

// Per-port ring-zero calibration. Wired in a later phase; zeros = no change for now.
// LED_OFFSET rotates each ring's start pixel; LED_REVERSE flips its CW/CCW direction.
int  LED_OFFSET[totalLEDStrips]  = {-1, -1, 0, 0};
bool LED_REVERSE[totalLEDStrips] = {0, 0, 0, 0};

// ------------------------------------------------------------------------------------------------------------ //
// For Art-Net DMX library
// ------------------------------------------------------------------------------------------------------------ //
// Explicit per-port universe map (absolute Art-Net universe numbers — no arithmetic).
// Port N (strips[N]) listens to portUniverse[N]; only ports enabled above are driven.
//   Default {0,1,2,3}: Port1<-U0, Port2<-U1, Port3<-U2, Port4<-U3.
//   Example {2,3,0,0} with stripsEnabled {1,1,0,0}: sender on U2/U3 -> rings on Ports 1 & 2.
//   Two ports mapped to the same universe mirror it.
int portUniverse[totalLEDStrips] = {0, 1, 2, 3};

// Optional global "master dimmer" universe (e.g. for Resolume / QLC+ / MadMapper master fader).
// When defined, an Art-Net packet on this universe sets hardware brightness on all enabled strips
// from data[0]. Leave COMMENTED for the ring_eye_sim sender, whose pixels are already
// brightness-corrected (enabling it would double-dim). Uncomment to expose it for other software.
// #define MASTER_DIMMER_UNIVERSE 15

// --- Network mode (declared here as the single source of truth; wired into network.h in a later phase) ---
//   USE_STATIC_IP defined  => try fixedIP first, then fall back to DHCP, then signal + stop.
//   USE_STATIC_IP commented => DHCP only, then signal + stop.

#define USE_STATIC_IP
#define STATIC_LINK_TIMEOUT_MS 8000  // ms to wait for cable link when using a static IP
#define DHCP_TIMEOUT_MS        12000 // ms bounded wait per DHCP attempt
#define DHCP_RETRIES           2     // DHCP attempts before giving up

byte fixedIP[]   = {192, 168, 1, 230}; // static IP for this node (used when USE_STATIC_IP is set)
byte broadcast[] = {192, 168, 1, 255}; // subnet broadcast (ArtPoll-reply cosmetic only)

// ------------------------------------------------------------------------------------------------------------ //
// For On-board LEDs to show, according to our logic, if network interface was successful or not
// ------------------------------------------------------------------------------------------------------------ //
#define LED_PIN 9
