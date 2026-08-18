# Security Policy

## Supported versions

TravelTime ships as a single stream; only the latest release receives fixes.

## Reporting a vulnerability

Please **do not** open a public issue for a security problem.

Use GitHub's private reporting instead:
[Report a vulnerability](https://github.com/susunola/TravelTime/security/advisories/new).

Please include a description of the issue, reproduction steps, and the affected
version. Expect an initial response within a few days.

## Security-relevant design

Two parts of this app deserve scrutiny from anyone auditing or modifying it.

### Privileged execution

Changing the system time zone requires administrator rights. TravelTime runs
`/usr/sbin/systemsetup -settimezone` via `osascript ... with administrator
privileges` (`SystemZoneSwitcher` / `PrivilegedRunner`).

Controls in place:

- The zone identifier is validated against `TimeZone.knownTimeZoneIdentifiers`
  **before** it is interpolated into the shell string. This is the primary
  defence against command injection: after validation the value can only contain
  letters, digits, `_`, `/` and `-`, all inert inside the quoted AppleScript
  string.
- IP geolocation results are treated as untrusted input and validated the same
  way before they can reach that path.
- Both geolocation endpoints are HTTPS. A plaintext endpoint would let a
  same-network attacker spoof a response that feeds a privileged call.
- Execution happens off the main thread with a 15 second timeout; the child
  process is terminated on timeout so an ignored authorization dialog cannot
  leave a dangling `osascript`.
- The password is entered in the system dialog. The app never reads, handles, or
  stores it.

### Update channel

`Updater` fetches release metadata from the GitHub API over HTTPS, then:

- downloads the asset over HTTPS,
- computes its SHA-256 and compares it to the checksum published in the release
  notes,
- **aborts if the checksum is absent or does not match** (fail closed),
- and only then replaces the bundle in `/Applications`, which requires
  authorization.

If you change this code, preserve the fail-closed behaviour. An updater that
installs an unverified binary with administrator rights is a remote code
execution primitive.

## Scope notes

- Releases are ad-hoc signed and **not notarized**; users must clear the
  quarantine attribute on first launch. This is a known distribution property,
  not a vulnerability.
- The app requests no sandbox entitlements and stores data unencrypted under
  `~/Library/Application Support/TravelTime/` and in `UserDefaults`. None of it
  is sensitive: a city list, a theme name, and an avatar image.
