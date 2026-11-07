/// v4.41 — per-app tunneling (owner round 17, item 4): «برای قسمت
/// مسیریابی در تنظیمات قابلیت مثتثنی کردن برنامه ها از تونل در اندروید رو
/// هم اضافه کن. دو حالت داشته باشه 1. فقط برنامه های انتخاب شده تونل بشن
/// 2. برنامه های انتخاب شده تونل نشن این قسمت با زبان طراحی اپ هماهنگ
/// باشه»
///
/// The pick lives in [ConnectionStore] and reaches the TUN through the
/// `startVpn` channel args: the service applies the packages to the
/// VpnService.Builder (allow-list / disallow-list, mutually exclusive —
/// a degenerate allow-list falls back to whole-device). Only meaningful
/// in tunnel mode on Android; every other surface ignores it.
library;

/// The per-app tunneling mode.
enum AppTunnelMode {
  /// Every app rides the TUN (the standing whole-device behavior).
  all,

  /// ONLY the selected apps tunnel ([ConnectionStore.appTunnelApps]).
  allow,

  /// Everything EXCEPT the selected apps tunnels.
  disallow;

  /// The persisted name — unknown/corrupt values resolve to [all]
  /// (an old blob must never crash the settings load).
  static AppTunnelMode fromName(String? name) => switch (name) {
        'allow' => allow,
        'disallow' => disallow,
        _ => all,
      };
}

/// One launchable app of the picker (Android `installedApps` channel).
class InstalledApp {
  const InstalledApp({required this.packageName, required this.label});

  factory InstalledApp.fromMap(Map<Object?, Object?> map) => InstalledApp(
        packageName: map['package'] as String? ?? '',
        label: map['label'] as String? ?? '',
      );

  final String packageName;
  final String label;
}
