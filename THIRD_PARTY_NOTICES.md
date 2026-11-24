# Third-party notices

## Lantern / Radiance (feature/lantern-core)

- Project: https://github.com/getlantern/radiance
- License: GNU General Public License, version 3 (GPL-3.0)
- License text: [licenses/RADIANCE-GPL-3.0.txt](licenses/RADIANCE-GPL-3.0.txt)
- Go module pin: `github.com/getlantern/radiance v0.0.0-20261121161923-0c920c73b969`
  (see `native/lanternbridge/go.mod`)

The Android sidecar (`liblantern.so`) is built from `native/lanternbridge`
with Radiance's `novpn` build tag: Radiance's TUN inbound is replaced by a
loopback-only mixed SOCKS5/HTTP listener on `127.0.0.1:1822`. AETHONE stays
the sole owner of Android's VpnService and TUN (zeptun forwards to 1822).
Telemetry is off (`TelemetryConsent: false`).

GPL-3.0 section 13 / AGPL-3.0 section 13 explicitly allow combining
GPL-3.0 and AGPL-3.0 code; each part keeps its own license.

## MSN-GUARD lanternbridge

- Project: https://github.com/mbm110/MSN-GUARD (branch `feature/lantern-prototype`)
- License: GNU Affero General Public License, version 3 (AGPL-3.0) — same as AETHONE
- `native/lanternbridge/` is adapted from MSN-GUARD's `core/lanternbridge/`
  (module path, default ports 1822 / ephemeral control, `--autoconnect`).

Radiance brings its own transitive Go dependencies (pinned by
`native/lanternbridge/go.sum`). Each keeps its own license and notices;
before distributing a release APK, generate and review a complete
dependency-license inventory (e.g. `go-licenses report ./cmd/lanternsidecar`).
