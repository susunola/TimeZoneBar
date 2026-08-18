# Contributing

Thanks for your interest in TravelTime. It is a small, dependency-free macOS app,
and the goal is to keep it that way.

## Getting set up

```bash
git clone https://github.com/susunola/TravelTime.git
cd TravelTime
swift build --disable-sandbox
swift test  --disable-sandbox
```

`--disable-sandbox` is needed on recent macOS releases, where SwiftPM's manifest
sandbox fails with `sandbox_apply: Operation not permitted`.

To produce a runnable app bundle:

```bash
python3 make_icon.py Resources
./build.sh
```

`build.sh` signs with a self-signed identity called `TimeZoneBar Developer` and
installs to `/Applications`. Create that certificate in Keychain Access
(*Certificate Assistant → Create a Certificate*, type: Code Signing), or change
the identity in `build.sh` to `-` for ad-hoc signing.

## Ground rules

- **No third-party dependencies.** `Package.swift` has none, and adding one needs
  a strong justification in the PR description.
- **Keep the privilege boundary tight.** Anything reaching
  `SystemZoneSwitcher` or `PrivilegedRunner` must be validated first. Time zone
  identifiers are checked against `TimeZone.knownTimeZoneIdentifiers` before they
  are interpolated into a shell string, because geolocation responses are
  untrusted input. Do not weaken this.
- **The updater fails closed.** A missing or mismatched SHA-256 must abort the
  install. Do not add a "skip verification" path.
- **Cover logic with tests.** UI code is not unit tested, but pure functions
  (formatting, version comparison, checksum parsing, decoding/migration) are —
  see `Tests/TravelTimeTests`. New logic of that kind should come with tests.
- **Match the surrounding style.** Comments explain *why*, not *what*; several
  non-obvious workarounds in this codebase exist because of specific macOS
  behaviour and are documented inline. Preserve those notes if you refactor.

## Pull requests

1. Branch off `main`.
2. Make sure `swift build` and `swift test` both pass. CI runs them on macOS.
3. Describe what you changed and how you verified it. For UI changes, attach a
   screenshot.
4. Keep each PR to one concern.

## Reporting bugs

Open an issue including:

- your macOS version (`sw_vers -productVersion`)
- the app version (Settings, or `CFBundleShortVersionString` in the bundle)
- steps to reproduce, expected vs actual behaviour
- for crashes, the relevant report from Console.app

## Screenshots

Theme screenshots in `docs/screenshots/` are captured from a throwaway bundle ID
so that no personal preferences or avatar end up in the images, and captured
per-window (`screencapture -l`) so no desktop is visible. If you regenerate
them, please keep those properties and use the same zone set across all four
themes.
