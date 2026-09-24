import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_direction_screen.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_match_screen.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_tab_chrome.dart';
import 'package:flutter/material.dart';

/// The AI tab: one page whose view is the match or the direction analysis.
///
/// Both routes build this with the same page key, so moving between them
/// changes what this page shows -- a cross-fade under the same title and
/// switch -- instead of pushing a second page over the first.
class AiTabPage extends StatelessWidget {
  const AiTabPage({required this.mode, super.key});

  final AiMode mode;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.quick,
      switchInCurve: AppMotion.standardCurve,
      switchOutCurve: AppMotion.standardCurve,
      child: KeyedSubtree(
        key: ValueKey(mode),
        child: switch (mode) {
          AiMode.match => const AiMatchScreen(),
          AiMode.direction => const AiDirectionScreen(),
        },
      ),
    );
  }
}
