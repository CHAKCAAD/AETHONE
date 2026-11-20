import 'package:flutter/material.dart';

/// Preview adapter for the developer's own Widget.
///
/// To preview a project component, import its library below and return it
/// from this function. Keep the returned expression in sync with the
/// Widget expression field in the Playground inspector.
///
/// Example:
///   import 'package:aethone/features/settings/my_card.dart';
///   Widget buildCustomWidgetPreview() => const MyCard();
Widget buildCustomWidgetPreview() => const _StarterPreviewCard();

class _StarterPreviewCard extends StatelessWidget {
  const _StarterPreviewCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF142018),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x8842B987)),
        boxShadow: const [
          BoxShadow(color: Color(0x331AD995), blurRadius: 30),
        ],
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR WIDGET',
            style: TextStyle(
              color: Color(0xFF1AD995),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'AETHONE',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Replace this adapter with your own Widget.',
            style: TextStyle(color: Color(0xFF91A095), fontSize: 10),
          ),
        ],
      ),
    );
  }
}
