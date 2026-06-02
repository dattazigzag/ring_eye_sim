/**
 * @brief
 *
 */

#include <SPI.h>
// # [TBD] This will compile for Teensy 4.1 and Teensy 4.0 ([TBD]: Differentiate fromTeensy 4.0 as it doesn't have Native Ethernet)
//#if defined( __IMXRT1062__)
#include <NativeEthernet.h>
#include <NativeEthernetUdp.h>
// IPAddress remoteIP = {192, 168, 132, 255};
//#endif
#include <Artnet.h>

byte querryMAC[] = {0xE5, 0x2A, 0xFC, 0x41, 0x13, 0x2D}; // Dummy random MAC addr used for retrieving Teensy 4.1's actual MAC addr
byte teensyMAC[6] = {};                                  // Array to hold the actual MACaddr of Teensy 4.1 (To be used for starting Ethernet Interface later)

Artnet artnet;
// startUniverse now lives in config.h (single source of truth).
const int numberOfChannels = numLeds * channelsPerLed; // Total number of channels you want to receive over DMX

const int maxUniverses = numberOfChannels / 512 + ((numberOfChannels % 512) ? 1 : 0); // Check if we got all universes...
bool universesReceived[maxUniverses];
bool sendFrame = 1;
int previousDataLength = 0;

void assignMAC(byte *_mac)
{
    logln("\n---------------------------------------------------------");
    logln("ETH + ARTNET INTERFACE INIT");
    logln("---------------------------------------------------------");
    logln("Getting new mac addr...");

    // oled screen text prompt
    if (ENABLE_OLED)
    {
        oled.clearDisplay();
        oled.setCursor(0, 0);
        oled.println("Trying to get new \n\nMAC ADDRESS ...");
        oled.display();
    }
    delay(2000);

    for (uint8_t by = 0; by < 2; by++)
        _mac[by] = (HW_OCOTP_MAC1 >> ((1 - by) * 8)) & 0xFF;
    for (uint8_t by = 0; by < 4; by++)
        _mac[by + 2] = (HW_OCOTP_MAC0 >> ((3 - by) * 8)) & 0xFF;
    for (int i = 0; i < 6; i++)
    {
        teensyMAC[i] = _mac[i];
    }

#ifdef DEBUG
    Serial.printf("byte teensyMAC[] = { 0x%02x, 0x%02x, 0x%02x, 0x%02x, 0x%02x, 0x%02x };\n", teensyMAC[0], teensyMAC[1], teensyMAC[2], teensyMAC[3], teensyMAC[4], teensyMAC[5]);
#endif

    // display on OLED
    if (ENABLE_OLED)
    {
        oled.clearDisplay();
        oled.setCursor(0, 0);
        oled.println("MAC ADDR:");

        for (int i = 0; i < 6; i++)
        {
            oled.print("0x");
            if (teensyMAC[i] < 16)
            {
                oled.print(0);
            }
            oled.print(teensyMAC[i], HEX);
            oled.print(":");
        }
        oled.display();
    }
}

// --- P2: bounded network bring-up -------------------------------------------
// Bring Ethernet up (static and/or DHCP, each time-bounded), then start the
// Art-Net UDP listener. Order is governed by USE_STATIC_IP in config.h:
//   defined   -> try static (fixedIP), fall back to DHCP, else STUCK
//   undefined -> DHCP only, else STUCK
// All timeouts/retries are config.h knobs. No indefinite block until STUCK.

// Static IP is applied immediately regardless of cable, so "success" here means
// the cable link actually came up within STATIC_LINK_TIMEOUT_MS.
static bool netTryStatic(byte _mac[], byte _ip[])
{
    logln("NET: trying STATIC IP...");
    Ethernet.begin(_mac, _ip);
    unsigned long t0 = millis();
    while (millis() - t0 < STATIC_LINK_TIMEOUT_MS)
    {
        if (Ethernet.linkStatus() == LinkON)
            return true;
        delay(50);
    }
    return false;
}

// Ethernet.begin(mac, timeout) returns 1 on lease / 0 on timeout -> bounded wait.
static bool netTryDHCP(byte _mac[])
{
    for (int attempt = 1; attempt <= DHCP_RETRIES; attempt++)
    {
        log("NET: trying DHCP, attempt ");
        logln(attempt);
        if (Ethernet.begin(_mac, DHCP_TIMEOUT_MS) == 1 && Ethernet.linkStatus() == LinkON)
            return true;
    }
    return false;
}

void inititateArtnet(byte _teensyMAC[], byte _fixedIP[])
{
    logln("\nNET: bringing up Ethernet + Art-Net...");
    if (ENABLE_OLED)
    {
        oled.clearDisplay();
        oled.setCursor(0, 0);
        oled.println("Bringing up\n\nNETWORK ...");
        oled.display();
    }

    bool ok = false;
    const char *mode = "";

#ifdef USE_STATIC_IP
    // Static first, then fall back to DHCP.
    if (netTryStatic(_teensyMAC, _fixedIP))
    {
        ok = true;
        mode = "STATIC";
    }
    else if (netTryDHCP(_teensyMAC))
    {
        ok = true;
        mode = "DHCP";
    }
#else
    // DHCP only.
    if (netTryDHCP(_teensyMAC))
    {
        ok = true;
        mode = "DHCP";
    }
#endif

    if (ok)
    {
        // Ethernet is up; just start the Art-Net UDP listener (port 6454).
        artnet.begin();

        log("\nNET OK [");
        log(mode);
        log("]  IP: ");
        logln(Ethernet.localIP());

        digitalWrite(LED_PIN, HIGH); // status LED: network up

        if (ENABLE_OLED)
        {
            oled.clearDisplay();
            oled.setCursor(0, 0);
            oled.print("NET OK: ");
            oled.println(mode);
            oled.println("Set sender -> IP:");
            oled.println(Ethernet.localIP());
            oled.display();
        }
    }
    else
    {
        // Terminal STUCK state: signal on the enabled strips and stop.
        logln("\nNET FAILED: no link / no DHCP [x]");
        digitalWrite(LED_PIN, LOW);

        if (ENABLE_OLED)
        {
            oled.clearDisplay();
            oled.setCursor(0, 0);
            oled.println("NETWORK FAILED");
            oled.println("no link / no DHCP");
            oled.println("check cable/router");
            oled.display();
        }

        for (byte i = 0; i < totalLEDStrips; i++)
        {
            if (stripsEnabled[i])
            {
                strips[i].fill(RED);
                strips[i].show();
            }
        }
        while (true)
        {
            ;
        }
    }
}