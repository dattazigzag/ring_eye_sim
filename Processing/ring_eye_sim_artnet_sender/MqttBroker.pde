// =============================================================
// MqttBroker — best-effort local broker autostart (macOS only)
// =============================================================
// Goal: "launch the sketch and MQTT just works." On startup we ENSURE a broker
// is listening on mqttHost:mqttPort, then let the existing MQTT toggle connect.
//
// Model (decided): ENSURE-RUNNING, NEVER KILL.
//   - broker already on the port  -> use it, leave it alone
//   - else `mosquitto` on PATH     -> spawn one (it PERSISTS after we exit)
//   - else                          -> log once + carry on (MQTT just won't
//                                       connect; Art-Net is unaffected)
// Gated on `enableMQTT` (off in config -> we touch nothing).
//
// Run SYNCHRONOUSLY from setup() BEFORE the UI builds: the default-ON MQTT toggle
// fires startMQTT() during construction, so ensuring the broker first means the
// connect finds it already listening — no race, no polling handshake back into
// the UI. The block is short and bounded (startup only): instant when the port is
// already up or dead-refused, ~a few hundred ms when we spawn + wait for bind.
//
// macOS only (login zsh for brew's PATH, brew-installed mosquitto). This whole
// sketch is macOS-only anyway (Robot screen-grab, osascript-free here).
//
// We spawn with a generated temp conf (NOT a tracked file) because mosquitto 2.x
// has no CLI flag for `allow_anonymous` / listener bind address — only `-c <file>`
// sets them. The conf binds all interfaces + allows anon so a LAN tester / future
// ESP32 can reach it, not just localhost.
// =============================================================

import java.io.*;
import java.net.Socket;
import java.net.InetSocketAddress;

// The broker we spawned (if any). Kept for reference/debug only — intentionally
// NOT destroyed on exit (Model B: the broker persists for the tester + the next
// launch's fast path). No shutdown hook, no dispose() teardown.
Process mqttBrokerProcess = null;

// -------------------------------------------------------------
// Entry point — called once from setup(), before the UI is built.
// -------------------------------------------------------------
void ensureBrokerRunning() {
  if (!enableMQTT) {
    log("[broker] MQTT disabled in config — skipping broker autostart");
    return;
  }

  // 1) Already up? Use it, never touch it. (Dead port = connection refused =
  //    returns ~instantly, so no timeout penalty on the spawn path below.)
  if (isPortOpen(mqttHost, mqttPort, 250)) {
    logOk("[broker] broker already listening on " + mqttHost + ":" + mqttPort + " — using it");
    return;
  }

  // 2) Find mosquitto on PATH (login shell so brew's PATH is loaded).
  String mosq = whichCommand("mosquitto");
  if (mosq == null) {
    logWarn("[broker] mosquitto not found — 'brew install mosquitto' for live tester sync; running without it");
    return;
  }

  // 3) Spawn it (best effort), then wait briefly for it to bind the port.
  logOk("[broker] found mosquitto at " + mosq + " — starting on port " + mqttPort);
  startBroker(mosq);
  if (waitForPort(mqttHost, mqttPort, 1500)) {
    logOk("[broker] broker is up on " + mqttHost + ":" + mqttPort);
  } else {
    logWarn("[broker] broker didn't confirm on " + mqttPort + " within 1.5 s — toggle ENABLE off/on to retry if needed");
  }
}

// -------------------------------------------------------------
// Spawn mosquitto with a generated temp conf (bind-all + allow-anon). Output is
// discarded (we don't read broker logs). Falls back to a localhost-only -p launch
// if the temp conf can't be written. Best effort — any failure just degrades to
// "no broker" (the MQTT connect then fails safely; Art-Net is unaffected).
// -------------------------------------------------------------
void startBroker(String mosquittoPath) {
  try {
    ProcessBuilder pb;
    String conf = writeTempBrokerConf();          // null if it couldn't be written
    if (conf != null) {
      pb = new ProcessBuilder(mosquittoPath, "-c", conf);
    } else {
      logWarn("[broker] couldn't write temp conf — launching localhost-only on " + mqttPort);
      pb = new ProcessBuilder(mosquittoPath, "-p", str(mqttPort));
    }
    pb.redirectOutput(ProcessBuilder.Redirect.DISCARD);
    pb.redirectError(ProcessBuilder.Redirect.DISCARD);
    mqttBrokerProcess = pb.start();
  }
  catch (Exception e) {
    logWarn("[broker] failed to start mosquitto: " + e.getMessage() + " — running without it");
  }
}

// Two-line broker conf: listen on ALL interfaces + allow anonymous. Written fresh
// to the system temp dir each launch (ephemeral, not a project file).
String writeTempBrokerConf() {
  try {
    File conf = new File(System.getProperty("java.io.tmpdir"), "ring_eye_sim_mosquitto.conf");
    PrintWriter w = new PrintWriter(conf);
    w.println("listener " + mqttPort + " 0.0.0.0");
    w.println("allow_anonymous true");
    w.flush();
    w.close();
    return conf.getAbsolutePath();
  }
  catch (Exception e) {
    return null;
  }
}

// -------------------------------------------------------------
// Helpers
// -------------------------------------------------------------

// `which <cmd>` via a LOGIN zsh so brew's PATH (.zprofile/.zshrc) is loaded — a
// GUI-launched Processing otherwise has a minimal PATH and won't find brew bins.
String whichCommand(String cmd) {
  try {
    Process p = new ProcessBuilder("/bin/zsh", "-l", "-c", "which " + cmd)
      .redirectErrorStream(true).start();
    BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
    String line = r.readLine();
    p.waitFor();
    r.close();
    if (line != null && line.trim().length() > 0 && !line.contains("not found")
        && new File(line.trim()).exists()) {
      return line.trim();
    }
  }
  catch (Exception e) {
    logWarn("[broker] error looking for " + cmd + ": " + e.getMessage());
  }
  return null;
}

// True if a TCP connect to host:port succeeds within timeoutMs (= a broker is
// listening). A dead port returns connection-refused ~instantly.
boolean isPortOpen(String host, int port, int timeoutMs) {
  Socket s = null;
  try {
    s = new Socket();
    s.connect(new InetSocketAddress(host, port), timeoutMs);
    return true;
  }
  catch (Exception e) {
    return false;
  }
  finally {
    if (s != null) try {
      s.close();
    } catch (Exception ignore) {
    }
  }
}

// Poll isPortOpen until it succeeds or totalMs elapses (~100 ms steps). Used once,
// right after we spawn the broker, to gate the (imminent) first connect.
boolean waitForPort(String host, int port, int totalMs) {
  int deadline = millis() + totalMs;
  while (millis() < deadline) {
    if (isPortOpen(host, port, 150)) return true;
    delay(100);
  }
  return false;
}
