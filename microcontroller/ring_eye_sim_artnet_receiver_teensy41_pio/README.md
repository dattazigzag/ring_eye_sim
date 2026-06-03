# README

__Platform:__ Teensy 4.1 @ 600MHz with Native Ethernet

An Art-Net → NeoPixel receiver for **two independent eye rings** on Teensy 4.1 (NativeEthernet + natcl Artnet), running on the custom 4-port PCB ("TeensyEthernetNeoPixel v21"). Each PCB port is driven by its own Art-Net universe through an explicit per-port map: by default **U0 → Port 1 (right eye)** and **U1 → Port 2 (left eye)**, 12 LEDs / 36 channels per ring. Network bring-up (static-then-DHCP, or DHCP-only) and every per-port behavior are set from one file — [`src/config.h`](#configuration-srcconfigh).

Pairs with the Processing `ring_eye_sim_artnet_sender`, which emits U0/U1 (broadcast or unicast to this node's IP on UDP 6454). Sender pixels are already gamma + brightness corrected, so this receiver does no color correction of its own — it writes the received bytes straight to the LEDs.

> [!Important]
> [Original Work](https://github.com/dattasaurabh82/ARTNET_TEENSY41_ETH_NEOPIXEL), _forked here and ported for neopixel rings (for our use case)_ 

---

## Hardware Setup

1. Schematic: [Schematic.pdf](https://github.com/dattasaurabh82/ARTNET_TEENSY41_ETH_NEOPIXEL/blob/main/Schematic.pdf)

![alt text](assets/164231916-6705f384-f0fe-4fe1-af7a-472f45dfab4b.png)

Simplified wiring:

![alt text](<assets/Untitled Sketch 3_bb.png>)

1. [GERBER](https://github.com/dattazigzag/ring_eye_sim/blob/main/microcontroller/ring_eye_sim_artnet_receiver_teensy41_pio/assets/GERBERS/TeensyEthernetNeoPixel%20v21%20v444_2022-04-11.zip)

![alt text](assets/164235523-db50fcdd-3af4-470b-9f34-19a7222f135f.png)
<img width="1678" alt="Screenshot 2022-05-09 at 11 23 33 AM" src="assets/167335416-20042251-5908-4861-87a3-e6d49e06f863.png">

## Development Environment Setup

### PIO specific instructions (from scratch) : 

  1. Needed to add manually Adafruit Busio lib from pio's library registry, to this project.
  2. Needed to add manually Adafruit GFX lib from pio's library registry, to this project.
  3. Needed to add manually Adafruit SSD1306 pio's library registry, to this project.
  4. In platformio.ini, in "lib_deps" section, add https://github.com/vjmuzik/NativeEthernet . (although is baked in Teensy System, but it might not be the latest)
  5. In platformio.ini, in "lib_deps" section, add https://github.com/natcl/Artnet . (May be available in pio lib registry, but it's not latest [as of Mar 20222])

  For 1st time:
  It will highlight in red complaining it can't find the following libraries in path, in some header files:
  ```c
    #include <Arduino.h>
    #include <SPI.h>
    #include <Wire.h>
    #include <Adafruit_GFX.h>
    #include <Adafruit_SSD1306.h>
   ```
  1. In vscode, in the appropriate header files, a small light bulb will appear, asking "Fix the quick way", do that (for both the libraries)
  2. Come back to main.cpp and compile, the errors would be gone.

---

#### Minimal [platformio.ini](https://github.com/dattasaurabh82/ARTNET_TEENSY41_ETH_NEOPIXEL/blob/main/platformio_alternative/teensy41_pio_artnet_demo/platformio.ini)

```yaml
[env:teensy41]
platform = teensy
board = teensy41
framework = arduino
board_build.mcu = imxrt1062
board_build.f_cpu = 600000000L ; max freq available on T4.1
monitor_speed = 115200
upload_protocol = teensy-cli ; teensy-gui is default also "jlink" is available
lib_deps = 
    SPI
    Wire
    https://github.com/vjmuzik/NativeEthernet
    https://github.com/natcl/Artnet
    adafruit/Adafruit NeoPixel@^1.10.4
    adafruit/Adafruit BusIO@^1.11.3
    adafruit/Adafruit GFX Library@^1.10.14
    adafruit/Adafruit SSD1306@^2.5.1
```

---

## Configuration (`src/config.h`)

Everything tunable lives in `src/config.h`. Edit → rebuild → upload. None of this touches the Processing sender.

| Setting | Default | What it controls / when to change |
|---|---|---|
| `stripsEnabled[4]` | `{1,1,0,0}` | Which PCB ports are driven (`1` = on). `{1,1,0,0}` = two eyes on Ports 1 & 2. To move both eyes to Ports 3 & 4 → `{0,0,1,1}` (and map their universes via `portUniverse`). |
| `portUniverse[4]` | `{0,1,2,3}` | Which Art-Net universe each port consumes — absolute, no arithmetic. Port N ← `portUniverse[N]`. Sender on U2/U3 instead of U0/U1 → `{2,3,0,0}`. Two ports mapped to the same universe **mirror** it. |
| `ledsPerStrip` | `12` | LEDs per ring (≤ 170 = one universe at 3 ch/LED). Match your ring; applies to all ports. |
| `STRIP_COLOR_ORDER` | `NEO_GRB` | Pixel color order for all rings. Red/green swapped → `NEO_RGB`. WS2812/SK6812 rings are usually GRB; some WS2811 strips are RGB. |
| `LED_OFFSET[4]` | `{0,0,0,0}` | Per-port start-pixel rotation. Bump a port's value ±1 until the sender's pixel 0 (12 o'clock) lands at that ring's true top. Wraps; negatives OK. |
| `LED_REVERSE[4]` | `{0,0,0,0}` | Per-port winding flip. Set a port's entry to `1` if that ring runs CCW against the sender's clockwise order. Set this **before** `LED_OFFSET` (the offset you need depends on direction). |
| `USE_STATIC_IP` | defined | Defined → try `fixedIP` first, fall back to DHCP, else STUCK. Comment out → DHCP-only. |
| `fixedIP[4]` | `{192,168,1,230}` | Static IP for this node (used when `USE_STATIC_IP` is defined). Point the sender's target IP here. |
| `STATIC_LINK_TIMEOUT_MS` · `DHCP_TIMEOUT_MS` · `DHCP_RETRIES` | `8000` · `12000` · `2` | Bounds for the network bring-up state machine. Rarely touched. |
| `MASTER_DIMMER_UNIVERSE` | commented out | Uncomment (e.g. `15`) to expose a global hardware-brightness universe for Resolume / QLC+ / MadMapper (`data[0]` dims all enabled strips). **Leave off** with the ring_eye_sim sender — its pixels are already brightness-scaled, so enabling it double-dims. |
| `DEBUG` | commented out | Uncomment for Serial logging @ 115200 (boot steps + `NET:` lines). Leave off in production — it adds a blocking `while(!Serial)` at boot. |
| `channelsPerLed` | `3` | `3` = RGB/GRB, `4` = RGBW/GRBW. Leave at `3` for these rings + this sender. |

**Fixed by the PCB** (don't change unless the board changes): `totalLEDStrips` (4 ports), `stripPins[] = {24,25,26,27}` (Port N → pin), `LED_PIN` (9, status LED), and the OLED pins/addresses (auto-detected at boot).

### Worked examples
- **Eyes on Ports 3 & 4, sender unchanged (still U0/U1):** `stripsEnabled = {0,0,1,1}`, `portUniverse = {0,1,0,1}` → U0 → Port 3, U1 → Port 4 (the first two entries are ignored since Ports 1 & 2 are disabled).
- **Sender re-universed to U2/U3, rings stay on Ports 1 & 2:** `stripsEnabled = {1,1,0,0}`, `portUniverse = {2,3,0,0}`.
- **Calibrate a ring:** show a single lit pixel from the sender. If the ring winds the wrong way set `LED_REVERSE[port] = 1`; then increment `LED_OFFSET[port]` until pixel 0 sits at 12 o'clock. Each port is independent.

---

## Runtime behavior

- **Boot:** status LED init → OLED auto-detect → LED test sweep (R/G/B) on enabled ports → read the Teensy's own MAC → network bring-up → start the Art-Net listener (UDP 6454).
- **Network:** bounded **static → DHCP → STUCK**, governed by `USE_STATIC_IP`. On success the OLED shows the active IP labelled `Set sender -> IP` (on DHCP, type that IP into the sender). STUCK = red on enabled rings + OLED `NETWORK FAILED`, reached only after every configured path is exhausted — not an indefinite hang.
- **Per frame:** each incoming Art-Net packet drives the enabled port(s) whose `portUniverse` matches its universe, then shows that ring. Two universes = two rings, fully independent; a dropped packet simply holds the last frame.
- **Status LED (pin 9):** HIGH = network up; LOW + red rings = STUCK.

---

## License

[GNU Lesser General Public License](../../LICENSE)

---

## Credits:

1. PaulStoffregen : for the [Teensy platform](https://github.com/PaulStoffregen/cores) and initial Ethernet library.
2. Nathanaël Lécaudé : for the [Artnet library](https://github.com/natcl/Artnet)
3. vjmuzik: For the Native [Ethernet library](https://github.com/vjmuzik/NativeEthernet)
4. Adafruit : for the [Neopixel library](https://github.com/adafruit/Adafruit_NeoPixel)


