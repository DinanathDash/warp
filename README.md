# Warp

Real-time network speedtest with an animated speedometer gauge and Bento dashboard in your Mac's notch and shelf, built for [Droppy](https://getdroppy.app).

## Overview

Warp provides instant, zero-dependency network speed testing directly from your Mac's notch and shelf. Powered by Apple's native `networkQuality` engine, Warp measures bandwidth throughput, loaded latency (bufferbloat), round-trip time, and responsiveness ratings against Apple's worldwide Edge CDN infrastructure with zero daemon overhead.

## Features

### macOS Native Engine
- **Zero External Dependencies:** Built on macOS's native `/usr/bin/networkQuality` binary. No Python runtime, Node packages, or Homebrew installations required.
- **Apple Edge CDN Infrastructure:** Runs bidirectional tests across native HTTP/2 and HTTP/3 sockets.
- **Safety & Process Control:** Sandboxed execution with watchdog timeouts, output buffer caps, and clean process lifecycle management.

### 270-Degree Speedometer Gauge
- **Dynamic Radial Arc:** 270° sweep with spring-damped needle and milestone markers (`0`, `50`, `100`, `250`, `1G`).
- **Phase-Aware Illumination:** Emerald green gradient for download measurement; purple gradient for upload measurement.
- **Numeric Rolling Digits:** Smooth animated value transitions using monospace alignment.

### Bento-Style Expanded Dashboard
- **Modular Bento Grid:** Every metric and control is housed in unified glass tiles with subtle borders and balanced heights.
- **Dedicated Gauge Tile:** Enlarged 180pt speedometer gauge paired with live phase indicators and test action controls.
- **Full Telemetry Tiles:**
  - **Throughput:** Individual download and upload bandwidth tiles with byte counters.
  - **Latency & Responsiveness:** Round-trip latency (RTT) and Apple Responsiveness RPM ratings (Low, Medium, High).
  - **Connection:** Active link interface (`Wi-Fi` / `Ethernet`), protocol version, and network endpoint.
  - **Server:** Edge CDN server name and host routing.
  - **Loaded Diagnostics:** Bufferbloat latency under load, TCP 443 handshake duration, and TLS handshake timing.
- **Balanced Idle State:** Structured readiness dashboard presenting engine specifications, active link detection, telemetry capabilities, and previous test records.

### Fluid Morph Transitions
- **Notch Morph Presentation:** Gauge and modular Bento tiles bloom outward from the camera notch upon expansion.
- **Collapse to HUD:** Header control folds the expanded surface back toward the notch, seamlessly presenting the compact completion HUD or returning to the shelf widget.

### Notch Shelf Widget
- **Solo Mode:** Full-width layout featuring notch-wrap wing integration, clean frosted glass `GO` button, and side-by-side telemetry.
- **Paired Mode:** Compact layout suited for multi-widget shelf configurations.
- **In-View Persistence:** Test results stay in view while the shelf or expanded surface is open, auto-resetting only when out of view for 14 seconds.

### Completion HUD
- **HUD Banner:** Compact notification presenting download speed, upload speed, and ping when testing finishes.
- **One-Click Takeover:** Primary action button to jump straight into the full expanded Bento dashboard.

### Preferences & History
- **Speed Units:** Toggle between standard Mbps (Megabits/s) and MB/s (Megabytes/s).
- **Notification Control:** Toggle completion HUD banners on or off.
- **Local History:** Locally stored test records with expandable rows displaying timestamp, throughput, and ping.
- **Rotating Logs:** Non-blocking rotating file logs in `~/Library/Logs/Warp/` with retention cleanup, one-click zip export, and Finder reveal.

## Requirements

- macOS 14.0 or newer
- [Droppy](https://getdroppy.app) with DroppyKit 1.28.0+

## License & Acknowledgements

- **Warp** is licensed under the MIT License by Dinanath Dash.
- **macOS networkQuality** is developed natively by Apple Inc. and built into macOS.
