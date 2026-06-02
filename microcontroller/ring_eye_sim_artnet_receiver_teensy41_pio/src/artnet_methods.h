/**
 * @brief
 *
 */

void onDmxFrame(uint16_t universe, uint16_t length, uint8_t sequence, uint8_t *data, IPAddress remoteIP)
{
#ifdef MASTER_DIMMER_UNIVERSE
    // Optional global master-dimmer universe (opt-in via config.h). data[0] sets hardware
    // brightness on all enabled strips. OFF by default for the ring_eye_sim sender, whose
    // pixels are already brightness-corrected (would otherwise double-dim).
    if (universe == MASTER_DIMMER_UNIVERSE)
    {
        for (byte i = 0; i < totalLEDStrips; i++)
        {
            if (stripsEnabled[i])
            {
                strips[i].setBrightness(data[0]);
                strips[i].show();
            }
        }
        return;
    }
#endif

    // Explicit per-port routing: drive every ENABLED port whose mapped universe
    // (portUniverse[p], from config.h) matches this incoming universe. No arithmetic.
    // A universe no port maps to is ignored; two ports mapped to it mirror it.
    int leds = length / channelsPerLed;
    for (byte p = 0; p < totalLEDStrips; p++)
    {
        if (!stripsEnabled[p] || portUniverse[p] != (int)universe)
            continue;

        for (int i = 0; i < leds && i < numLeds; i++)
        {
            // P4 calibration: map sender pixel i -> physical pixel on THIS port.
            //   LED_REVERSE[p] flips winding (CW <-> CCW); LED_OFFSET[p] rotates the start pixel.
            //   Defaults (false / 0) give phys == i -> identity (no calibration applied).
            int phys = LED_REVERSE[p] ? (numLeds - 1 - i) : i;
            phys = ((phys + LED_OFFSET[p]) % numLeds + numLeds) % numLeds;

            if (channelsPerLed == 4)
            {
                // RGBW / GRBW
                strips[p].setPixelColor(phys, data[i * channelsPerLed], data[i * channelsPerLed + 1], data[i * channelsPerLed + 2], data[i * channelsPerLed + 3]);
            }
            else
            {
                // RGB / GRB
                strips[p].setPixelColor(phys, data[i * channelsPerLed], data[i * channelsPerLed + 1], data[i * channelsPerLed + 2]);
            }
        }
        strips[p].show();
    }
}

void startArtnetMethods()
{
    artnet.setBroadcast(broadcast);
    artnet.setArtDmxCallback(onDmxFrame);
}

void readArtnet()
{
    artnet.read();
}