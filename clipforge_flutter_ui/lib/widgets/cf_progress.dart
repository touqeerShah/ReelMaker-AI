import 'package:flutter/material.dart';

class CfProgressBar extends StatelessWidget {
  const CfProgressBar({
    super.key,
    required this.value,
    this.height = 10,
  });

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          value: value.clamp(0, 1),
          backgroundColor: cs.surfaceContainerHighest.withOpacity(0.65),
          valueColor: AlwaysStoppedAnimation(cs.primary),
          minHeight: height,
        ),
      ),
    );
  }
}

class CfStepDots extends StatelessWidget {
  const CfStepDots({
    super.key,
    required this.total,
    required this.current,
  });

  final int total;
  final int current; // 0-based

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(total, (i) {
        final isDone = i < current;
        final isCurrent = i == current;
        final color = isDone
            ? cs.primary
            : (isCurrent ? Colors.white : cs.outline.withOpacity(0.35));
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }
}
