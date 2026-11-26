/// Traffic Analytics strings. fa and en are complete; ru / zh / tk fall back
/// to en for this module until their tables are translated (tracked in
/// docs/traffic-analytics.md §10 — Not Implemented).
library;

import 'package:flutter/widgets.dart';

class TrafficStrings {
  const TrafficStrings._(this._v);
  final Map<String, String> _v;

  static TrafficStrings of(BuildContext context) {
    final code = Localizations.maybeLocaleOf(context)?.languageCode ?? 'fa';
    return TrafficStrings._(_t[code] ?? _t['en']!);
  }

  static TrafficStrings forCode(String code) => TrafficStrings._(_t[code] ?? _t['en']!);

  String _g(String k) => _v[k] ?? _t['en']![k]!;

  String get title => _g('title');
  String get subtitle => _g('subtitle');
  String get rangeToday => _g('rangeToday');
  String get range24h => _g('range24h');
  String get range7d => _g('range7d');
  String get range30d => _g('range30d');
  String get rangeThisMonth => _g('rangeThisMonth');
  String get rangeLastMonth => _g('rangeLastMonth');
  String get rangeCustom => _g('rangeCustom');
  String get download => _g('download');
  String get upload => _g('upload');
  String get total => _g('total');
  String get avgSpeed => _g('avgSpeed');
  String get peakSpeed => _g('peakSpeed');
  String get usageOverTime => _g('usageOverTime');
  String get live => _g('live');
  String get liveOff => _g('liveOff');
  String get liveDisabled => _g('liveDisabled');
  String get activeApps => _g('activeApps');
  String get activeRoutes => _g('activeRoutes');
  String get openFlows => _g('openFlows');
  String get routes => _g('routes');
  String get apps => _g('apps');
  String get allApps => _g('allApps');
  String get searchApps => _g('searchApps');
  String get flows => _g('flows');
  String get appsUsing => _g('appsUsing');
  String get byRoute => _g('byRoute');
  String get byApp => _g('byApp');
  String get hourly => _g('hourly');
  String get daily => _g('daily');
  String get topDomains => _g('topDomains');
  String get compare => _g('compare');
  String get vsPrevious => _g('vsPrevious');
  String get notEnoughHistory => _g('notEnoughHistory');
  String get biggestChanges => _g('biggestChanges');
  String get noData => _g('noData');
  String get noDataBody => _g('noDataBody');
  String get unsupported => _g('unsupported');
  String get unattributed => _g('unattributed');
  String get unattributedHint => _g('unattributedHint');
  String get unmeasured => _g('unmeasured');
  String get unmeasuredHint => _g('unmeasuredHint');
  String get notMeasured => _g('notMeasured');
  String get coverage => _g('coverage');
  String get history => _g('history');
  String get historyDesc => _g('historyDesc');
  String get recordUsage => _g('recordUsage');
  String get recordUsageDesc => _g('recordUsageDesc');
  String get recordDomains => _g('recordDomains');
  String get recordDomainsDesc => _g('recordDomainsDesc');
  String get retention => _g('retention');
  String get forever => _g('forever');
  String get exportCsv => _g('exportCsv');
  String get exportJson => _g('exportJson');
  String get exported => _g('exported');
  String get exportFailed => _g('exportFailed');
  String get clearHistory => _g('clearHistory');
  String get clearConfirm => _g('clearConfirm');
  String get cancel => _g('cancel');
  String get clear => _g('clear');
  String get cleared => _g('cleared');
  String get appliesNextConnect => _g('appliesNextConnect');
  String get android10 => _g('android10');
  String get loading => _g('loading');
  String get errorLoading => _g('errorLoading');
  String get otherApps => _g('otherApps');
  String get previous => _g('previous');
  String days(int n) => _g('days').replaceAll('{n}', '$n');
  String sinceFirst(String date) => _g('sinceFirst').replaceAll('{d}', date);

  static const Map<String, Map<String, String>> _t = {
    'fa': {
      'title': 'تحلیل ترافیک',
      'subtitle': 'مصرف واقعی هر برنامه و هر مسیر، از شمارنده‌های خود موتور تونل.',
      'rangeToday': 'امروز',
      'range24h': '۲۴ ساعت',
      'range7d': '۷ روز',
      'range30d': '۳۰ روز',
      'rangeThisMonth': 'این ماه',
      'rangeLastMonth': 'ماه قبل',
      'rangeCustom': 'دلخواه',
      'download': 'دانلود',
      'upload': 'آپلود',
      'total': 'مجموع',
      'avgSpeed': 'سرعت متوسط',
      'peakSpeed': 'بیشترین سرعت',
      'usageOverTime': 'مصرف در طول زمان',
      'live': 'زنده',
      'liveOff': 'تونل وصل نیست؛ سرعت زنده فقط هنگام اتصال نمایش داده می‌شود.',
      'liveDisabled': 'ثبت آمار خاموش است.',
      'activeApps': 'برنامه‌های فعال',
      'activeRoutes': 'مسیرهای فعال',
      'openFlows': 'اتصال باز',
      'routes': 'مسیرها',
      'apps': 'برنامه‌ها',
      'allApps': 'همه برنامه‌ها',
      'searchApps': 'جست‌وجوی برنامه',
      'flows': 'اتصال',
      'appsUsing': 'برنامه',
      'byRoute': 'به تفکیک مسیر',
      'byApp': 'به تفکیک برنامه',
      'hourly': 'ساعتی',
      'daily': 'روزانه',
      'topDomains': 'دامنه‌های پرمصرف',
      'compare': 'مقایسه',
      'vsPrevious': 'نسبت به دوره قبل',
      'notEnoughHistory': 'برای دوره قبل آمار کافی ثبت نشده؛ مقایسه نامشخص است.',
      'biggestChanges': 'بیشترین تغییر مصرف',
      'noData': 'هنوز مصرفی ثبت نشده',
      'noDataBody': 'آمار از اولین اتصال بعد از فعال‌شدن ثبت می‌شود.',
      'unsupported': 'تحلیل ترافیک فقط در نسخه اندروید در دسترس است.',
      'unattributed': 'نامشخص',
      'unattributedHint': 'اتصال‌هایی که اندروید صاحبشان را مشخص نکرد.',
      'unmeasured': 'اندازه‌گیری‌نشده',
      'unmeasuredHint': 'بایت‌هایی که موتور جابه‌جا کرد اما شمارنده اتصال‌ها آن‌ها را ندید؛ مثل UDP و DNS یا قطع ناگهانی. این بایت‌ها در هیچ برنامه یا مسیری حساب نشده‌اند.',
      'notMeasured': 'اندازه‌گیری نشده',
      'coverage': 'پوشش اندازه‌گیری',
      'history': 'تاریخچه و خروجی',
      'historyDesc': 'نگهداری، پاک‌کردن و خروجی آمار. همه‌چیز فقط روی همین گوشی ذخیره می‌شود.',
      'recordUsage': 'ثبت آمار مصرف',
      'recordUsageDesc': 'شمارش بایت‌های هر اتصال در موتور تونل.',
      'recordDomains': 'ثبت نام دامنه‌ها',
      'recordDomainsDesc': 'فقط نام دامنه، بدون آدرس کامل یا محتوا.',
      'retention': 'مدت نگهداری',
      'forever': 'همیشه',
      'exportCsv': 'خروجی CSV',
      'exportJson': 'خروجی JSON',
      'exported': 'فایل ذخیره شد.',
      'exportFailed': 'خروجی ذخیره نشد.',
      'clearHistory': 'پاک‌کردن تاریخچه',
      'clearConfirm': 'همه آمار ثبت‌شده برای همیشه پاک شود؟',
      'cancel': 'انصراف',
      'clear': 'پاک کن',
      'cleared': 'تاریخچه پاک شد.',
      'appliesNextConnect': 'از اتصال بعدی اعمال می‌شود.',
      'android10': 'تفکیک برنامه‌ها به اندروید ۱۰ یا بالاتر نیاز دارد.',
      'loading': 'در حال خواندن…',
      'errorLoading': 'خواندن آمار ناموفق بود.',
      'otherApps': 'سایر',
      'previous': 'دوره قبل',
      'days': '{n} روز',
      'sinceFirst': 'از {d}',
    },
    'en': {
      'title': 'Traffic Analytics',
      'subtitle': 'Real usage per app and per route, from the tunnel engine\'s own counters.',
      'rangeToday': 'Today',
      'range24h': '24 h',
      'range7d': '7 days',
      'range30d': '30 days',
      'rangeThisMonth': 'This month',
      'rangeLastMonth': 'Last month',
      'rangeCustom': 'Custom',
      'download': 'Download',
      'upload': 'Upload',
      'total': 'Total',
      'avgSpeed': 'Average speed',
      'peakSpeed': 'Peak speed',
      'usageOverTime': 'Usage over time',
      'live': 'Live',
      'liveOff': 'Not connected — live speed shows while the tunnel is up.',
      'liveDisabled': 'Usage recording is off.',
      'activeApps': 'Active apps',
      'activeRoutes': 'Active routes',
      'openFlows': 'open flows',
      'routes': 'Routes',
      'apps': 'Apps',
      'allApps': 'All apps',
      'searchApps': 'Search apps',
      'flows': 'flows',
      'appsUsing': 'apps',
      'byRoute': 'By route',
      'byApp': 'By app',
      'hourly': 'Hourly',
      'daily': 'Daily',
      'topDomains': 'Top domains',
      'compare': 'Compare',
      'vsPrevious': 'vs previous period',
      'notEnoughHistory': 'Not enough history for the previous period — comparison unknown.',
      'biggestChanges': 'Biggest changes',
      'noData': 'No usage recorded yet',
      'noDataBody': 'Recording starts with the first connection after it is enabled.',
      'unsupported': 'Traffic Analytics is available on Android only.',
      'unattributed': 'Unattributed',
      'unattributedHint': 'Flows whose owner Android could not name.',
      'unmeasured': 'Unmeasured',
      'unmeasuredHint': 'Bytes the engine moved that no per-flow meter saw (UDP, DNS, a hard stop). Not counted under any app or route.',
      'notMeasured': 'not measured',
      'coverage': 'Measurement coverage',
      'history': 'History & export',
      'historyDesc': 'Retention, clearing and export. Everything stays on this phone.',
      'recordUsage': 'Record usage',
      'recordUsageDesc': 'Count each flow\'s bytes inside the tunnel engine.',
      'recordDomains': 'Record domain names',
      'recordDomainsDesc': 'Host names only — never full URLs or content.',
      'retention': 'Keep history for',
      'forever': 'Forever',
      'exportCsv': 'Export CSV',
      'exportJson': 'Export JSON',
      'exported': 'File saved.',
      'exportFailed': 'Export was not saved.',
      'clearHistory': 'Clear history',
      'clearConfirm': 'Permanently delete all recorded usage?',
      'cancel': 'Cancel',
      'clear': 'Clear',
      'cleared': 'History cleared.',
      'appliesNextConnect': 'Applies from the next connection.',
      'android10': 'Per-app attribution needs Android 10 or newer.',
      'loading': 'Reading…',
      'errorLoading': 'Could not read the usage store.',
      'otherApps': 'Other',
      'previous': 'Previous',
      'days': '{n} days',
      'sinceFirst': 'since {d}',
    },
  };
}
