/// The home screen — LOOK 1 keeps the v4.x four-band column; LOOK 2 is the
/// v5 «نمای 2» redesign (owner round 19), pixel-cut from the committed
/// mockups «نمای 2-متصل/قطع» (402×874 @3×) and the owner's own CSS:
///
///   top bar → status pill (y 198) → connect button (160dp @ 307) →
///   the CURVED WHITE SHEET (top edge y 470, U-dip to 500, shadow
///   0 −16 95 rgba(0,0,0,.09)) carrying the stats row (y 532: DOWN ·
///   speed-test · UP) → the flag wheel (y 636) → the country row
///   (y 703) → the protocol card (y 775).
///
/// The pill sits ABOVE the hero in look 2 (the v4.x order is reversed);
/// the hero is BOTTOM-anchored in the flex band so the button's white
/// base stays glued to the sheet's crown (the merged-blob look of the
/// mockups) on every device height.
///
/// v5.1 (owner round 20 — the merge + the geometry repair): the MOTION
/// LINE (feature/motion-phase3) is merged in — the ConnectHalo director,
/// the spark loader, the shimmer edge, the tap ripple, the smoke field and
/// the circles-selector all live here again — and the look-2 sheet is
/// re-anchored so its CONTENT is laid out crown-down with the design's own
/// rhythm (62 + 74 + 27 + 115 + 27 + 62 = 367; the card's bottom lands at
/// design y 837 with the FULL 37px margin below it) instead of riding the
/// live bottom inset: the card can no longer sink under the glass on any
/// device, and the DOWN/UP stat groups ride the 33px page margins like
/// the mockups (they no longer hug the screen edges). The hero halos are
/// OverflowBox-positioned so the button's box NEVER resizes when a halo
/// mounts — the connect button stays exactly where it is when tapped
/// (owner: «وقتی روی دکمه اتصال نمای 2 کلیک میکنی باید جایگاهش همونجا
/// بمونه و بالا نره»).
///
/// v5.2 (owner round 21 — the branch repair + the four decrees): the
/// round's work now rides THE LINE THAT OWNS THE APP (fix/owner-round-2,
/// which already carries the motion line via the round-20 merge) — the
/// old motion-line base still held the pre-retirement app and has no
/// place under the new changes. On top of it: the green/red gradient
/// pair is carried to EVERY other green/red element (the speed-page
/// start core, the look-1 FAB, the look-1 logo tint, the ping readout
/// and this file's failure caption), the dark↔light mode transition is
/// repaired (see core/fx/theme_reveal.dart + pattern_sides.dart — the
/// pattern-ink lerp, the ticker vendor, the double-tap race, the 420 ms
/// window), and the DOWN/UP readouts decode through the ping readout's
/// own [HyperText] walk (bottom_panel.dart).
///
/// v6 (owner round 23) — the look-1 re-cut lands on the MOTION LINE
/// (feature/motion-phase3, the branch that owns the app): the spark
/// loader owns look 1's walk again, the flutterfx ripple family owns
/// look 2's, the GitHub-spark burst owns the landing on both, look 1
/// grows its own three-layer status chip + its own pattern placement +
/// a real speed-button/pill gap, and the look-2 connect button rides
/// the re-cut three-layer «Group 45».
///
/// v4.45 (merged onto the round-23 line, 2026-11-24) — the protocol
/// selection BOTTOM SHEET: the home protocol card no longer pushes the
/// v4.19 protocol PAGE; it slides the redesigned flutterfx-style sheet up
/// over the scaling home (the 2×6 grid of 159×67 r17 protocol cards, the
/// green-gradient + 4px-ring selected state — the owner's «انتخاب
/// پروتکل» CSS, see protocol_sheet/protocol_sheet.dart).
///
/// State honesty: every visual (colors, ping, speed button, stats) derives
/// from the REAL [ConnectionStore] state — nothing shows "connected" before
/// the engine reports it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../connection/connection_state.dart';
import '../../connection/connection_store.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/fx/connect_ripple.dart';
import '../../core/fx/github_spark.dart';
import '../../core/motion.dart';
import '../../core/motion_widgets.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_screen.dart';
import '../speedtest/speed_test_page.dart';
import 'protocol_sheet/protocol_sheet.dart';
import 'widgets/bottom_panel.dart';
import 'widgets/connect_core.dart';
import 'widgets/glow_pill.dart';
import 'widgets/hero_logo.dart';
import 'widgets/location_header.dart';
import 'widgets/pattern_sides.dart';
import 'widgets/top_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final ConnectionStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// The widget's store, re-exposed under the old name so every method
  /// reads exactly like the stateless-era code.
  ConnectionStore get store => widget.store;

  /// v4.45 — the protocol bottom sheet's handle (the flutterfx
  /// controller pattern): the home protocol card opens the sheet over
  /// the scaling home instead of pushing the retired protocol page.
  final ProtocolSheetController _protocolSheet = ProtocolSheetController();

  @override
  void dispose() {
    _protocolSheet.detach();
    super.dispose();
  }

  /// v4.24 — the REAL speed test page (promoted from the v4.14
  /// placeholder sheet; pixel-faithful to the three committed frames).
  void _openSpeedTest(BuildContext context) {
    Navigator.of(context).push(
      speedTestPageRoute(
        store: store,
        style: store.effectiveMotionStyle(context),
      ),
    );
  }

  /// Step 2: the REAL settings main page (pixel-faithful to the design
  /// frame). v4.17 — owner settings round #4: «به صفحه و کارت ها انیمیشن
  /// ورود و خروج اضافه کن» — the route animates and the screen staggers
  /// its blocks on the route timeline (see [SettingsScreen._enter]).
  /// v4.25 — the push rides [aethPageRoute]: the page enters with the
  /// SELECTED STYLE'S own personality (SILK fade-rise / TIDE zoom-
  /// dissolve / SPRING pop / BLINK fade / OFF instant cut).
  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      aethPageRoute<void>(
        style: store.effectiveMotionStyle(context),
        builder: (_) => SettingsScreen(store: store),
      ),
    );
  }

  /// v4.45 — the protocol selection BOTTOM SHEET (the owner's redesign):
  /// the home protocol card slides the sheet up over the scaling home
  /// (the flutterfx bottom-sheet choreography — the 2×6 grid of 159×67
  /// protocol cards), replacing the retired v4.19 protocol page.
  /// Selecting a protocol still auto-returns (the sheet closes itself
  /// after the green crossfade lands).
  void _openProtocolSheet() {
    _protocolSheet.open();
  }

  /// v4.19 (#3) — tap-to-cancel, owner device test: «حین اتصال کاربر باید
  /// بتونه اتصال رو کنسل کنه». Every connect surface (hero logo, look-2
  /// center button, bottom FAB) routes through THIS toggle: while the
  /// engine walk is in flight a tap CANCELS the pending connection (the
  /// store's canceling disconnect — legal edges starting/…/connecting →
  /// disconnecting), instead of being silently ignored by the old
  /// single-flight guard.
  void _toggleConnection() {
    switch (store.state) {
      case VpnState.starting:
      case VpnState.waitingForPermissions:
      case VpnState.connecting:
      case VpnState.connected:
        store.disconnect();
      case VpnState.failed:
      case VpnState.reconnecting:
      case VpnState.disconnected:
        store.connect();
      case VpnState.disconnecting:
        break; // one transition already in flight — ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final size = MediaQuery.sizeOf(context);
        final s = size.width / AethGeometry.refWidth;
        final style = store.effectiveMotionStyle(context);
        final connected = store.isConnected;
        final isLookOne = store.homeLook == HomeLook.one;
        // The scanning walk: starting → connecting (→ reconnecting).
        final showScan =
            !connected &&
            (store.state == VpnState.starting ||
                store.state == VpnState.connecting ||
                store.state == VpnState.reconnecting);
        // v6 (owner round 23: «انیمیشن دکمه اتصال وسط صفحه در نمای 1 حین
        // تلاش برای اتصال رو چرا حذف کردی؟ برشگردون به حالت قبل») — the
        // SPARK LOADER's walk flag is BACK: every state in which the
        // engine walks toward a session marches look 1's logo in quarter
        // turns ([SparkLoaderSpin]); look 2's connecting story is the
        // flutterfx RIPPLE family instead ([ConnectRipple]).
        final walking = !connected &&
            (store.state == VpnState.starting ||
                store.state == VpnState.waitingForPermissions ||
                store.state == VpnState.connecting ||
                store.state == VpnState.reconnecting);

        final locationHeader = LocationHeader(
          connected: connected,
          // The motion personality — the circles-selector arrival pop on
          // the flag wheel rides its tempos and dies under its kill-switch.
          style: style,
          // v4.21 — the band rule follows the committed mode
          // (single-knob selection after the v4.20 revert).
          protocolIsTorOrPsiphon:
              store.effectiveProtocol.isTor ||
              store.effectiveProtocol.isPsiphon,
          // v4.21 — the wheel is a real, scrollable SELECTOR for the
          // whole psiphon + tor families while DISCONNECTED, and locks on
          // the connected location once connected (owner device-test
          // round 3). v5: non-family protocols keep the band VISIBLE but
          // GREYSCALE + locked while disconnected (round 19).
          selectable: store.wheelSelectable,
          allowedCodes: store.wheelAllowedCodes,
          autoEntry: store.wheelAutoEntry,
          anchorCode: store.wheelAnchorCode,
          pingMs: store.pingMs,
          exitCountryCode: store.exitCountryCode,
          onCountrySelected: store.selectLocation,
        );

        // v1.0.2 — the home tree reads the style through the scope too
        // (the theme tile's swap, the shared value-text fallbacks).
        return MotionScope(
          style: style,
          child: Scaffold(
            backgroundColor: AethColors.bgScreen,
            // v4.25 — `StackFit.expand` for uniformity with every other page
            // (the pattern-placement fix; home already fills via the Column
            // `Expanded`, but the body now pins itself explicitly).
            // v4.45 — the protocol BOTTOM SHEET host: the whole home is
            // the sheet's [mainContent] (it scales/slides/rounds while
            // the sheet opens — the flutterfx recipe); closed, it renders
            // untouched.
            body: ProtocolSheetHost(
              controller: _protocolSheet,
              store: store,
              mainContent: Stack(
              fit: StackFit.expand,
              children: [
                // v5.3 (the owner's decree: «انیمیشن حاله سبز در حالت اتصال
                // رو کلا حذف کن و فقط پترن ها باشن») — the connected SMOKE
                // FIELD and the pattern DRIFT are both RETIRED: the tunnel's
                // green state shows ONLY the static pattern artwork (the
                // green canvases), never a second of ambient motion. The
                // drift survives solely on the ENGINE WALK (the scan feel
                // while connecting) — see [ConnectionStore.patternsAlive].
                // Edge patterns (red ↔ green, animated crossfade). The
                // appearance switch can turn them off. v5: the look-2 curved
                // sheet COVERS them below its crown exactly like the
                // mockups (the sheet is painted above in z-order).
                if (store.showPatterns)
                  Positioned.fill(
                    child: PatternSides(
                      connected: connected,
                      style: style,
                      active: store.patternsAlive,
                      // v6 (owner round 23: «در نمای 1 صفحه اصلی جایگاه
                      // پترن های چپ و راست باید متفاوت از نمای 2 باشه …
                      // پترن سمت چپ یک سوم پایین تر از وسط صفحه و پترن
                      // سمت راست باید یک سوم بالاتر از وسط صفحه») — the
                      // home's LOOK 1 carries its own placement: each
                      // art's ink centre a third of the screen away from
                      // the middle (left BELOW, right ABOVE), both states.
                      lookOne: isLookOne,
                    ),
                  ),
                SafeArea(
                  // v5 — look 2's curved sheet bleeds to the PHYSICAL bottom
                  // edge (the mockups run it past the home indicator); only
                  // look 1 keeps the bottom inset inside the SafeArea.
                  bottom: isLookOne,
                  child: Column(
                    children: [
                      // v4.12: extra top gap so the app never crowds the
                      // status-bar / notch area.
                      SizedBox(height: AethGeometry.topSafeExtraGap * s),
                      HomeTopBar(
                        onSettings: () => _openSettings(context),
                        store: store,
                      ),
                      if (isLookOne) ...[
                        SizedBox(height: AethGeometry.gapTopbarToLocation * s),
                        locationHeader,
                        // Hero band: the logo centers in the flex region.
                        Expanded(
                          child: Center(
                            child: heroStack(
                              context, s, style, connected, walking),
                          ),
                        ),
                        // v5.3 (the owner's decrees) — the session TABLE
                        // (duration / latency / session data — the old
                        // [HomeWidgetDeck]) is REMOVED from the app
                        // entirely («جدولی که مدت اتصال، تاخیر و داده جلسه
                        // رو نمایش میده باید کلا از اپ حذف بشه»). The
                        // bottom DOWN/UP cards stay look-1's own surface,
                        // now recording KILOBYTES exactly like «نمای 2»'s
                        // readouts («کارت های نمایش دانلود و آپلود باید
                        // مثل کارت های نمای 2 حتی تغیرات مصرف کیلوبایتی رو
                        // هم باید ثبت کنن») — the same formatter, the same
                        // HyperText decode, the same KB ticks.
                        SpeedTestButton(
                          visible: connected,
                          connected: connected,
                          style: style,
                          onTap: () => _openSpeedTest(context),
                        ),
                        // v6 — the owner's «باید کمی فاصله داشته باشن»:
                        // the 1px kiss is gone; the speed button and the
                        // (now 38px-tall, three-layer) pill breathe apart.
                        SizedBox(height: AethGeometry.gapSpeedToPill * s),
                        // v6 — LOOK 1's own three-layer chip («Group 119»,
                        // 140×38): the layered composition + the
                        // «غیرفعال» label. Look 2 keeps the 126×30 gradient
                        // chip above the hero.
                        StatusPill(
                          state: store.state,
                          style: style,
                          layered: true,
                        ),
                        failureCaption(context, s),
                        SizedBox(height: AethGeometry.gapPillToPanel * s),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AethGeometry.pageHPadding * s,
                          ),
                          child: BottomPanel(
                            connected: connected,
                            style: style,
                            // v1.0.2 — the panel carries the REAL state now:
                            // the FAB's three-slot ride + the protocol label
                            // swap.
                            state: store.state,
                            selectedProtocol: store.smartDisplayProtocol,
                            protocolLabel: protocolLabel(strings, showScan),
                            downBytes: store.downBytes,
                            upBytes: store.upBytes,
                            showConnectButton: true,
                            onProtocolCardTap: () =>
                                _openProtocolSheet(),
                            onConnect: _toggleConnection,
                            onDisconnect: _toggleConnection,
                          ),
                        ),
                        SizedBox(height: AethGeometry.gapPanelToBottom * s),
                      ] else ...[
                        // v5 «نمای 2» — the pill rides ABOVE the hero.
                        SizedBox(height: AethGeometry.gapTopbarToPill * s),
                        StatusPill(state: store.state, style: style),
                        failureCaption(context, s),
                        // The hero is BOTTOM-anchored: the connect button's
                        // white base stays glued to the sheet's crown. The
                        // band ABSORBS the device-height variance (the air
                        // between the pill and the button grows on taller
                        // screens) so the sheet's crown — and everything
                        // top-anchored inside it — keeps the design position.
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: heroStack(
                              context, s, style, connected, walking),
                          ),
                        ),
                        SizedBox(height: AethGeometry.gapHeroToPanel * s),
                        _LookTwoSheet(
                          store: store,
                          style: style,
                          strings: strings,
                          s: s,
                          connected: connected,
                          locationHeader: locationHeader,
                          protocolLabel: protocolLabel(strings, showScan),
                          onProtocolCardTap: () =>
                              _openProtocolSheet(),
                          onSpeedTap: () => _openSpeedTest(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The hero band's constant Stack — v1.0.2: ONE state-driven [ConnectHalo]
  /// plays BEHIND the central element of BOTH looks (the v4.15 aurora + the
  /// v4.14 scan rings unified and extended to all EIGHT states: ignition /
  /// held / march / aurora+celebration / seek / collapse / error ring),
  /// wrapped by [ConnectShake] on the failed edge; v8a (owner round 18)
  /// retired the connected AURORA on both looks, and v5.3 retired the
  /// round-18 [ShimmerEdge] lap too.
  ///
  /// v6 (owner round 23) — the WALK and the LANDING are re-cut, one look
  /// each: the halo's own walk vocabulary sleeps on BOTH looks now —
  /// LOOK 1's walk is the RESTORED spark-loader march on the logo itself
  /// («برشگردون به حالت قبل»), LOOK 2's is the flutterfx RIPPLE family
  /// breathing behind the button ([ConnectRipple]), and the walk's
  /// landing flourish — the connecting→connected edge — is the GITHUB
  /// SPARK burst ([GitHubSparkBurst]): sparks pour from BEHIND the
  /// button in every direction, once («وقتی اتصال شکل گرفت باید از
  /// انیمیشن GitHub Spark استفاده بشه و از پشت دکمه اتصال وسط صفحه به
  /// سرعت اسپارک به جهات مختلف بریزه»). The CONNECTED steady state
  /// stays perfectly still (the round-22 decree stands).
  ///
  /// v5.1 (owner round 20) — THE HALOS ARE LAYOUT-NEUTRAL: every layer
  /// bigger than the central element rides an [OverflowBox] pinned to the
  /// element's own box, so the Stack's size is the BUTTON's, in every
  /// state. The old build resized the Stack when the 270px scan ring
  /// mounted — and because look 2 anchors the hero to its BOTTOM, the
  /// centered button RODE UP ~35px the moment the walk started. The
  /// button's box is now constant: tap it and it stays exactly where it
  /// is (owner: «جایگاهش همونجا بمونه و بالا نره").
  Widget heroStack(
    BuildContext context,
    double s,
    MotionStyle style,
    bool connected,
    bool walking,
  ) {
    final isLookOne = store.homeLook == HomeLook.one;
    final elementSize = (isLookOne
            ? AethGeometry.heroSize
            : AethGeometry.connectGroupSize) *
        s;
    final haloSize = elementSize * 1.25;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // The state halo family — paints AROUND the element (up to ×1.25
        // of it) without ever resizing the Stack: IgnorePointer keeps it
        // pure decoration, the OverflowBox frees it from the element's
        // tight constraints, Clip.none lets it spill into the band's air.
        // v6: the walk story is per-look (the spark march on the logo for
        // look 1, the ripple family for look 2) and the landing flourish
        // is the GitHub-spark burst on both — the halo keeps the collapse
        // and the error ring.
        IgnorePointer(
          child: SizedBox.square(
            dimension: elementSize,
            child: OverflowBox(
              maxWidth: haloSize,
              maxHeight: haloSize,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  ConnectHalo(
                    state: store.state,
                    style: style,
                    hideWalkStates: true,
                    hideConnectedAura: true,
                    size: haloSize,
                  ),
                  // LOOK 2's connecting animation — the flutterfx ripple
                  // family behind the button (owner round 23).
                  if (!isLookOne)
                    ConnectRipple(
                      state: store.state,
                      style: style,
                      size: haloSize,
                    ),
                  // The landing flourish, both looks — the GitHub-spark
                  // one-shot on the connecting→connected edge.
                  GitHubSparkBurst(
                    state: store.state,
                    style: style,
                    size: haloSize,
                  ),
                ],
              ),
            ),
          ),
        ),
        ConnectShake(
          state: store.state,
          style: style,
          child: isLookOne
              ? PressSpring(
                  style: style,
                  onTap: _toggleConnection,
                  // v6 — the spark march is BACK for the walk (owner
                  // round 23); the 58° pose + the gradient tint stay the
                  // state APPEARANCE, never looping motion.
                  child: HeroLogo(
                    connected: connected,
                    style: style,
                    sparking: walking,
                  ),
                )
              : _CenterConnectButton(
                  store: store,
                  style: style,
                  onTap: _toggleConnection,
                ),
        ),
      ],
    );
  }

  /// The failed state's honest caption under the status pill (v4.20),
  /// shared by both looks — it eats into the flex band in look 2.
  Widget failureCaption(BuildContext context, double s) {
    return AnimatedSize(
      duration: motionDuration(
        store.effectiveMotionStyle(context),
        MotionDurations.quick,
      ),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: store.state == VpnState.failed && store.lastErrorCode != null
          ? Padding(
              padding: EdgeInsets.only(top: 8 * s),
              child: _FailureCaption(
                code: store.lastErrorCode!,
                message: store.lastErrorMessage,
                onTap: () => _openFailureDetails(
                  context,
                  store.lastErrorCode!,
                  store.lastErrorMessage,
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  /// The panel's protocol label (v4.32/v4.35 rule): the SMART session's
  /// own display — the carrying protocol while resolved, the in-flight
  /// candidate + attempt while the walk runs.
  String protocolLabel(AppStrings strings, bool showScan) {
    return store.smartAttempt != null && showScan
        ? (store.smartAttempt!.measuring
              ? strings.smartMeasuringLabel(
                  strings.protocolName(store.smartAttempt!.candidate),
                )
              : strings.smartAttemptLabel(
                  strings.protocolName(store.smartAttempt!.candidate),
                  store.smartAttempt!.attempt,
                  store.smartAttempt!.total,
                ))
        : strings.protocolName(store.smartDisplayProtocol);
  }

  /// v4.20 — the failure details sheet: the engine's own error code + full
  /// message, with a copy button so the owner can hand the exact stage over
  /// (the tunnel failure was previously an anonymous miss: «اپ هنوز هم در
  /// حالت تونل مشکل داره و وصل نمیشه»).
  void _openFailureDetails(
    BuildContext context,
    String code,
    String? message,
  ) {
    final strings = AppStrings.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AethColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AethColors.textSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              strings.failureDetailsTitle,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AethColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              code,
              style: const TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AethColors.statusDisconnected,
              ),
            ),
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  height: 1.6,
                  color: AethColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: '$code\n${message ?? ''}'),
                );
                Navigator.of(sheetContext).pop();
              },
              icon: const Icon(
                Icons.copy_rounded,
                size: 18,
                color: AethColors.accentConnected,
              ),
              label: Text(
                strings.failureDetailsCopy,
                style: const TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: AethColors.accentConnected,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// v4.20 — the failed state's honest caption under the status pill: the
/// engine's own error code («کد خطا: tunnelStartFailed»), tappable for the
/// full details sheet. Rendered ONLY in the failed state; AnimatedSize in
/// [HomeScreen] keeps the layout shift soft.
class _FailureCaption extends StatelessWidget {
  const _FailureCaption({
    required this.code,
    this.message,
    this.onTap,
  });

  final String code;
  final String? message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // v5.2 (owner round 21) — the failure caption carries the
      // redesign's own RED gradient sweep («گردینت سبز و قرمز … برای
      // المان های سبز و قرمز رنگ دیگه هم اعمال کن»): a ShaderMask in
      // srcIn mode over the glyphs, with a matching alpha on both stops
      // (the old flat .85 pose preserved).
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AethColors.redStops[0].withValues(alpha: 0.85),
            AethColors.redStops[1].withValues(alpha: 0.85),
          ],
        ).createShader(bounds),
        child: Text(
          '${strings.failureCodeLabel}: $code',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'IRANYekanX',
            fontWeight: FontWeight.w500,
            fontSize: 11 * s,
            height: 1.4,
            color: AethColors.statusDisconnected.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

/// Look 2: the hero IS the connect button — v5 (owner round 19): the
/// owner's new CSS composition «Group 45» ([ConnectButtonGlow] — the WHITE
/// 160² r60 base + the 108.17² r41 gradient core + the Off glyph), the
/// v4.33 glow stack retired by the redesign. Owner v4.12: plain tap
/// toggles; v4.19 (#3): the toggle logic lives in
/// [HomeScreen._toggleConnection] (tap-to-cancel during the walk); v1.0.2:
/// the REAL state drives the disconnecting tap lock, the press rides the
/// shared [PressSpring] and the tap burst rides [TapRipple].
class _CenterConnectButton extends StatelessWidget {
  const _CenterConnectButton({
    required this.store,
    required this.style,
    required this.onTap,
  });

  final ConnectionStore store;
  final MotionStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConnectButtonGlow(
      connected: store.isConnected,
      state: store.state,
      style: style,
      duration: motionDuration(style, MotionDurations.state),
      curve: style.curve,
      onTap: onTap, // tap-to-toggle (owner v4.12) + cancel (v4.19 #3)
    );
  }
}

/// v5 («نمای 2») — the curved white bottom sheet: the owner's «Rectangle
/// 87» + SVG crown (flat rim, a U-dip to +30 across the centre) with the
/// committed shadow (`0 −16 95 rgba(0,0,0,0.09)`), carrying the stats row,
/// the flag wheel + country row and the protocol card.
///
/// v5.1 (owner round 20) — CROWN-DOWN ANCHORING. The sheet's height is its
/// OWN content (62 crown pad + 74 stats + 27 + 115 band + 27 + 62 card +
/// the 37px design margin = 402 ref px), pinned to the screen's bottom by
/// the column; the hero band above absorbs every device-height delta. The
/// content is laid out TOP-DOWN from the crown, so on the 402×874
/// reference the stats land at y 532, the ring at 633, the row at 703 and
/// the card at 775–837 — design-exact — and the card keeps its FULL 37px
/// margin above the physical bottom on EVERY device (the old build drew
/// `3px + live inset` under the card, which sank it to the glass edge
/// whenever the inset read 0 and pushed it off-screen on inset-heavy
/// devices: owner round 20, «کارت انتخاب پروتکل از صفحه بیرون زده»).
/// A 3-BUTTON nav bar (inset > 29) lifts the card above the bar instead.
class _LookTwoSheet extends StatelessWidget {
  const _LookTwoSheet({
    required this.store,
    required this.style,
    required this.strings,
    required this.s,
    required this.connected,
    required this.locationHeader,
    required this.protocolLabel,
    required this.onProtocolCardTap,
    required this.onSpeedTap,
  });

  final ConnectionStore store;
  final MotionStyle style;
  final AppStrings strings;
  final double s;
  final bool connected;
  final Widget locationHeader;
  final String protocolLabel;
  final VoidCallback onProtocolCardTap;
  final VoidCallback onSpeedTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    // The design's full 37px margin under the card (the reference's
    // home-indicator zone rides inside it); only a genuinely TALLER nav
    // inset (a 3-button bar, > 29) lifts the card above the bar — a
    // gesture inset (≈34) is exactly what the design's own margin
    // already clears, so the card keeps its design y 837 on every
    // gesture device too.
    final bottomPad = bottomInset > 29
        ? bottomInset + 8 * s
        : AethGeometry.gapCardToBottom * s;
    return CustomPaint(
      // The crown paints UNDER the content — the sheet's own fill must
      // never cover the stats row / flags / card riding on it. v5.3: the
      // inks are passed in (palette-read at build time) so the 420 ms
      // mode tween repaints them — see the painter's shouldRepaint.
      painter: _SheetCrownPainter(
        s,
        AethColors.panelShadowInk,
        AethColors.bgScreen,
      ),
      child: Padding(
        // The sheet's empty crown between its top edge and the stats row
        // (design y 470 → 532).
        padding: EdgeInsets.only(top: AethGeometry.panelTopPad * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            HomeStatsRow(
              connected: connected,
              style: style,
              downBytes: store.downBytes,
              upBytes: store.upBytes,
              onSpeedTap: onSpeedTap,
            ),
            SizedBox(height: AethGeometry.gapStatsToFlags * s),
            locationHeader,
            SizedBox(height: AethGeometry.gapRowToCard * s),
            Padding(
              // The card spans x 33–369 on the 402-wide frame.
              padding: EdgeInsets.symmetric(
                horizontal: AethGeometry.pageHPadding * s,
              ),
              child: BottomPanel(
                connected: connected,
                style: style,
                selectedProtocol: store.smartDisplayProtocol,
                protocolLabel: protocolLabel,
                downBytes: store.downBytes,
                upBytes: store.upBytes,
                showConnectButton: false,
                onProtocolCardTap: onProtocolCardTap,
                onConnect: () {},
                onDisconnect: () {},
              ),
            ),
            // The design's full bottom margin (see the class doc).
            SizedBox(height: bottomPad),
          ],
        ),
      ),
    );
  }
}

/// Paints the sheet's crown: the blurred shadow ABOVE the top edge + the
/// bg-coloured fill whose top line follows the owner's SVG path (flat rim
/// 0–96 · U-dip to +30 across the centre · flat rim 301–402, design px).
///
/// v5.3 — the shadow ink rides the PALETTE now (light rgba(0,0,0,0.09) /
/// night rgba(255,255,255,0.09), the owner's dark CSS «Rectangle 87»), and
/// [shouldRepaint] compares BOTH inks — the old `s`-only test left the
/// crown painted in the PREVIOUS mode's colors through the whole 420 ms
/// theme tween (the painter instance changes, but s does not).
class _SheetCrownPainter extends CustomPainter {
  _SheetCrownPainter(this.s, this.shadowInk, this.fill);

  final double s;
  final Color shadowInk;
  final Color fill;

  Path _crownPath(Size size) {
    final k = s;
    Path path = Path()..moveTo(0, 0);
    path = path
      ..lineTo(AethGeometry.panelDipX1 * k, 0)
      ..cubicTo(
        114.511 * k,
        0,
        132.325 * k,
        6.208 * k,
        AethGeometry.panelDipCx1 * k,
        17.616 * k,
      )
      ..cubicTo(
        156.933 * k,
        25.731 * k,
        169.606 * k,
        AethGeometry.panelDipDepth * k,
        AethGeometry.panelDipX2 * k,
        AethGeometry.panelDipDepth * k,
      )
      ..lineTo(AethGeometry.panelDipX3 * k, AethGeometry.panelDipDepth * k)
      ..cubicTo(
        227.894 * k,
        AethGeometry.panelDipDepth * k,
        240.567 * k,
        25.731 * k,
        AethGeometry.panelDipCx2 * k,
        17.616 * k,
      )
      ..cubicTo(
        265.175 * k,
        6.208 * k,
        282.989 * k,
        0,
        AethGeometry.panelDipX4 * k,
        0,
      )
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _crownPath(size);
    // The committed shadow — the SVG filter: feOffset dy −16, feGaussian
    // σ47.5 — in the palette's own ink (α 0.09 rides inside the color).
    // Painted FIRST so the fill covers its lower half.
    canvas.save();
    canvas.translate(0, AethGeometry.panelShadowDy * s);
    canvas.drawPath(
      path,
      Paint()
        ..color = shadowInk
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          AethGeometry.panelShadowSigma * s,
        ),
    );
    canvas.restore();
    canvas.drawPath(path, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_SheetCrownPainter oldDelegate) =>
      oldDelegate.s != s ||
      oldDelegate.shadowInk != shadowInk ||
      oldDelegate.fill != fill;
}
