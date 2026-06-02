<div align="center">

# Ring Eye Sim · Art-Net Sender

**Drive two NeoPixel "eye" rings from a video or a live screen region — sampled, color-corrected, and streamed as Art-Net DMX.**

[![Export macOS (Apple Silicon)](https://github.com/dattazigzag/ring_eye_sim/actions/workflows/export-macos.yml/badge.svg)](https://github.com/dattazigzag/ring_eye_sim/actions/workflows/export-macos.yml)
![Platform](https://img.shields.io/badge/platform-macOS%20Apple%20Silicon-black)
![Processing](https://img.shields.io/badge/Processing-4.5.2-006699)
[![License: LGPL](https://img.shields.io/badge/license-LGPL-blue)](LICENSE)

</div>

---

## What it is

A Processing sketch that turns any video clip — or a draggable live screen-capture "lens" — into pixel data for **two side-by-side ring displays**: a **right "eye" (main)** and a **left "eye" (clone)**. Each eye overlays a parametric NeoPixel-style ring, samples the color under every LED, runs it through a gamma / brightness pipeline, and streams the result as **Art-Net DMX** on its **own universe** — so two physical rings can be driven independently and in perfect sync.

It's a hardware-in-the-loop design tool: drop in an animation, see exactly what the ring will show, and send it straight to the lights — or to the bundled software **tester** when the hardware isn't on the bench.

> Input is **either** a video file **or** a live screen region (mutually exclusive). Move / scale and play / pause are shared across both eyes; each eye can be flipped horizontally and/or vertically on its own.

## How it works

```mermaid
flowchart LR
    SRC["Video file or screen lens"] --> MH["MediaHandler: single decode, shared frame"]
    MH --> R["Right eye (main): mirror to 480x480"]
    MH --> L["Left eye (clone): mirror to 480x480"]
    R --> RS["Ring sample per LED"]
    L --> LS["Ring sample per LED"]
    RS --> CP["Color pipeline: gamma + brightness"]
    LS --> CP
    CP --> D0["Art-Net universe 0"] --> RX(("right ring / tester"))
    CP --> D1["Art-Net universe 1"] --> LX(("left ring / tester"))
    CP -. "layout via MQTT (retained)" .-> MQ["topic ring/config"]
    MQ -. .-> RX
```

**Key principles**

- **Single decode, shared frame.** The video is decoded once; both eyes render the same frame — frame-perfect sync, half the work, one pipeline to babysit.
- **Mirror is the only per-eye property.** H/V flip happens at draw time; sampling reads the framebuffer *after* the flip, so each ring follows its own mirror with no special-casing.
- **Sampling = inscribed circle per cell.** Each LED averages the pixels under its disc — rotation-invariant and allocation-free.
- **Dual-universe Art-Net.** Right = universe 0, left = universe 1 (shared subnet); broadcast or per-eye unicast.
- **MQTT is a side-channel, not the data path.** Pixels go over Art-Net; only the layout (`N`, universe, subnet — retained) is published on `ring/config` so a preview receiver mirrors geometry live. No broker → Art-Net still runs.
- **Screen-capture lens.** A transparent, resizable, always-on-top window grabs any desktop region into the same pipeline.

---

## Run it

### A · The released app (no Processing needed)

1. Download the latest `ring_eye_sim-vX.Y.Z-macos-aarch64.zip` from **[Releases](https://github.com/dattazigzag/ring_eye_sim/releases)** and unzip it.
2. The app is **native Apple Silicon with no embedded Java**, so install a **Java 17+ runtime** once (any arm64 JDK):
   ```bash
   brew install --cask temurin@17
   ```
3. Clear the macOS download quarantine, then launch:
   ```bash
   xattr -dr com.apple.quarantine ring_eye_sim_artnet_sender.app
   open ring_eye_sim_artnet_sender.app
   ```
4. For the screen-capture lens, grant **Screen Recording** (System Settings → Privacy & Security → Screen Recording) and **relaunch** — it takes effect only on restart, and the app's fresh signature means you must grant it even if Processing was allowed before.
5. *(Optional)* For live tester sync, install the broker — the app auto-starts it:
   ```bash
   brew install mosquitto
   ```

> **Apple Silicon only**, no Rosetta. Java is intentionally not bundled (keeps the app native and small), so a Java 17+ runtime must be present.

### B · From source in Processing

1. Install **Processing 4.5.2**.
2. **Sketch → Import Library → Manage Libraries** → install **Video**, **ControlP5**, **artnet4j**, **MQTT** (Joël Gähwiler), and **Drop / SDrop**.
3. Open `Processing/ring_eye_sim_artnet_sender/` and press **Run**.

- **Renderer is P3D** (GPU). P3D windows don't accept drag-and-drop, so load a clip with the <kbd>O</kbd> key / **OPEN VIDEO** button.
- **macOS Screen Recording** permission is needed for the screen-capture lens — enable Processing under Privacy & Security → Screen Recording, then restart it.
- **High-DPI:** runs at `pixelDensity(2)` for a crisp display (sampling is density-aware). If a GStreamer video freeze or perf drop appears, re-enable `pixelDensity(1)` in `settings()` — the known-good fallback.
- **MQTT broker:** see below — the sketch auto-launches mosquitto if installed, else skips MQTT (Art-Net unaffected).

---

## Keyboard controls

| Key | Action | &nbsp; | Key | Action |
|---|---|---|---|---|
| <kbd>O</kbd> | Open / load a video | | <kbd>D</kbd> | Toggle screen-capture lens |
| <kbd>Space</kbd> | Play / pause | | <kbd>G</kbd> | Grid overlay |
| <kbd>← → ↑ ↓</kbd> | Move video (both eyes) | | <kbd>L</kbd> | Cell labels |
| <kbd>⌘↑</kbd> / <kbd>⌘↓</kbd> | Scale up / down | | <kbd>C</kbd> | Sampled-color preview |
| <kbd>R</kbd> | Reset transform | | <kbd>A</kbd> | Art-Net send on / off |
| <kbd>M</kbd> | Cycle color mode | | <kbd>[</kbd> / <kbd>]</kbd> | Brightness − / + |
| <kbd>S</kbd> | Save config | | <kbd>⌫</kbd> | Clear video |

Per-eye **flip H/V**, **universe**, and **IP**, plus color and Art-Net transport, live in the on-screen panel.

---

## MQTT broker

Pixels travel over Art-Net; the preview tester also needs the ring **layout**, published over MQTT (topic `ring/config`, retained). Install a local broker:

```bash
brew install mosquitto
```

You don't start it manually — on launch the app **ensures a broker is running**: it reuses one already on `localhost:1883`, or spawns mosquitto itself and shuts down only a broker it started. With mosquitto absent, MQTT is skipped and **Art-Net is never affected**.

## Preview tester (software receiver)

`Processing/tools/tailored_dmx_receiver/` renders a NeoPixel-ring twin of the **main (right)** eye — the exact post-gamma colors the hardware would receive — reading pixels over Art-Net and layout over MQTT. Use it to validate output with no hardware on the bench.

**Start order:** mosquitto → sender → tester.

---

## Releasing (GitHub Actions)

Builds run on a GitHub-hosted **macOS Apple-Silicon** runner — no local export required.

- **Cut a release** — push a version tag:
  ```bash
  git tag v1.0.0 && git push origin v1.0.0
  ```
  The workflow exports the app and attaches `ring_eye_sim-v1.0.0-macos-aarch64.zip` to a new **GitHub Release** (notes auto-generated).
- **Dry run** — run **Export macOS (Apple Silicon)** from the **Actions** tab (`workflow_dispatch`): same zip as a downloadable **artifact**, no release created.

It pins Processing 4.5.2 (checksum-verified), pulls the Video library's Apple-Silicon GStreamer natives fresh, adds the vendored libraries in `ci/libraries/`, and exports `--no-java --variant=macos-aarch64`. See `.github/workflows/export-macos.yml`.

## Repo layout

| Path | What |
|---|---|
| `Processing/ring_eye_sim_artnet_sender/` | the sender app (sketch source) |
| `Processing/tools/tailored_dmx_receiver/` | software preview tester |
| `ci/libraries/` | Processing libraries vendored for CI |
| `.github/workflows/export-macos.yml` | export + release pipeline |

## License

[GNU Lesser General Public License](LICENSE)
