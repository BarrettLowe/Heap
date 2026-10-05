import 'package:flutter/material.dart';

import 'inbox_task.dart';

// Visual tokens follow the approved reference-led design, not task eligibility.
const heapCanvas = Color(0xFFFCFCF8);
const heapInk = Color(0xFF102E24);
const heapTitle = Color(0xFF171C19);
const heapMuted = Color(0xFF646D67);
const heapGreen = Color(0xFF285A46);
const heapHighlight = Color(0xFFEFF3E7);
const heapDivider = Color(0xFFDFE4DE);
const priorityColors = <int, (Color, Color, Color)>{
  1: (Color(0xFFFFC4B8), Color(0xFF7F2418), Color(0xFFC45843)),
  2: (Color(0xFFFFD790), Color(0xFF644000), Color(0xFFBC830E)),
  3: (Color(0xFFCAE0FA), Color(0xFF244E7A), Color(0xFF468BBB)),
  4: (Color(0xFFDCE7C8), Color(0xFF40551F), Color(0xFF779252)),
  5: (Color(0xFFE3E5E4), Color(0xFF414B44), Color(0xFF87918A)),
};
const unsetColors = (Color(0xFFEBEEEA), Color(0xFF4B554E), Color(0xFFA3AAA4));

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
        // Retained completed rows use a readable neutral fill.
        color: neutral ? const Color(0xFFE5E8E5) : colors.$1,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        priorityLabels[priority] ?? 'Unset',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: neutral ? const Color(0xFF3F4742) : colors.$2,
        ),
      ),
    );
  }
}

class HeapBrand extends StatelessWidget {
  const HeapBrand({super.key});
  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ExcludeSemantics(
        child: SizedBox(
          width: 40,
          height: 32,
          child: CustomPaint(painter: _MountainPainter()),
        ),
      ),
      Text(
        'Heap',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: heapInk,
        ),
      ),
    ],
  );
}

class _MountainPainter extends CustomPainter {
  const _MountainPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final left = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * .43, 0)
      ..quadraticBezierTo(size.width * .47, -1, size.width * .51, 3)
      ..lineTo(size.width * .64, size.height * .31)
      ..lineTo(size.width * .2, size.height)
      ..close();
    final right = Path()
      ..moveTo(size.width * .35, size.height)
      ..lineTo(size.width * .7, size.height * .3)
      ..quadraticBezierTo(
        size.width * .74,
        size.height * .25,
        size.width * .79,
        size.height * .34,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(left, Paint()..color = const Color(0xFF52875B));
    canvas.drawPath(right, Paint()..color = const Color(0xFF365F47));
  }

  @override
  bool shouldRepaint(covariant _MountainPainter oldDelegate) => false;
}
