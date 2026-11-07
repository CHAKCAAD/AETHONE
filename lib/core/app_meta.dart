/// App metadata the About row renders (v4.22). A tiny const instead of
/// package_info_plus — zero new dependencies; the companion test asserts
/// it against pubspec.yaml so the two can never drift apart.
library;

/// Mirrors pubspec.yaml's `version` (the `+N` build number is dropped from
/// the UI). Kept in sync by test/app_meta_test.dart.
const String appVersion = '1.0.0';

/// The Telegram channel (same URL as the top-bar info tiles).
const String telegramChannelUrl = 'https://t.me/AETHONE';

/// The public source repository (the server pills already carry the
/// GitHub logo — the About row opens the real repo).
const String repositoryUrl = 'https://github.com/CHAKCAAD/AETHONE';

/// v1.0.0 — the owner-delivered Instagram address (round 18:
/// «آدرس اینستاگرام: https://www.instagram.com/aethoneiran?srtk=… رو
/// اضافه کن» — kept verbatim, srtk attribution token included).
const String instagramUrl =
    'https://www.instagram.com/aethoneiran?srtk=MWhwbzFnbjFkb3pkdQ==';
