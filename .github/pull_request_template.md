## What this changes

<!-- Brief description, and the issue it closes if applicable. -->

## How it was verified

<!-- Commands you ran, cases you checked. Screenshots for UI changes. -->

- [ ] `swift build --disable-sandbox` passes
- [ ] `swift test --disable-sandbox` passes
- [ ] Ran as a bundled app (`./build.sh`) and exercised the changed path

## Checklist

- [ ] No third-party dependency added (or justified above)
- [ ] Logic changes come with tests in `Tests/TravelTimeTests`
- [ ] Anything reaching `PrivilegedRunner` / `SystemZoneSwitcher` is still
      validated against `TimeZone.knownTimeZoneIdentifiers` first
- [ ] Updater still fails closed on a missing or mismatched SHA-256
- [ ] `CHANGELOG.md` updated under `## [Unreleased]`
