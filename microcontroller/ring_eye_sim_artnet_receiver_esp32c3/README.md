# README

> Super simplified wiring diagram
![alt text](<assets/Untitled Sketch 2_bb.png>)

## Prerequisite

### Arduino IDE Setting:

> Arduino IDE version tested on: 2.3.9 (06.2026)

### Libraries used

1. https://github.com/rstephan/ArtnetWifi
2. https://github.com/adafruit/adafruit_neopixel

> All installed via library manager

### Board Tested on:

[esp32c3-mini](https://amzn.eu/d/06vSzoXW)


> [!Important]
> Do not forget to [Install esp32 boards in the Arduino IDE ](https://randomnerdtutorials.com/installing-the-esp32-board-in-arduino-ide-windows-instructions/)

---

### Code customization

> [!Important]

1. Copy the `config.h.template` to `config.h` and update the wifi credentials. 
2. Then in the main sketch update these if you want Fixed IP or comment them out if you want DHCP based IP assignment by router

```c
const IPAddress ip(192, 168, 1, 229);
const IPAddress gateway(192, 168, 1, 1);
const IPAddress subnet_mask(255, 255, 255, 0);
```

3. if you are assigning 1 ring to Artnet Universe 0, and flashing that to a esp32, then keep

```c
uint16_t universe = 0
```

But for the nxt one, teh 2d ring and the 2nd esp32, before flashing update this to 1. 

```c
uint16_t universe = 1
```

> [!Warning]
> _Also for the 2nd esp32, if yo are using Fixed IP, change the parameters from Pt. 2 so there are not IP Conflicts_

4. [Neopixel LED rings come in different sizes consisting of varied number of addressable LEDs](https://learn.adafruit.com/adafruit-neopixel-uberguide?view=all#neopixel-rings). We tested it against n=12. _Adjust if yours is different..._

```c
#define LED_COUNT  12
```

5. Also update where the Data-IN pin from the ring connects to the ESP32, if yours is different. _We used Pin 0_

```c
#define LED_PIN    0
```

---

#### Compile and Upload settings:

![alt text](<assets/Screenshot 2026-06-02 at 16.21.02.png>)

___

## LICENSE

[GNU Lesser General Public License](../../LICENSE)

