# Security and privacy

This application deliberately controls input. Connect only your own phone and
authorize only your own Mac. Accessibility and debugging are powerful OS
permissions; disable them when no longer needed.

- No account, telemetry, cloud connection, clipboard sync, microphone, video,
  screen capture, or retained keyboard content.
- UserDefaults contains arrangement, sensitivity, region and release-key choice.
  The app does not save device serials or pairing codes. ADB manages its own
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
- The companion has no internet permission. Its local abstract socket authenticates
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
