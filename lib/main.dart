import 'package:flutter/material.dart';

import 'app.dart';
import 'connection/connection_store.dart';
import 'connection/settings_persistence.dart';

Future<void> main() async {
  // The ConnectionStore is constructed with the (first) app widget and its
  // platform adapter registers the aethone/engine MethodChannel handler right
  // away — the binding must exist before that (M2).
  WidgetsFlutterBinding.ensureInitialized();

  // v4.19 (#8 — owner device test: «اپ انتخاب های تنظیمات رو یادش نمیمونه»):
  // the user's settings are restored BEFORE the first frame, so the cold
  // start renders the remembered protocol/mode/country/etc. — never a flash
  // of the defaults — and every later change is saved (debounced).
  final store = ConnectionStore();
  final persistence = SettingsPersistence();
  await persistence.restore(store);
  persistence.attach(store);

  runApp(AethoneApp(store: store));
}
