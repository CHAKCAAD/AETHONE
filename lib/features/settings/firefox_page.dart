/// «فایرفاکس» — the Firefox VPN sub-page (Phase 2): the ACCOUNT section
/// (the WebChannel sign-in state — signed in / not signed in, the sign-in
/// button opening the embedded accounts.firefox.com page, the sign-out
/// wiping the Keystore vault), the EXIT-LOCATION pick (the LIVE
/// RemoteSettings country set the engine's --discover role fetched —
/// AUTO first = Mozilla's recommended anycast — the same list the home
/// wheel's firefox band offers, with the live/cached honesty label), and
/// the data-plane transport pick (h2 default / h3 optional).
///
/// The engine behind this page: docs/FIREFOX_VPN_ENGINE.md + the login
/// flow docs/FIREFOX_VPN_LOGIN.md (private branch phase2/firefox-vpn-ui).
library;

import 'package:flutter/material.dart';

import '../../../connection/connection_store.dart';
import '../../../connection/core_settings.dart';
import '../../../connection/transport_modes.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../l10n/app_strings.dart';
import '../home/widgets/hero_logo.dart' show ScanRings;
import 'firefox_login_screen.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class FirefoxSettingsPage extends StatefulWidget {
  const FirefoxSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  @override
  State<FirefoxSettingsPage> createState() => _FirefoxSettingsPageState();
}

class _FirefoxSettingsPageState extends State<FirefoxSettingsPage> {
  @override
  void initState() {
    super.initState();
    // The honesty-first refreshes: the live country set (labeled live vs
    // cached) and the vault-backed signed-in state.
    widget.store.loadFirefoxDnsSettings().then((_) {
      if (mounted) widget.store.refreshFirefoxLocations();
    });
    widget.store.refreshFirefoxAccount().then((_) {
      // 1.7.0 — the remaining-data value lands on page open (the
      // `--usage` role through a WARP carrier; a signed-out vault is
      // an honest no-op).
      if (mounted &&
          widget.store.firefoxAccount == FirefoxAccountStatus.signedIn) {
        widget.store.refreshFirefoxQuota();
      }
    });
  }

  void _openLogin(BuildContext context) {
    Navigator.of(context).push(
      aethPageRoute<void>(
        style: widget.store.effectiveMotionStyle(context),
        builder: (_) => FirefoxLoginScreen(store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final store = widget.store;
    final core = store.coreSettings;

    final accountStatus = switch (store.firefoxAccount) {
      FirefoxAccountStatus.signedIn => strings.firefoxSignedIn,
      FirefoxAccountStatus.signedOut => strings.firefoxSignedOut,
      FirefoxAccountStatus.unknown => strings.firefoxSignedOut,
    };

    // The honesty label of the location list: live fetch vs disk cache,
    // with the fetch time — a cache is never presented as live data.
    final fetchedAt = store.firefoxLocationsFetchedAt;
    final listLabel = store.firefoxLocationsLive
        ? strings.firefoxLocationsLive
        : strings.firefoxLocationsCached;

    return SubPageFrame(
      store: store,
      title: strings.settingsFirefox,
      children: () => [
        // ---- Section: the account (Phase 2: the WebChannel sign-in) ----
        SubSectionHeading(
          // PHASE-2 REBUILD (2026-11-09): the OFFICIAL Firefox mark
          // (the owner-delivered artwork) — the Shield-Tick stopgap
          // retires here too (open item G2, both surfaces).
          icon: AppAssets.protocolFirefoxLogo,
          title: strings.secFirefoxAccount,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingLabel(accountStatus),
              const SizedBox(height: 10),
              if (store.firefoxAccount == FirefoxAccountStatus.signedIn) ...[
                // v1.7.0 — the remaining-data card (the owner's round 5:
                // «بخش حجم باقی‌مانده رو اصلاح کن چون ظاهراً کار نمیکنه»):
                // the live value + the on-demand refresh (the `--usage`
                // role — no pass minted, the WARP carrier ridden like
                // the sign-in). The same block feeds the settings pill
                // and the protocol card.
                _FirefoxQuotaCard(store: store),
                const SizedBox(height: 10),
                // Sign-out: the logout-grade vault wipe (the store
                // disconnects a live firefox session first).
                SettingActionButton(
                  keyId: 'firefox-sign-out',
                  label: strings.firefoxSignOut,
                  onTap: () => store.firefoxSignOut(),
                ),
              ] else ...[
                // Sign-in: the embedded accounts.firefox.com page — the
                // password never transits AETHONE code (the sign-in
                // happens on Mozilla's own page; the WebChannel captures
                // only the session token for the engine's stdin pipe).
                SettingActionButton(
                  keyId: 'firefox-sign-in',
                  label: strings.firefoxSignIn,
                  onTap: () => _openLogin(context),
                ),
              ],
              const SubSectionDivider(),
              SettingInfoText(strings.firefoxAccountDesc),
            ],
          ),
        ),

        // ---- Section: exit location (the LIVE RemoteSettings set) ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconLocation,
          title: strings.secExitLocation,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The SAME list the home wheel's firefox band offers: the
              // live set once the --discover refresh lands, else the
              // standing seed (recorded 2026-11-08). AUTO first = the
              // REC anycast.
              FlagPickStrip(
                codes: [
                  LocationWheelPolicy.autoCode,
                  ...(store.liveFirefoxCountries ?? firefoxCountrySnapshot),
                ],
                selected: store.firefoxLocation,
                onSelect: store.setFirefoxLocation,
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.firefoxLocationDesc),
              const SubSectionDivider(),
              // The honesty label (live / cached + the fetch time) — with
              // the scan-loading rings while the refresh walk runs (the
              // owner's round 5: a backend operation must show its
              // loading the moment it starts).
              Row(
                children: [
                  if (store.firefoxLocationsRefreshing)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: ScanRings(
                        color: AethColors.textSecondary,
                        size: 14,
                      ),
                    ),
                  if (store.firefoxLocationsRefreshing)
                    const SizedBox(width: 8),
                  Expanded(
                    child: SettingInfoText(
                      fetchedAt == null
                          ? listLabel
                          : '$listLabel — ${_formatTime(context, fetchedAt)}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ---- Section: the carrier mode (v1.5.0, the owner's round 3;
        // semantics corrected in round 4) — over-WARP (the standing
        // default: the whole engine conversation rides the in-process
        // Aether core) or DIRECT (arman's relay posture: the initial
        // connection stages still ride the Aether core's WARP tunnel,
        // then the data connection dials the Fastly edge itself). ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconSwap1,
          title: strings.secFirefoxMode,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingPills<FirefoxCarrierMode>(
                keyId: 'firefox-carrier-mode',
                options: [
                  (FirefoxCarrierMode.overWarp, strings.firefoxModeOverWarp),
                  (FirefoxCarrierMode.direct, strings.firefoxModeDirect),
                ],
                selected: core.firefoxCarrierMode,
                onSelect: (v) =>
                    store.updateCore((c) => c.firefoxCarrierMode = v),
              ),
              const SubSectionDivider(),
              SettingInfoText(
                core.firefoxCarrierMode == FirefoxCarrierMode.direct
                    ? strings.firefoxModeDirectDesc
                    : strings.firefoxModeOverWarpDesc,
              ),
            ],
          ),
        ),

        // ---- Section: process-scoped Firefox DNS (the resolver for
        // Firefox's separate pre-connect roles — the WebChannel sign-in,
        // initial discovery and the explicit DNS probe; in the DIRECT
        // mode it also resolves the Fastly edge for the direct data
        // plane's dials, since those no longer resolve at the carrier's
        // remote end). System or DoH. ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconSwap1,
          title: strings.secFirefoxDns,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: _FirefoxDnsCard(store: store),
        ),

        // ---- Section: the WARP carrier leg (the owner's decree:
        // «پروتکل فایرفاکس رو به صورت دیفالت اور وارپ کنی … کاربر از
        // تنظیمات فایرفاکس بتونه پروتکل هسته ایتر رو خودش انتخاب کنه»):
        // the same per-family leg pick the tor and psiphon pages carry,
        // writing CoreSettings.firefoxLegProtocol. 1.6.0 (round 4):
        // the section renders in BOTH modes — the initial connection
        // stages ride the picked leg's WARP tunnel in over-WARP and
        // DIRECT alike; only the data plane's path differs.
        // ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconSwap1,
          title: strings.secFirefoxCarrier,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingLabel(strings.firefoxCarrierLabel),
              const SizedBox(height: 10),
              SettingPills<AetherLegProtocol>(
                keyId: 'firefox-aether-leg',
                options: [
                  // The same order + labels as the protocol page's own
                  // tiles (strings.aetherLegName reuses their names).
                  (AetherLegProtocol.wireguard,
                      strings.aetherLegName(AetherLegProtocol.wireguard)),
                  (AetherLegProtocol.masque,
                      strings.aetherLegName(AetherLegProtocol.masque)),
                  (AetherLegProtocol.gool,
                      strings.aetherLegName(AetherLegProtocol.gool)),
                  (AetherLegProtocol.goolClassic,
                      strings.aetherLegName(AetherLegProtocol.goolClassic)),
                  (AetherLegProtocol.mim,
                      strings.aetherLegName(AetherLegProtocol.mim)),
                ],
                selected: core.firefoxLegProtocol,
                onSelect: (v) =>
                    store.updateCore((c) => c.firefoxLegProtocol = v),
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.firefoxLegDesc),
            ],
          ),
        ),

        // ---- Section: the data-plane transport (h2 via the carrier's
        // TCP CONNECT, h3 via its UDP ASSOCIATE — both ride the WARP
        // carrier in over-WARP; in DIRECT both dial the Fastly edge
        // straight from the device) ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconSwap1,
          title: strings.secFirefoxTransport,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingLabel(strings.firefoxTransportLabel),
              const SizedBox(height: 10),
              SettingPills<String>(
                keyId: 'firefox-transport',
                options: [
                  ('h2', strings.firefoxTransportH2),
                  ('h3', strings.firefoxTransportH3),
                ],
                selected: store.firefoxTransport,
                onSelect: store.setFirefoxTransport,
              ),
              const SubSectionDivider(),
              SettingInfoText(
                core.firefoxCarrierMode == FirefoxCarrierMode.direct
                    ? strings.firefoxTransportDirectDesc
                    : strings.firefoxTransportDesc,
              ),
            ],
          ),
        ),
        SizedBox(height: 16 * s),
        SettingInfoText(strings.appliesNextConnect),
      ],
    );
  }

  String _formatTime(BuildContext context, DateTime t) {
    final loc = Localizations.localeOf(context);
    String two(int n) => n.toString().padLeft(2, '0');
    final d = t.toLocal();
    // Locale-agnostic HH:mm — the label is informational only.
    return '${two(d.hour)}:${two(d.minute)}'
        '${loc.languageCode == 'fa' ? '، ' : ' '}${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

/// v1.7.0 (the owner's round 5) — the remaining-data card on the Firefox
/// settings page: the LIVE value (the `--usage` role — fetched at page
/// open, after sign-in, on connect, and from this refresh button), the
/// honest «نامحدود» / «—» placeholders, the reset stamp when Guardian
/// reports one, and the refresh walk's scan-loading rings — the user
/// SEES the backend operation the moment they press.
class _FirefoxQuotaCard extends StatelessWidget {
  const _FirefoxQuotaCard({required this.store});

  final ConnectionStore store;

  /// The app's own bytes format (the settings pill's precedent: Latin
  /// digits + MB/GB, LTR-locked by the value row).
  static String _formatBytes(int bytes) {
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) {
      final v = (bytes / gb)
          .toStringAsFixed(bytes >= gb * 10 ? 0 : 1)
          .replaceFirst(RegExp(r'\.0$'), '');
      return '$v GB';
    }
    return '${bytes ~/ mb} MB';
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final quota = store.firefoxQuota;
    final String value;
    if (quota == null) {
      value = '—'; // never known — the honest placeholder
    } else if (quota.unlimited) {
      value = strings.firefoxQuotaUnlimited;
    } else {
      value = _formatBytes(quota.remainingBytes ?? 0);
    }
    final reset = quota?.resetAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.firefoxQuotaLabel,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight: FontWeight.w400,
                      fontSize: 11 * s,
                      color: AethColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 3 * s),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      value,
                      style: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w700,
                        fontSize: 16 * s,
                        color: AethColors.accentConnected,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (reset != null && !quota!.unlimited)
              Padding(
                padding: EdgeInsets.only(left: 12 * s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      strings.firefoxQuotaResetLabel,
                      style: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w400,
                        fontSize: 11 * s,
                        color: AethColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: 3 * s),
                    Text(
                      _formatReset(context, reset),
                      style: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w600,
                        fontSize: 12 * s,
                        color: AethColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        SizedBox(height: 8 * s),
        SettingActionButton(
          keyId: 'firefox-quota-refresh',
          label: strings.firefoxQuotaRefresh,
          busy: store.firefoxQuotaRefreshing,
          busyLabel: strings.firefoxQuotaRefreshing,
          onTap: () => store.refreshFirefoxQuota(),
        ),
      ],
    );
  }

  String _formatReset(BuildContext context, DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = t.toLocal();
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}


/// DNS for Firefox's separate pre-connect roles (WebChannel sign-in,
/// initial discovery and the explicit DNS probe). Once Firefox over WARP
/// is active, tunnel-server hostnames are resolved by the Aether carrier's
/// DNS because the Go engine sends them through Aether SOCKS without local
/// resolution. Chromium speculative DNS prefetch may still use system DNS.
class _FirefoxDnsCard extends StatefulWidget {
  const _FirefoxDnsCard({required this.store});

  final ConnectionStore store;

  @override
  State<_FirefoxDnsCard> createState() => _FirefoxDnsCardState();
}

class _FirefoxDnsCardState extends State<_FirefoxDnsCard> {
  String _endpoint = '';
  String _bootstrap = '';
  bool _testing = false;
  bool _setupFailed = false;
  List<Map<String, dynamic>>? _probeEvents;

  @override
  void initState() {
    super.initState();
    _endpoint = widget.store.firefoxDnsEndpoint;
    _bootstrap = widget.store.firefoxDnsBootstrapIps.join(', ');
    _restoreFields();
  }

  Future<void> _runDnsProbe() async {
    setState(() {
      _testing = true;
      _setupFailed = false;
      _probeEvents = null;
    });
    try {
      final events = await widget.store.firefoxDnsProbe();
      if (!mounted) return;
      setState(() {
        // null = the role never produced events (a setup failure or a
        // timeout) — its own message, never the per-domain one.
        _setupFailed = events == null;
        _probeEvents = events ?? const [];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _setupFailed = true;
        _probeEvents = const [];
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _restoreFields() async {
    await widget.store.loadFirefoxDnsSettings();
    if (!mounted) return;
    _endpoint = widget.store.firefoxDnsEndpoint;
    _bootstrap = widget.store.firefoxDnsBootstrapIps.join(', ');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final store = widget.store;
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final doh = store.firefoxDnsMode == 'doh';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingLabel(strings.firefoxDnsMode),
        SizedBox(height: 10 * s),
        SettingPills<String>(
          keyId: 'firefox-dns-mode',
          options: [
            ('system', strings.firefoxDnsSystem),
            ('doh', strings.firefoxDnsDoH),
          ],
          selected: store.firefoxDnsMode,
          onSelect: (value) {
            store.setFirefoxDnsMode(value);
            setState(() => _probeEvents = null);
          },
        ),
        if (doh) ...[
          SizedBox(height: 16 * s),
          SettingLabel(strings.firefoxDnsProvider),
          SizedBox(height: 10 * s),
          SettingPills<String>(
            keyId: 'firefox-dns-provider',
            options: const [
              ('cloudflare', 'Cloudflare'),
              ('google', 'Google'),
              ('quad9', 'Quad9'),
              ('custom', 'Custom'),
            ],
            selected: store.firefoxDnsProvider,
            onSelect: (value) {
              store.setFirefoxDnsProvider(value);
              setState(() => _probeEvents = null);
            },
          ),
          if (store.firefoxDnsProvider == 'custom') ...[
            SizedBox(height: 16 * s),
            SettingField(
              key: ValueKey('firefox-dns-endpoint-$_endpoint'),
              keyId: 'firefox-dns-endpoint',
              label: strings.firefoxDnsEndpoint,
              hint: 'https://1.2.3.4/dns-query',
              initial: _endpoint,
              onChanged: (value) => _endpoint = value,
            ),
            // 1.7.0 — the honest incomplete hint: an empty custom
            // endpoint degrades the EFFECTIVE mode to system (never an
            // invalid engine line) — the user must know why.
            if (store.firefoxDnsCustomIncomplete)
              SettingInfoText(strings.firefoxDnsCustomIncomplete),
          ],
          SizedBox(height: 12 * s),
          SettingField(
            key: ValueKey('firefox-dns-bootstrap-$_bootstrap'),
            keyId: 'firefox-dns-bootstrap',
            label: strings.firefoxDnsBootstrap,
            hint: 'Optional IP addresses',
            initial: _bootstrap,
            onChanged: (value) => _bootstrap = value,
          ),
          SizedBox(height: 12 * s),
          SettingActionButton(
            keyId: 'firefox-dns-save',
            label: strings.firefoxDnsSave,
            onTap: () {
              store.setFirefoxDnsCustom(_endpoint, _bootstrap);
              setState(() => _probeEvents = null);
              FocusScope.of(context).unfocus();
            },
          ),
        ],
        SizedBox(height: 14 * s),
        // 1.7.0 — the test button itself carries the scan-loading rings
        // while the probe runs (the owner's round 5: the user SEES the
        // backend operation the moment they press).
        SettingActionButton(
          keyId: 'firefox-dns-test',
          label: strings.firefoxDnsTestButton,
          busy: _testing,
          busyLabel: strings.firefoxDnsTesting,
          onTap: _runDnsProbe,
        ),
        if (_probeEvents != null) ...[
          SizedBox(height: 10 * s),
          Builder(builder: (context) {
            Map<String, dynamic>? summary;
            for (final event in _probeEvents!) {
              if (event['event'] == 'dnsProbeSummary') {
                summary = event;
                break;
              }
            }
            final ok = summary?['ok'] == true;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingInfoText(
                  // The role never produced events (setup failure or
                  // timeout) — its own message, distinct from the
                  // per-domain "some requests failed".
                  _setupFailed
                      ? strings.firefoxDnsSetupFailed
                      : ok
                          ? strings.firefoxDnsTestSuccess
                          : strings.firefoxDnsTestFailed,
                ),
                for (final event in _probeEvents!)
                  if (event['event'] == 'dnsProbe')
                    SettingInfoText(
                      "${event['domain']?.toString() ?? '—'} · "
                          "${(event['addresses'] as List?)?.join(', ') ?? (event['error'] as String? ?? '—')} · "
                          "${event['elapsedMs']?.toString() ?? '0'} ms",
                    ),
              ],
            );
          }),
        ],
        const SubSectionDivider(),
        SettingInfoText(strings.firefoxDnsDesc),
        const SubSectionDivider(),
        SettingInfoText(strings.firefoxDnsWebViewNote),
      ],
    );
  }
}
