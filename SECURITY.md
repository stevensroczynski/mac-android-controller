# Security and privacy

This application deliberately controls input. Connect only your own phone and
authorize only your own Mac. Accessibility and debugging are powerful OS
permissions; disable them when no longer needed.

- No account, telemetry, cloud connection, clipboard sync, microphone/audio capture,
  or retained keyboard content. Normal input-sharing mode does not capture screens.
- Extended-display mode explicitly captures only the new virtual Mac display after
  macOS Screen Recording permission. Anything moved onto that display is visible
  to the selected phone. H.264 video is held in bounded memory buffers, never saved
  or logged. A temporary display is removed when streaming stops. Undocumented
  CoreGraphics virtual-display interfaces are isolated and runtime checked.
- The Android display viewer is foreground-only, uses FLAG_SECURE to discourage
  screenshots, and blanks its surface on pause or stream failure. It uses a separate
  authenticated abstract socket through the selected localhost ADB forward. Packets
  are limited to 4 MiB, dimensions to 2560 per axis, and reads to five seconds. A
  stream has at most one encoded frame awaiting acknowledgment; video frames are
  skipped before encoding to avoid an unbounded queue or broken H.264 references.
  Its own activity keeps the screen awake while visible; closing/pausing or a stream
  failure releases that hold. There is no permanent screen-timeout change.
- UserDefaults contains arrangement, sensitivity, region, release-key choice and
  USB/Wi-Fi preference. The most recently authenticated companion installation ID
  and token are saved in macOS Keychain, not plaintext preferences or logs. ADB manages its own
  host private key and paired-device records in its standard user configuration.
- USB control uses the explicitly selected physical device. AOA registration is
  attempted first; on failure, the bundled UHID helper runs through the already
  authorized USB ADB shell for the same serial. The app never changes
  Android's USB role, silently enables debugging, or modifies system security.
- Wireless control requires explicit Android Wireless Debugging pairing. The
  six-digit pairing code is passed over stdin, not process arguments, and cleared
  from the app after submission. All input/control channels select the same TLS
  service. Pairing trust persists in ADB/Android until revoked; disconnecting this
  app does not revoke the Mac's debugging authorization or stop the ADB server.
- Automatic credential retrieval uses an exported ContentProvider protected by
  the platform DUMP permission AND a Binder caller check for UID 2000 (ADB shell).
  It supports credentials and minimal connection-status queries; write operations
  are rejected. Access
  therefore requires a Mac already authorized for USB or TLS debugging. Ordinary
  Android apps and unauthenticated LAN clients cannot retrieve the token.
- The companion uses WAKE_LOCK only for an authenticated live session. Its screen
  wake lock expires after five seconds unless renewed by the session watchdog.
  No wake-up flag, keyguard dismissal, or system timeout change is used. Locking
  the phone ends the session. Users can disable keep-awake in the companion.
- The companion has no internet permission. Its input/control local abstract socket authenticates
  with a random 128-bit secret, bounded input lines, timeouts and failed-attempt
  throttling. ADB exposes only a localhost forward, removed when the session ends.
  The Android secret is stored in private preferences, excluded from backups,
  and can be reset in its setup screen.
- Local privileged processes, a compromised phone/Mac, or another authorized ADB
  client are outside this protection boundary. USB AOA itself has no application
  authentication or encryption. Wireless mode uses Android 11+ TLS Wireless Debugging;
  only modern TLS service advertisements are eligible, with no legacy TCP mode.
- Test and build outputs, signing keys, logs, downloaded research, private notes,
  local paths, and credentials are excluded from the source repository.

Do not put pairing codes, device identifiers, typed text, screenshots of private
apps, or credentials in public bug reports. Report reproducible behavior using
the isolated input test activity and sanitized permission/status diagnostics.
