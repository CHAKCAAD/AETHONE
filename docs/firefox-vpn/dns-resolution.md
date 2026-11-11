# DNS Resolution — the A1 decree

## 1. The field failure (root cause)

The 2026-11-08 device build (logcat line 43649, package
`com.chakcaad.aethone.da`) failed the FxA login exchange with:

```text
oauth token request: Post "https://api.accounts.firefox.com/v1/oauth/token":
dial tcp: lookup api.accounts.firefox.com on [::1]:53: read udp
[::1]:37265->[::1]:53: read: connection refused
```

Diagnosis: the ARM64 engine had been built **pure Go**
(`CGO_ENABLED=0`). Go's own resolver on Android consults the local
`/etc/resolv.conf`-shaped configuration, which on Android points at
`127.0.0.1:53` / `[::1]:53` — a resolver that does not exist outside
the OS's own resolver machinery.

## 2. The fix

Every Android ABI is built with **CGO + the NDK clang toolchain**,
which routes name resolution through **Bionic's `getaddrinfo`** — the
Android system resolver.

```bash
CGO_ENABLED=1
GOOS=android
GOARCH=<arm64|arm|amd64>
CC="$TOOLCHAIN/<per-abi>-clang"     # see android-abi-matrix.md
```

Pure Go is FORBIDDEN for every Android target of this engine:
`phase1/scripts/build_engine.sh` **refuses** `CGO_ENABLED=0` for any
Android target (fail-closed, not a warning). The build also fails if
the produced ELF lacks Bionic NEEDED entries or the `getaddrinfo`
import.

The Linux **host** build stays pure Go — it is not a deliverable; it
exists so the Dart integration tests and `--dns-probe` host evidence
run on the development machine (its resolver is the host OS's, which
is correct for that platform).

## 3. OS-dependent policy (never a global setting)

| Platform | Resolver policy |
|---|---|
| Android (all ABIs) | Bionic `getaddrinfo` via CGO — mandatory |
| Linux host (test vehicle) | Host OS resolver (pure Go is acceptable for the test vehicle only) |
| Other platforms | No wired Firefox VPN target exists — no claim, no generalization of the Android settings |

## 4. Forbidden approaches (the amendment's list)

* No hardcoded public resolvers (`8.8.8.8`, `1.1.1.1`, …).
* Never pin the resolver to `127.0.0.1` / `::1`.
* Never treat `/etc/resolv.conf` as authoritative on Android.
* Never hide DNS errors (no swallowing).
* Never weaken TLS verification.
* No network/operator-specific hacks.
* No logic that breaks private networks, system custom DNS, split DNS
  or VPN-active networks.

The goal is the correct use of the OS's native resolver mechanism —
nothing else.

## 5. Runtime DNS testing

* The engine carries a `--dns-probe` role: it resolves the real
  control-plane domains (`api.accounts.firefox.com`,
  `firefox.settings.services.mozilla.com`) and reports the real
  result/error — no account data involved.
* Host evidence was recorded 2026-11-09 (prior session).
* **Per-ABI on-device DNS runtime tests: NOT RUN** — no device or
  emulator exists in the agent environment. The owner runs them in
  the device-acceptance phase (e.g. `adb shell` invoking the extracted
  binary, or the app's own login flow and `da_diagnostic.log`).

DNS control-plane testing (login / token refresh / discovery) is
separate from VPN traffic validation — the owner has not requested
traffic validation.
