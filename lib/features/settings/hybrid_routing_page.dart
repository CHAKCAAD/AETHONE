/// v1.1.0 — «مسیریابی ترکیبی»: hybrid per-tunnel routing rules for ONE
/// hybrid protocol (the profile). Reachable only while a hybrid protocol
/// is selected (routing page entry). Every control here edits
/// [ConnectionStore.hybridRules]; the store pushes the rules to the live
/// native engine (HybridRouter.kt via the patched zeptun) when that
/// profile's tunnel is up, and the page shows what the ENGINE reports as
/// applied — never a success the engine did not confirm.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../connection/app_tunnel.dart';
import '../../connection/connection_store.dart';
import '../../connection/hybrid_routing.dart';
import '../../connection/platform_engine_adapter.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';
import '../../l10n/app_strings.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class HybridRoutingPage extends StatefulWidget {
  const HybridRoutingPage({super.key, required this.store, required this.profile});

  final ConnectionStore store;
  final ProtocolId profile;

  @override
  State<HybridRoutingPage> createState() => _HybridRoutingPageState();
}

class _HybridRoutingPageState extends State<HybridRoutingPage> {
  Timer? _poll;

  ConnectionStore get store => widget.store;
  ProtocolId get profile => widget.profile;
  List<HybridTunnel> get tunnels => HybridRouting.profileOf(profile) ?? const [];
  List<HybridRule> get rules => store.hybridRulesFor(profile);

  @override
  void initState() {
    super.initState();
    _refresh();
    // The live counters: refreshed while the page is open (cheap channel
    // read of in-memory counters — no network).
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  void _refresh() {
    if (store.hybridLive(profile)) unawaited(store.refreshHybridStatus());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _save(List<HybridRule> next) => store.setHybridRules(profile, next);

  void _upsert(HybridRule rule) {
    final list = List.of(rules);
    final i = list.indexWhere((r) => r.id == rule.id);
    i < 0 ? list.add(rule) : list[i] = rule;
    unawaited(_save(list));
  }

  void _remove(HybridRule rule) {
    unawaited(_save([for (final r in rules) if (r.id != rule.id) r]));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final defaultTunnel = tunnels.firstWhere((t) => t.isDefault);
    return SubPageFrame(
      store: store,
      title: strings.hybridRouting,
      icon: AppAssets.iconArrowSwapHorizontal,
      subtitle: strings.hybridRoutingDesc,
      children: () {
        final all = rules;
        final invalid = HybridRouting.invalidRules(profile, all).map((r) => r.id).toSet();
        final status = store.hybridLive(profile) ? store.hybridStatus : null;
        final engineRejected = <String, String>{
          for (final r in (status?['rejected'] as List?) ?? const [])
            if (r is Map) r['id'].toString(): r['reason'].toString(),
        };
        final hits = (status?['hits'] as Map?) ?? const {};
        final routed = (status?['routed'] as Map?) ?? const {};
        final appSupported = status?['appRoutingSupported'] != false;
        _RuleState stateOf(HybridRule r) {
          if (invalid.contains(r.id)) return _RuleState.invalidTunnel;
          if (engineRejected.containsKey(r.id) && engineRejected[r.id] != 'tunnel-unavailable') {
            return _RuleState.engineRejected;
          }
          if (!r.enabled) return _RuleState.off;
          return _RuleState.active;
        }

        Widget ruleList(Iterable<HybridRule> list, {required bool app}) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in list)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8 * s),
                    child: _RuleRow(
                      key: ValueKey('hybrid-rule-${r.id}'),
                      rule: r,
                      app: app,
                      tunnels: tunnels,
                      state: stateOf(r),
                      hits: (hits[r.id] as num?)?.toInt(),
                      onTunnel: (t) => _upsert(r.copyWith(tunnel: t)),
                      onEnabled: (v) => _upsert(r.copyWith(enabled: v)),
                      onDelete: () => _remove(r),
                      onEdit: app ? null : () => _openEditor(context, existing: r),
                    ),
                  ),
              ],
            );

        final apps = all.where((r) => r.kind == HybridRuleKind.app);
        final domains = all.where((r) =>
            r.kind == HybridRuleKind.domain || r.kind == HybridRuleKind.wildcard);
        final ips = all.where((r) => r.kind == HybridRuleKind.cidr);

        return [
          // ---- the profile: routes + where the rest goes + live state ----
          SubSectionHeading(icon: AppAssets.iconShuffle1, title: strings.hybridRoutes),
          const SubSectionGap.headingToCard(),
          SubSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in tunnels)
                  Padding(
                    padding: EdgeInsets.only(bottom: 6 * s),
                    child: _TunnelLine(
                      tunnel: t,
                      flows: (routed[t.id] as num?)?.toInt(),
                      defaultLabel: strings.hybridDefaultRoute,
                    ),
                  ),
                const SubSectionDivider(),
                SettingInfoText(
                  strings.hybridDefaultNote.replaceAll('{route}', defaultTunnel.label),
                ),
                const SubSectionDivider(),
                _StatusLine(store: store, profile: profile, status: status),
              ],
            ),
          ),

          // ---- A. apps ----
          SizedBox(height: 24 * s),
          SubSectionHeading(icon: AppAssets.iconCategory, title: strings.hybridApps),
          const SubSectionGap.headingToCard(),
          SubSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!appSupported)
                  SettingInfoText(strings.hybridAppUnsupported)
                else ...[
                  if (apps.isEmpty) SettingInfoText(strings.hybridEmpty) else ruleList(apps, app: true),
                  SizedBox(height: 4 * s),
                  SettingActionButton(
                    keyId: 'hybrid-add-apps',
                    label: strings.hybridAddApps,
                    onTap: () => _openAppPicker(context),
                  ),
                ],
              ],
            ),
          ),

          // ---- B. domains ----
          SizedBox(height: 24 * s),
          SubSectionHeading(icon: AppAssets.iconWebsite, title: strings.hybridDomains),
          const SubSectionGap.headingToCard(),
          SubSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (domains.isEmpty) SettingInfoText(strings.hybridEmpty) else ruleList(domains, app: false),
                SizedBox(height: 4 * s),
                SettingActionButton(
                  keyId: 'hybrid-add-domain',
                  label: strings.hybridAddDomain,
                  onTap: () => _openEditor(context, kind: HybridRuleKind.domain),
                ),
                const SubSectionDivider(),
                SettingInfoText(strings.hybridWildcardNote),
              ],
            ),
          ),

          // ---- C. IPs ----
          SizedBox(height: 24 * s),
          SubSectionHeading(icon: AppAssets.iconFilter5, title: strings.hybridIps),
          const SubSectionGap.headingToCard(),
          SubSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ips.isEmpty) SettingInfoText(strings.hybridEmpty) else ruleList(ips, app: false),
                SizedBox(height: 4 * s),
                SettingActionButton(
                  keyId: 'hybrid-add-ip',
                  label: strings.hybridAddIp,
                  onTap: () => _openEditor(context, kind: HybridRuleKind.cidr),
                ),
              ],
            ),
          ),

          SizedBox(height: 16 * s),
          SettingInfoText(strings.hybridPriority),
          SizedBox(height: 8 * s),
          SettingInfoText(strings.hybridLimits),
          SizedBox(height: 16 * s),
        ];
      },
    );
  }

  // ---- domain / IP editor -------------------------------------------------

  Future<void> _openEditor(BuildContext context, {HybridRuleKind? kind, HybridRule? existing}) async {
    final result = await showModalBottomSheet<HybridRule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AethColors.bgScreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _RuleEditor(
        profile: profile,
        tunnels: tunnels,
        rules: rules,
        kind: existing?.kind ?? kind!,
        existing: existing,
      ),
    );
    if (result != null) _upsert(result);
  }

  // ---- app picker ---------------------------------------------------------

  Future<void> _openAppPicker(BuildContext context) async {
    final picked = await Navigator.of(context).push<List<HybridRule>>(
      aethPageRoute<List<HybridRule>>(
        style: store.effectiveMotionStyle(context),
        builder: (_) => _AppPickerPage(
          store: store,
          profile: profile,
          tunnels: tunnels,
          existing: rules.where((r) => r.kind == HybridRuleKind.app).map((r) => r.value).toSet(),
        ),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    unawaited(_save([...rules, ...picked]));
  }
}

enum _RuleState { active, off, invalidTunnel, engineRejected }

// ---------------------------------------------------------------------------
// rows
// ---------------------------------------------------------------------------

TextStyle _t(double s, {double size = 13, FontWeight w = FontWeight.w600, Color? color}) => TextStyle(
      fontFamily: 'IRANYekanX',
      fontWeight: w,
      fontSize: size * s,
      color: color ?? AethColors.textPrimary,
    );

class _TunnelLine extends StatelessWidget {
  const _TunnelLine({required this.tunnel, required this.flows, required this.defaultLabel});

  final HybridTunnel tunnel;
  final int? flows;
  final String defaultLabel;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: appContentDirection(context),
      child: Row(
        children: [
          Container(
            width: 8 * s,
            height: 8 * s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tunnel.isDefault ? AethColors.accentConnected : AethColors.textSecondary,
            ),
          ),
          SizedBox(width: 8 * s),
          Expanded(
            child: Text(
              tunnel.isDefault ? '${tunnel.label} · $defaultLabel' : tunnel.label,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              style: _t(s, size: 12),
            ),
          ),
          Text('127.0.0.1:${tunnel.port}', style: _t(s, size: 10, w: FontWeight.w400, color: AethColors.textSecondary)),
          if (flows != null) ...[
            SizedBox(width: 8 * s),
            Text('· $flows', style: _t(s, size: 10, w: FontWeight.w400, color: AethColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.store, required this.profile, required this.status});

  final ConnectionStore store;
  final ProtocolId profile;
  final Map<String, Object?>? status;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final String text;
    if (!store.hybridLive(profile)) {
      text = strings.hybridAppliedNext;
    } else if (store.hybridApplyError != null) {
      text = strings.hybridApplyFailed.replaceAll('{error}', store.hybridApplyError!);
    } else if (status == null || status!['live'] != true) {
      text = strings.hybridNotRouted;
    } else {
      text = strings.hybridStatusLive.replaceAll('{n}', '${status!['activeRules'] ?? 0}');
    }
    return SettingInfoText(text);
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    super.key,
    required this.rule,
    required this.app,
    required this.tunnels,
    required this.state,
    required this.hits,
    required this.onTunnel,
    required this.onEnabled,
    required this.onDelete,
    this.onEdit,
  });

  final HybridRule rule;
  final bool app;
  final List<HybridTunnel> tunnels;
  final _RuleState state;
  final int? hits;
  final ValueChanged<String> onTunnel;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final recipe = MotionScope.of(context).recipe;
    final error = state == _RuleState.invalidTunnel || state == _RuleState.engineRejected;
    final off = state == _RuleState.off;
    final note = switch (state) {
      _RuleState.invalidTunnel => strings.hybridInvalidTunnel,
      _RuleState.engineRejected => strings.hybridEngineRejected,
      _RuleState.off => strings.hybridRuleOff,
      _RuleState.active => hits == null ? null : strings.hybridFlows.replaceAll('{n}', '$hits'),
    };
    return AnimatedOpacity(
      duration: Duration(milliseconds: recipe.controlMs),
      opacity: off ? 0.55 : 1,
      child: AnimatedContainer(
        duration: Duration(milliseconds: recipe.controlMs),
        curve: recipe.controlCurve,
        padding: EdgeInsets.all(10 * s),
        decoration: BoxDecoration(
          color: AethColors.sheetDescCard,
          borderRadius: BorderRadius.circular(14 * s),
          border: error ? Border.all(color: AethColors.statusDisconnected, width: 1.2) : null,
        ),
        child: Directionality(
          textDirection: appContentDirection(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (app) ...[
                    _AppIcon(packageName: rule.value, size: 30 * s),
                    SizedBox(width: 10 * s),
                  ],
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onEdit,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app ? (rule.label ?? rule.value) : rule.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: app ? Directionality.of(context) : TextDirection.ltr,
                            style: _t(s),
                          ),
                          if (app || note != null) ...[
                            SizedBox(height: 2 * s),
                            Text(
                              [if (app) rule.value, ?note].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _t(s,
                                  size: 10,
                                  w: FontWeight.w400,
                                  color: error ? AethColors.statusDisconnected : AethColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 6 * s),
                  _MiniSwitch(
                    keyId: 'hybrid-enable-${rule.id}',
                    value: rule.enabled,
                    onChanged: onEnabled,
                  ),
                  SizedBox(width: 6 * s),
                  GestureDetector(
                    key: ValueKey('hybrid-delete-${rule.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onDelete,
                    child: Padding(
                      padding: EdgeInsets.all(4 * s),
                      child: SvgGlyph(asset: AppAssets.iconClose, size: 18 * s, color: AethColors.textSecondary),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8 * s),
              _TunnelChooser(
                keyId: 'hybrid-tunnel-${rule.id}',
                tunnels: tunnels,
                selected: rule.tunnel,
                onSelect: onTunnel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The route picker: one segment per REAL route of the profile, the
/// default route marked. Nothing that cannot be dialed is ever offered.
class _TunnelChooser extends StatelessWidget {
  const _TunnelChooser({
    required this.keyId,
    required this.tunnels,
    required this.selected,
    required this.onSelect,
  });

  final String keyId;
  final List<HybridTunnel> tunnels;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final recipe = MotionScope.of(context).recipe;
    return Row(
      children: [
        for (final t in tunnels) ...[
          Expanded(
            child: GestureDetector(
              key: ValueKey('$keyId-${t.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(t.id),
              child: AnimatedContainer(
                duration: Duration(milliseconds: recipe.controlMs),
                curve: recipe.controlCurve,
                padding: EdgeInsets.symmetric(vertical: 7 * s),
                decoration: BoxDecoration(
                  color: t.id == selected ? AethColors.accentConnected : AethColors.bgScreen,
                  borderRadius: BorderRadius.circular(10 * s),
                ),
                child: Text(
                  t.label,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(s,
                      size: 11,
                      w: t.id == selected ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
            ),
          ),
          if (t != tunnels.last) SizedBox(width: 6 * s),
        ],
      ],
    );
  }
}

class _MiniSwitch extends StatelessWidget {
  const _MiniSwitch({required this.keyId, required this.value, required this.onChanged});

  final String keyId;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final recipe = MotionScope.of(context).recipe;
    return GestureDetector(
      key: ValueKey(keyId),
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: Duration(milliseconds: recipe.controlMs),
        curve: recipe.controlCurve,
        width: 34 * s,
        height: 20 * s,
        padding: EdgeInsets.all(2 * s),
        alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        decoration: BoxDecoration(
          color: value ? AethColors.accentConnected : AethColors.bgScreen,
          borderRadius: BorderRadius.circular(10 * s),
        ),
        child: Container(
          width: 16 * s,
          height: 16 * s,
          decoration: BoxDecoration(shape: BoxShape.circle, color: AethColors.textPrimary),
        ),
      ),
    );
  }
}

/// The app's real launcher icon (PackageManager), cached per package.
class _AppIcon extends StatefulWidget {
  const _AppIcon({required this.packageName, required this.size});

  final String packageName;
  final double size;

  static final Map<String, Future<Uint8List?>> _cache = {};

  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  late Future<Uint8List?> _icon = _AppIcon._cache.putIfAbsent(
    widget.packageName,
    () => PlatformEngineAdapter.appIcon(widget.packageName),
  );

  @override
  void didUpdateWidget(_AppIcon old) {
    super.didUpdateWidget(old);
    if (old.packageName != widget.packageName) {
      _icon = _AppIcon._cache.putIfAbsent(
        widget.packageName,
        () => PlatformEngineAdapter.appIcon(widget.packageName),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: FutureBuilder<Uint8List?>(
        future: _icon,
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes == null) {
            return SvgGlyph(asset: AppAssets.iconCategory, size: widget.size * 0.7, color: AethColors.textSecondary);
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(widget.size * 0.22),
            child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// domain / IP editor sheet
// ---------------------------------------------------------------------------

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({
    required this.profile,
    required this.tunnels,
    required this.rules,
    required this.kind,
    this.existing,
  });

  final ProtocolId profile;
  final List<HybridTunnel> tunnels;
  final List<HybridRule> rules;
  final HybridRuleKind kind;
  final HybridRule? existing;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final TextEditingController _c = TextEditingController(text: widget.existing?.value ?? '');
  late String _tunnel = widget.existing?.tunnel ??
      widget.tunnels.firstWhere((t) => !t.isDefault, orElse: () => widget.tunnels.first).id;
  HybridInputError? _error;

  bool get _ip => widget.kind == HybridRuleKind.cidr;

  HybridRuleKind get _kind => _ip ? HybridRuleKind.cidr : HybridRouting.domainKindOf(_c.text);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  HybridRule? _candidate() {
    final v = HybridRouting.canonical(_kind, _c.text);
    if (v == null) return null;
    return HybridRule(
      id: widget.existing?.id ?? HybridRouting.newId(),
      kind: _kind,
      value: v,
      tunnel: _tunnel,
      enabled: widget.existing?.enabled ?? true,
    );
  }

  void _submit() {
    final err = HybridRouting.validate(widget.rules, _kind, _c.text, editingId: widget.existing?.id);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop(_candidate());
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final cand = _candidate();
    final overlaps = cand == null ? const <HybridRule>[] : HybridRouting.overlaps(widget.rules, cand);
    final errText = switch (_error) {
      HybridInputError.empty => strings.hybridErrEmpty,
      HybridInputError.invalid => strings.hybridErrInvalid,
      HybridInputError.duplicate => strings.hybridErrDuplicate,
      null => null,
    };
    return Padding(
      padding: EdgeInsets.only(
        left: 20 * s,
        right: 20 * s,
        top: 20 * s,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20 * s,
      ),
      child: Directionality(
        textDirection: appContentDirection(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_ip ? strings.hybridAddIp : strings.hybridAddDomain, style: _t(s, size: 15, w: FontWeight.w700)),
            SizedBox(height: 14 * s),
            TextField(
              key: const ValueKey('hybrid-editor-field'),
              controller: _c,
              autofocus: true,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
              style: _t(s, size: 13, w: FontWeight.w500),
              decoration: InputDecoration(
                hintText: _ip ? strings.hybridIpHint : strings.hybridDomainHint,
                hintTextDirection: TextDirection.ltr,
                hintStyle: _t(s, size: 12, w: FontWeight.w400, color: AethColors.textSecondary),
                filled: true,
                fillColor: AethColors.sheetDescCard,
                errorText: errText,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12 * s),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12 * s),
                  borderSide: const BorderSide(color: AethColors.accentConnected),
                ),
              ),
            ),
            SizedBox(height: 12 * s),
            Text(strings.hybridPickTunnel, style: _t(s, size: 12)),
            SizedBox(height: 8 * s),
            _TunnelChooser(
              keyId: 'hybrid-editor-tunnel',
              tunnels: widget.tunnels,
              selected: _tunnel,
              onSelect: (t) => setState(() => _tunnel = t),
            ),
            if (overlaps.isNotEmpty) ...[
              SizedBox(height: 10 * s),
              SettingInfoText(
                strings.hybridConflict.replaceAll('{rules}', overlaps.map((r) => r.value).join('، ')),
              ),
            ],
            SizedBox(height: 16 * s),
            SettingActionButton(keyId: 'hybrid-editor-save', label: strings.hybridSave, onTap: _submit),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// app picker (search + multi-select + one route for the selection)
// ---------------------------------------------------------------------------

class _AppPickerPage extends StatefulWidget {
  const _AppPickerPage({
    required this.store,
    required this.profile,
    required this.tunnels,
    required this.existing,
  });

  final ConnectionStore store;
  final ProtocolId profile;
  final List<HybridTunnel> tunnels;
  final Set<String> existing;

  @override
  State<_AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<_AppPickerPage> {
  List<InstalledApp>? _apps;
  bool _failed = false;
  String _query = '';
  final Set<String> _picked = {};
  late String _tunnel =
      widget.tunnels.firstWhere((t) => !t.isDefault, orElse: () => widget.tunnels.first).id;

  @override
  void initState() {
    super.initState();
    PlatformEngineAdapter.installedApps().then((a) {
      if (mounted) setState(() => _apps = a);
    }, onError: (_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final q = _query.trim().toLowerCase();
    final apps = (_apps ?? const <InstalledApp>[])
        .where((a) => !widget.existing.contains(a.packageName))
        .where((a) => q.isEmpty || a.label.toLowerCase().contains(q) || a.packageName.toLowerCase().contains(q))
        .toList();
    return SubPageFrame(
      store: widget.store,
      title: strings.hybridAddApps,
      children: () => [
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('hybrid-app-search'),
                onChanged: (v) => setState(() => _query = v),
                style: _t(s, size: 13, w: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: strings.hybridSearchApps,
                  hintStyle: _t(s, size: 12, w: FontWeight.w400, color: AethColors.textSecondary),
                  filled: true,
                  fillColor: AethColors.sheetDescCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12 * s),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              SizedBox(height: 12 * s),
              Text(strings.hybridPickTunnel, style: _t(s, size: 12)),
              SizedBox(height: 8 * s),
              _TunnelChooser(
                keyId: 'hybrid-picker-tunnel',
                tunnels: widget.tunnels,
                selected: _tunnel,
                onSelect: (t) => setState(() => _tunnel = t),
              ),
              SizedBox(height: 12 * s),
              SettingActionButton(
                keyId: 'hybrid-picker-save',
                label: '${strings.hybridSave} (${_picked.length})',
                onTap: () {
                  final byPkg = {for (final a in _apps ?? const <InstalledApp>[]) a.packageName: a};
                  Navigator.of(context).pop([
                    for (final p in _picked)
                      HybridRule(
                        id: HybridRouting.newId(),
                        kind: HybridRuleKind.app,
                        value: p,
                        tunnel: _tunnel,
                        label: byPkg[p]?.label,
                      ),
                  ]);
                },
              ),
            ],
          ),
        ),
        SizedBox(height: 16 * s),
        SubSectionCard(
          child: _apps == null
              ? SettingInfoText(_failed ? strings.tunnelAppsLoadFailed : strings.tunnelAppsLoading)
              : apps.isEmpty
                  ? SettingInfoText(strings.hybridEmpty)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final a in apps)
                          Padding(
                            padding: EdgeInsets.only(bottom: 8 * s),
                            child: _PickRow(
                              key: ValueKey('hybrid-pick-${a.packageName}'),
                              app: a,
                              selected: _picked.contains(a.packageName),
                              onTap: () => setState(() {
                                _picked.contains(a.packageName)
                                    ? _picked.remove(a.packageName)
                                    : _picked.add(a.packageName);
                              }),
                            ),
                          ),
                      ],
                    ),
        ),
        SizedBox(height: 16 * s),
      ],
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({super.key, required this.app, required this.selected, required this.onTap});

  final InstalledApp app;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final recipe = MotionScope.of(context).recipe;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: recipe.controlMs),
        curve: recipe.controlCurve,
        padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 9 * s),
        decoration: BoxDecoration(
          color: selected ? AethColors.accentConnected : AethColors.sheetDescCard,
          borderRadius: BorderRadius.circular(14 * s),
        ),
        child: Directionality(
          textDirection: appContentDirection(context),
          child: Row(
            children: [
              _AppIcon(packageName: app.packageName, size: 28 * s),
              SizedBox(width: 10 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(s)),
                    Text(app.packageName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(s, size: 10, w: FontWeight.w400, color: AethColors.textSecondary)),
                  ],
                ),
              ),
              SizedBox(
                width: 22 * s,
                height: 22 * s,
                child: selected
                    ? SvgPicture.asset(
                        AppAssets.iconTick,
                        colorFilter: ColorFilter.mode(AethColors.textPrimary, BlendMode.srcIn),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
