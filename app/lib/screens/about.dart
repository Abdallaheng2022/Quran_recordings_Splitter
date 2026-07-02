// about.dart — شاشة «عن التطبيق» (مترجمة بكل لغات التطبيق).
import 'package:flutter/material.dart';
import '../l10n.dart';
import '../theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Mushaf.background,
        elevation: 0,
        foregroundColor: Mushaf.foreground,
        title: Text(t('about'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Mushaf.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.menu_book_rounded,
                  size: 34, color: Mushaf.primaryForeground),
            ),
          ),
          const SizedBox(height: 14),
          Text(t('appTitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Mushaf.primary)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Mushaf.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Mushaf.border, width: 0.6),
            ),
            child: Text(
              t('aboutBody'),
              style: const TextStyle(
                  fontSize: 15, height: 1.65, color: Mushaf.foreground),
            ),
          ),
        ],
      ),
    );
  }
}
