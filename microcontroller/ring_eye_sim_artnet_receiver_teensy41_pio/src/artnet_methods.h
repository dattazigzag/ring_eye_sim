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

    // Per-port routing: universe U drives exactly one port -> strips[U - startUniverse].
    // One ring per port, one universe per ring. Universes we don't map (or whose port is
    // disabled) are ignored. At <=170 LEDs/port each ring fits one universe, so no concat.
    int s = (int)universe - startUniverse;
    if (s < 0 || s >= totalLEDStrips || !stripsEnabled[s])
        return;

    int leds = length / channelsPerLed;
    for (int i = 0; i < leds && i < numLeds; i++)
    {
        if (channelsPerLed == 4)
        {
            // RGBW / GRBW
            strips[s].setPixelColor(i, data[i * channelsPerLed], data[i * channelsPerLed + 1], data[i * channelsPerLed + 2], data[i * channelsPerLed + 3]);
        }
        else
        {
            // RGB / GRB
            strips[s].setPixelColor(i, data[i * channelsPerLed], data[i * channelsPerLed + 1], data[i * channelsPerLed + 2]);
        }
    }
    strips[s].show();
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