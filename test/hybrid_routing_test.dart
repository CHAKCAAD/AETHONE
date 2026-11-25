/// v1.1.0 — hybrid per-tunnel routing (docs/hybrid-routing.md): the Dart
/// data layer (profiles, validation, overlaps, policy document,
/// persistence) and the UI contract (visible only for hybrid protocols,
/// rules per profile, every control commits to the store).
///
/// The MATCHING itself is native (HybridPolicy.kt) and is covered by the
/// JVM tests in android/app/src/test; the zeptun route plumbing by the
/// Zig tests in scripts/zeptun-hybrid-routing.patch.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/hybrid_routing.dart';
import 'package:aethone/connection/settings_persistence.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:aethone/features/settings/hybrid_routing_page.dart';
import 'package:aethone/features/settings/routing_page.dart';

Widget _booth(Widget child) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: AethoneApp.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

Future<void> _surface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

HybridRule _r(String id, HybridRuleKind k, String v, String t, {bool enabled = true}) =>
    HybridRule(id: id, kind: k, value: v, tunnel: t, enabled: enabled);

void main() {
  group('profiles — only real, dialable routes', () {
    test('single-tunnel protocols have no hybrid profile', () {
      for (final id in [
        ProtocolId.auto,
        ProtocolId.masque,
        ProtocolId.wireguard,
        ProtocolId.gool,
        ProtocolId.goolClassic,
        ProtocolId.mim,
        ProtocolId.torOnly,
        ProtocolId.psiphonOnly,
        ProtocolId.lantern,
      ]) {
        expect(HybridRouting.isHybrid(id), isFalse, reason: id.name);
        expect(HybridRouting.policyJson(id, const []), isNull, reason: id.name);
      }
    });

    test('each hybrid protocol: default = its current exit listener', () {
      final chain = HybridRouting.profileOf(ProtocolId.psiphonChain)!;
      expect(chain.first.isDefault, isTrue);
      expect(chain.first.port, 1821); // unchanged: zeptun's psiphonChain target
      expect(chain.first.label, 'WARP → Psiphon');
      expect(chain[1].port, 1819);
      expect(HybridRouting.profileOf(ProtocolId.psiphonReverse)!.first.port, 1819);
      expect(HybridRouting.profileOf(ProtocolId.torChain)!.first.port, 1820);
      expect(HybridRouting.profileOf(ProtocolId.torReverse)!.first.port, 1819);
      for (final p in [
        ProtocolId.psiphonChain,
        ProtocolId.psiphonReverse,
        ProtocolId.torChain,
        ProtocolId.torReverse,
      ]) {
        final ts = HybridRouting.profileOf(p)!;
        expect(ts.length, 2);
        expect(ts.where((t) => t.isDefault).length, 1);
        expect(ts.map((t) => t.port).toSet().length, 2, reason: 'two distinct listeners');
      }
    });
  });

  group('validation', () {
    test('domains: exact vs wildcard, boundaries, IDN, junk', () {
      expect(HybridRouting.canonical(HybridRuleKind.domain, ' Example.COM. '), 'example.com');
      expect(HybridRouting.canonical(HybridRuleKind.domain, '*.example.com'), isNull);
      expect(HybridRouting.canonical(HybridRuleKind.wildcard, '*.Google.com'), '*.google.com');
      expect(HybridRouting.canonical(HybridRuleKind.wildcard, 'google.com'), isNull);
      expect(HybridRouting.canonical(HybridRuleKind.domain, 'ایران.ir'), 'ایران.ir');
      for (final bad in ['', 'com', 'a..com', '-a.com', 'exa mple.com', 'a_b.com']) {
        expect(HybridRouting.canonical(HybridRuleKind.domain, bad), isNull, reason: bad);
      }
      expect(HybridRouting.domainKindOf('*.x.com'), HybridRuleKind.wildcard);
      expect(HybridRouting.domainKindOf('x.com'), HybridRuleKind.domain);
    });

    test('IPs: v4, v6, CIDR, host bits, ranges', () {
      expect(HybridRouting.canonical(HybridRuleKind.cidr, '1.1.1.1'), '1.1.1.1/32');
      expect(HybridRouting.canonical(HybridRuleKind.cidr, '192.168.1.0/24'), '192.168.1.0/24');
      expect(HybridRouting.canonical(HybridRuleKind.cidr, '192.168.1.5/24'), isNull);
      expect(HybridRouting.canonical(HybridRuleKind.cidr, '1.1.1.1/33'), isNull);
      expect(HybridRouting.canonical(HybridRuleKind.cidr, '2606:4700:4700::1111'),
          '2606:4700:4700::1111/128');
      expect(HybridRouting.canonical(HybridRuleKind.cidr, '2001:db8::/32'), '2001:db8::/32');
      expect(HybridRouting.canonical(HybridRuleKind.cidr, '2001:db8::1/32'), isNull);
      expect(HybridRouting.canonical(HybridRuleKind.cidr, 'example.com'), isNull);
    });

    test('package ids', () {
      expect(HybridRouting.canonical(HybridRuleKind.app, 'org.telegram.messenger'), 'org.telegram.messenger');
      expect(HybridRouting.canonical(HybridRuleKind.app, 'Telegram'), isNull);
    });

    test('duplicates are refused, the edited rule itself is not a duplicate', () {
      final rules = [_r('1', HybridRuleKind.domain, 'example.com', 'warp')];
      expect(HybridRouting.validate(rules, HybridRuleKind.domain, 'EXAMPLE.com'), HybridInputError.duplicate);
      expect(HybridRouting.validate(rules, HybridRuleKind.domain, 'example.com', editingId: '1'), isNull);
      expect(HybridRouting.validate(rules, HybridRuleKind.domain, ' '), HybridInputError.empty);
      expect(HybridRouting.validate(rules, HybridRuleKind.domain, 'nope'), HybridInputError.invalid);
    });

    test('overlap notices: wildcard vs exact, wildcard nesting, CIDR nesting', () {
      final rules = [
        _r('w', HybridRuleKind.wildcard, '*.google.com', 'warp'),
        _r('c', HybridRuleKind.cidr, '10.0.0.0/8', 'warp'),
      ];
      expect(HybridRouting.overlaps(rules, _r('n', HybridRuleKind.domain, 'mail.google.com', 'psiphon')).map((r) => r.id), ['w']);
      expect(HybridRouting.overlaps(rules, _r('n', HybridRuleKind.domain, 'google.com', 'psiphon')), isEmpty);
      expect(HybridRouting.overlaps(rules, _r('n', HybridRuleKind.wildcard, '*.mail.google.com', 'psiphon')).map((r) => r.id), ['w']);
      expect(HybridRouting.overlaps(rules, _r('n', HybridRuleKind.cidr, '10.1.0.0/16', 'psiphon')).map((r) => r.id), ['c']);
      // same tunnel = no conflict to report
      expect(HybridRouting.overlaps(rules, _r('n', HybridRuleKind.cidr, '10.1.0.0/16', 'warp')), isEmpty);
    });
  });

  group('policy document + persistence', () {
    test('policy carries both listeners (default first) and the rules', () {
      final rules = [
        _r('1', HybridRuleKind.app, 'org.telegram.messenger', 'warp'),
        _r('2', HybridRuleKind.app, 'com.instagram.android', 'psiphon'),
      ];
      final doc = jsonDecode(HybridRouting.policyJson(ProtocolId.psiphonChain, rules)!) as Map;
      expect(doc['profile'], 'psiphonChain');
      expect(doc['tunnels'], [
        {'id': 'psiphon', 'endpoint': '127.0.0.1:1821'},
        {'id': 'warp', 'endpoint': '127.0.0.1:1819'},
      ]);
      expect((doc['rules'] as List).length, 2);
      expect((doc['rules'] as List).first['kind'], 'app');
    });

    test('no rules still yields a policy (default route only, live-editable)', () {
      final doc = jsonDecode(HybridRouting.policyJson(ProtocolId.torChain, const [])!) as Map;
      expect(doc['rules'], isEmpty);
      expect((doc['tunnels'] as List).first, {'id': 'tor', 'endpoint': '127.0.0.1:1820'});
    });

    test('rules whose tunnel the profile lacks are flagged', () {
      final bad = _r('x', HybridRuleKind.domain, 'a.com', 'tor');
      expect(HybridRouting.invalidRules(ProtocolId.psiphonChain, [bad]).single.id, 'x');
      expect(HybridRouting.invalidRules(ProtocolId.torChain, [bad]), isEmpty);
    });

    test('encode/decode round-trip; a corrupt blob loads as none', () {
      final all = {
        'psiphonChain': [_r('1', HybridRuleKind.cidr, '1.1.1.1/32', 'warp', enabled: false)],
        'torChain': [_r('2', HybridRuleKind.wildcard, '*.x.org', 'tor')],
      };
      final back = HybridRouting.decodeAll(HybridRouting.encodeAll(all));
      expect(back.keys, ['psiphonChain', 'torChain']);
      expect(back['psiphonChain']!.single.enabled, isFalse);
      expect(back['torChain']!.single.kind, HybridRuleKind.wildcard);
      expect(HybridRouting.decodeAll('{not json'), isEmpty);
      expect(HybridRouting.decodeAll('{"a":[{"kind":"zzz"}]}')['a'], isEmpty);
    });

    test('rules persist per profile across a store reload', () async {
      SharedPreferences.setMockInitialValues({});
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      await store.setHybridRules(ProtocolId.psiphonChain, [
        _r('1', HybridRuleKind.app, 'org.telegram.messenger', 'warp'),
      ]);
      await store.setHybridRules(ProtocolId.torChain, [
        _r('2', HybridRuleKind.app, 'org.telegram.messenger', 'tor'),
      ]);
      final persistence = SettingsPersistence();
      await persistence.save(store);
      final again = ConnectionStore(engine: EngineNotWiredAdapter());
      await persistence.restore(again);
      expect(again.hybridRulesFor(ProtocolId.psiphonChain).single.tunnel, 'warp');
      expect(again.hybridRulesFor(ProtocolId.torChain).single.tunnel, 'tor');
      // profiles never leak into each other or into single-tunnel modes
      expect(again.hybridRulesFor(ProtocolId.psiphonReverse), isEmpty);
      expect(again.hybridRulesFor(ProtocolId.masque), isEmpty);
    });

    test('a single-tunnel protocol never stores rules', () async {
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      await store.setHybridRules(ProtocolId.masque, [_r('1', HybridRuleKind.domain, 'a.com', 'warp')]);
      expect(store.hybridRules, isEmpty);
    });
  });

  group('UI', () {
    setUp(() => debugShowHybridRouting = true);
    tearDown(() => debugShowHybridRouting = false);

    testWidgets('routing page: entry only for hybrid protocols', (tester) async {
      await _surface(tester);
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.selectedProtocol = ProtocolId.masque;
      await tester.pumpWidget(_booth(RoutingSettingsPage(store: store)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nav-hybrid-routing')), findsNothing);

      store.selectProtocol(ProtocolId.psiphonChain);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nav-hybrid-routing')), findsOneWidget);

      store.selectProtocol(ProtocolId.psiphonOnly);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nav-hybrid-routing')), findsNothing);
    });

    testWidgets('hybrid page: add a domain, switch its route, disable, delete', (tester) async {
      await _surface(tester);
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.selectedProtocol = ProtocolId.psiphonChain;
      await tester.pumpWidget(_booth(HybridRoutingPage(store: store, profile: ProtocolId.psiphonChain)));
      await tester.pumpAndSettle();
      expect(find.text('WARP → Psiphon · پیش‌فرض'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('action-hybrid-add-domain')));
      await tester.tap(find.byKey(const ValueKey('action-hybrid-add-domain')));
      await tester.pumpAndSettle();
      // invalid entry is refused in place
      await tester.enterText(find.byKey(const ValueKey('hybrid-editor-field')), 'not a domain');
      await tester.tap(find.byKey(const ValueKey('action-hybrid-editor-save')));
      await tester.pumpAndSettle();
      expect(store.hybridRulesFor(ProtocolId.psiphonChain), isEmpty);
      await tester.enterText(find.byKey(const ValueKey('hybrid-editor-field')), 'Google.com');
      await tester.tap(find.byKey(const ValueKey('action-hybrid-editor-save')));
      await tester.pumpAndSettle();

      final rules = store.hybridRulesFor(ProtocolId.psiphonChain);
      expect(rules.single.value, 'google.com');
      expect(rules.single.tunnel, 'warp'); // the editor preselects the non-default route
      final id = rules.single.id;

      await tester.ensureVisible(find.byKey(ValueKey('hybrid-tunnel-$id-psiphon')));
      await tester.tap(find.byKey(ValueKey('hybrid-tunnel-$id-psiphon')));
      await tester.pumpAndSettle();
      expect(store.hybridRulesFor(ProtocolId.psiphonChain).single.tunnel, 'psiphon');

      await tester.tap(find.byKey(ValueKey('hybrid-enable-$id')));
      await tester.pumpAndSettle();
      expect(store.hybridRulesFor(ProtocolId.psiphonChain).single.enabled, isFalse);

      await tester.tap(find.byKey(ValueKey('hybrid-delete-$id')));
      await tester.pumpAndSettle();
      expect(store.hybridRulesFor(ProtocolId.psiphonChain), isEmpty);
    });

    testWidgets('hybrid page: a rule on a missing route is shown as an error', (tester) async {
      await _surface(tester);
      final store = ConnectionStore(engine: EngineNotWiredAdapter());
      store.hybridRules = {
        'psiphonChain': [_r('bad', HybridRuleKind.domain, 'a.com', 'tor')],
      };
      await tester.pumpWidget(_booth(HybridRoutingPage(store: store, profile: ProtocolId.psiphonChain)));
      await tester.pumpAndSettle();
      expect(find.textContaining('مسدود'), findsWidgets);
    });
  });
}
