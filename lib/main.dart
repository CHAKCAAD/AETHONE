import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  // The ConnectionStore is constructed with the (first) app widget and its
  // platform adapter registers the aethone/engine MethodChannel handler right
  // away — the binding must exist before that (M2).
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AethoneApp());
}
