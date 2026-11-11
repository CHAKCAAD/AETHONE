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
import '../../../connection/transport_modes.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../l10n/app_strings.dart';
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
    widget.store.refreshFirefoxAccount();
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
              // The honesty label (live / cached + the fetch time).
              SettingInfoText(
                fetchedAt == null
                    ? listLabel
                    : '$listLabel — ${_formatTime(context, fetchedAt)}',
              ),
            ],
          ),
        ),

        // ---- Section: process-scoped Firefox DNS ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconSwap1,
          title: strings.secFirefoxDns,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: _FirefoxDnsCard(store: store),
        ),

        // ---- Section: the data-plane transport ----
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
              SettingInfoText(strings.firefoxTransportDesc),
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


/// Firefox-only DNS preferences. The Go engine consumes these settings;
/// the embedded WebView login remains on Android WebView networking until
/// its app-scoped proxy bridge is implemented and verified.
class _FirefoxDnsCard extends StatefulWidget {
  const _FirefoxDnsCard({required this.store});

  final ConnectionStore store;

  @override
  State<_FirefoxDnsCard> createState() => _FirefoxDnsCardState();
}

class _FirefoxDnsCardState extends State<_FirefoxDnsCard> {
  late final TextEditingController _endpoint = TextEditingController(
    text: widget.store.firefoxDnsEndpoint,
  );
  late final TextEditingController _bootstrap = TextEditingController(
    text: widget.store.firefoxDnsBootstrapIps.join(', '),
  );

  @override
  void initState() {
    super.initState();
    _restoreFields();
  }

  Future<void> _restoreFields() async {
    await widget.store.loadFirefoxDnsSettings();
    if (!mounted) return;
    _endpoint.text = widget.store.firefoxDnsEndpoint;
    _bootstrap.text = widget.store.firefoxDnsBootstrapIps.join(', ');
    setState(() {});
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _bootstrap.dispose();
    super.dispose();
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
          onSelect: store.setFirefoxDnsMode,
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
            onSelect: store.setFirefoxDnsProvider,
          ),
          if (store.firefoxDnsProvider == 'custom') ...[
            SizedBox(height: 16 * s),
            SettingField(
              key: ValueKey('firefox-dns-endpoint-${_endpoint.text}'),
              keyId: 'firefox-dns-endpoint',
              label: strings.firefoxDnsEndpoint,
              hint: 'https://dns.example/dns-query',
              initial: _endpoint.text,
              onChanged: (value) => _endpoint.text = value,
            ),
            SizedBox(height: 12 * s),
            SettingField(
              key: ValueKey('firefox-dns-bootstrap-${_bootstrap.text}'),
              keyId: 'firefox-dns-bootstrap',
              label: strings.firefoxDnsBootstrap,
              hint: 'Optional IP addresses',
              initial: _bootstrap.text,
              onChanged: (value) => _bootstrap.text = value,
            ),
            SizedBox(height: 12 * s),
            SettingActionButton(
              keyId: 'firefox-dns-save',
              label: strings.firefoxDnsSave,
              onTap: () {
                store.setFirefoxDnsCustom(_endpoint.text, _bootstrap.text);
                FocusScope.of(context).unfocus();
              },
            ),
          ],
        ],
        const SubSectionDivider(),
        SettingInfoText(strings.firefoxDnsDesc),
        const SubSectionDivider(),
        SettingInfoText(strings.firefoxDnsWebViewNote),
      ],
    );
  }
}
