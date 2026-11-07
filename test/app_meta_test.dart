/// v4.22 — meta tests: the version const stays in lockstep with
/// pubspec.yaml, and every AppStrings getter resolves in ALL four locales
/// (a missing key in any table would crash at runtime with the `!`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/core/app_meta.dart';
import 'package:aethone/l10n/app_strings.dart';

void main() {
  test('appVersion mirrors pubspec.yaml (single source, two mirrors)', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.firstWhere((l) => l.startsWith('version:'));
    final value = line.split(':')[1].trim(); // e.g. 4.22.0+1
    expect(value.startsWith('$appVersion+'), isTrue,
        reason: 'pubspec says $value but the About row renders $appVersion');
  });

  test('every string getter resolves in all four locales', () {
    final locales = ['fa', 'en', 'ru', 'zh'];
    for (final l in locales) {
      final s = AppStrings.forLocale(l);
      // v4.22 getters — any missing table entry throws here.
      s.subCoreTitle;
      s.expertMode;
      s.expertModeDesc;
      s.appliesNextConnect;
      s.secFragment;
      s.fragOff;
      s.fragStandard;
      s.fragBalanced;
      s.fragAggressive;
      s.fragCustom;
      s.fragOffDesc;
      s.fragStandardDesc;
      s.fragBalancedDesc;
      s.fragAggressiveDesc;
      s.fragCustomDesc;
      s.fragSizeLabel;
      s.fragDelayLabel;
      s.fragSizeHint;
      s.fragDelayHint;
      s.secTls;
      s.tlsCustom;
      s.tlsCustomDesc;
      s.tlsDisableGrease;
      s.tlsDisableGreaseDesc;
      s.tlsGreaseSigalgs;
      s.tlsGreaseSigalgsDesc;
      s.tlsEchGrease;
      s.tlsEchGreaseDesc;
      s.tlsSessionTicket;
      s.tlsSessionTicketDesc;
      s.tlsOcsp;
      s.tlsOcspDesc;
      s.tlsSct;
      s.tlsSctDesc;
      s.tlsExtPerm;
      s.tlsExtPermDesc;
      s.tlsVerify;
      s.tlsVerifyDesc;
      s.tlsGroups;
      s.tlsGroupsHint;
      s.tlsKeyShares;
      s.tlsKeySharesHint;
      s.tlsCiphers12;
      s.tlsCiphers12Hint;
      s.tlsCiphers13;
      s.tlsCiphers13Hint;
      s.masqueSni;
      s.masqueSniHint;
      s.secTransport;
      s.h2Transport;
      s.h2TransportDesc;
      s.quicV2;
      s.quicV2Desc;
      s.dnsLabel;
      s.dnsHint;
      s.secEngine;
      s.noizeLabel;
      s.noizeDesc;
      s.noizeDefault;
      s.noizeOff;
      s.noizeLight;
      s.noizeFirewall;
      s.noizeBalanced;
      s.noizeGfw;
      s.noizeAggressive;
      s.perfLabel;
      s.perfAuto;
      s.perfLow;
      s.perfMedium;
      s.perfHigh;
      s.logLevelLabel;
      s.logInfo;
      s.logDebug;
      s.logTrace;
      s.keepaliveLabel;
      s.secRoutes;
      s.routeBlockLabel;
      s.routeBlockHint;
      s.routeDirectLabel;
      s.routeDirectHint;
      s.routesDesc;
      s.routingNone;
      s.secProtocolMode;
      s.protoModeSmart;
      s.smartNote;
      s.coreRowDesc;
      s.secAbout;
      s.appVersionLabel;
      s.telegramRow;
      s.githubRow;
      s.instagramRow;
      s.secNotifications;
      s.notificationsComing;
      s.secAppLanguage;
      s.langSystem;
      s.langDesc;
      s.secHomeLook;
      s.lookOne;
      s.lookTwo;
      s.secMotion;
      s.motionStandard;
      s.motionSmooth;
      s.motionDynamic;
      s.motionMinimal;
      s.animationsOffTitle;
      s.animationsOffDesc;
      s.secPatterns;
      s.showPatterns;
      s.showPatternsDesc;
      s.secKillSwitch;
      s.killSwitchDesc;
      s.secDiagnostics;
      s.secExitLocation;
      s.psiphonLocationDesc;
      s.secFronting;
      s.frontingModeLabel;
      s.frontingAuto;
      s.frontingCdn;
      s.frontingDirect;
      s.frontingAutoDesc;
      s.frontingCdnDesc;
      s.frontingDirectDesc;
      s.cdnSniLabel;
      s.cdnSniHint;
      s.cdnIpsLabel;
      s.cdnIpsHint;
      s.torLocationDesc;
      s.secTorBridges;
      s.bridgesLabel;
      s.bridgesAuto;
      s.bridgesOff;
      s.bridgesAutoDesc;
      s.bridgesOffDesc;
      s.torLogLevelLabel;
      // v4.24 getters — the speed test page.
      s.speedTestTitle;
      s.speedPhasePing;
      s.speedPhaseDownload;
      s.speedPhaseUpload;
      s.speedStart;
      s.speedStarted;
      s.speedRestart;
    }
  });
}
