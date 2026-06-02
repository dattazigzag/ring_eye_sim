// =============================================================
// DMXSender — Art-Net wrapper
// =============================================================
// Copied (near-verbatim) from humanoid_face_twin/Processing/ArtNetSender.
// Wraps ch.bildspur.artnet.ArtNetClient. sendDMXData() unicasts one 512-byte
// DMX universe via unicastDmx(targetIP, subnet, universe, data). connect()
// starts the client (broadcast or to a target IP); stop() shuts it down.
//
// Requires the "Art-Net for Processing" library (ch.bildspur.artnet) installed,
// and these imports in the main sketch:
//   import ch.bildspur.artnet.*;
//   import java.net.InetAddress;
// =============================================================

class DMXSender {
  private ArtNetClient artnet;
  private boolean useBroadcast;
  private String  targetIP;
  private int universe;
  private int subnet;

  DMXSender(boolean useBroadcast, String targetIP, int port, int universe, int subnet) {
    this.useBroadcast = useBroadcast;
    this.targetIP     = targetIP;
    this.universe     = universe;
    this.subnet       = subnet;
    artnet = new ArtNetClient(new ArtNetBuffer(), port, port);
  }

  void connect() {
    try {
      // Always bind the local receiver on the default NIC via the no-arg start().
      // The destination is set PER-PACKET in sendDMXData() -> unicastDmx(targetIP, ...),
      // so we must NOT pass targetIP to start(): that argument is a *local* bind
      // address, and binding to the Teensy's IP throws
      // "BindException: Can't assign requested address".
      artnet.start();
      log(useBroadcast ? "[artnet] started (broadcast)"
                       : "[artnet] started (unicast target " + targetIP + ")");
    }
    catch (Exception e) {
      logErr("[artnet] error connecting: " + e.getMessage());
    }
  }

  void sendDMXData(byte[] data) {
    if (artnet != null) {
      try {
        artnet.unicastDmx(targetIP, subnet, universe, data);
      }
      catch (Exception e) {
        logErr("[artnet] error sending: " + e.getMessage());
      }
    }
  }

  void stop() {
    if (artnet != null) {
      artnet.stop();
      log("[artnet] stopped");
    }
  }
}
