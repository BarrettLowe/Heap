import 'package:flutter/material.dart';

import 'inbox_task.dart';

const heapCanvas = Color(0xFFFAF7F0);
const heapSurface = Color(0xFFFFFCF5);
const heapInk = Color(0xFF282723);
const heapTitle = Color(0xFF282723);
const heapMuted = Color(0xFF666158);
const heapPrimary = Color(0xFF1B5EC4);
const heapHighlight = Color(0xFFE4EDFC);
const heapBorder = Color(0xFF82766A);
const heapDivider = Color(0xFFD8D1C5);
const heapError = Color(0xFFB42318);
const heapErrorSurface = Color(0xFFFEECE8);
const heapCompletionNeutral = Color(0xFFEBE7DF);
const heapCompletionText = Color(0xFF49463F);
const heapWarningSurface = Color(0xFFFFF1D6);
const heapWarningText = Color(0xFF644000);

const priorityColors = <int, (Color, Color, Color)>{
  1: (Color(0xFFFFC4B8), Color(0xFF7F2418), Color(0xFFC45843)),
  2: (Color(0xFFFFD790), Color(0xFF644000), Color(0xFFBC830E)),
  3: (Color(0xFFCAE0FA), Color(0xFF244E7A), Color(0xFF468BBB)),
  4: (Color(0xFFEEE5F3), Color(0xFF624270), Color(0xFF8B6A9C)),
  5: (Color(0xFFF1F1F1), Color(0xFF414141), Color(0xFF7C776D)),
};
const unsetColors = (Color(0xFFF1F1F1), Color(0xFF414141), Color(0xFF7C776D));

const heapHeadingStyle = TextStyle(
  fontFamily: 'HeapSerif',
  fontSize: 30,
  fontWeight: FontWeight.w700,
  color: heapInk,
  height: 1.2,
);
const heapSheetHeadingStyle = TextStyle(
  fontFamily: 'HeapSerif',
  fontSize: 24,
  fontWeight: FontWeight.w700,
  color: heapInk,
  height: 1.2,
);

class PriorityPill extends StatelessWidget {
  const PriorityPill({super.key, required this.priority, this.neutral = false});
  final int? priority;
  final bool neutral;
  @override
  Widget build(BuildContext context) {
    final colors = priorityColors[priority] ?? unsetColors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: neutral ? heapCompletionNeutral : colors.$1,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        priorityLabels[priority] ?? 'Unset',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: neutral ? heapCompletionText : colors.$2,
        ),
      ),
    );
  }
}

class HeapBrand extends StatelessWidget {
  const HeapBrand({super.key});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ExcludeSemantics(
        child: SizedBox(
          width: 40,
          height: 32,
          child: Image.asset(
            'assets/images/heap-mark.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
      Text(
        'Heap',
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: heapInk,
        ),
      ),
    ],
  );
}
