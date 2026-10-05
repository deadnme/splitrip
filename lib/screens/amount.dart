import 'package:flutter/material.dart';

import '../format.dart';

/// Whole-number amount in front, the exact value small and muted underneath
/// (only when it has cents). E.g. "owes ₱134" over "₱133.34".
class AmountText extends StatelessWidget {
  final int minor;
  final String currency;
  final Rounding rounding;
  final String prefix;
  final TextStyle? style;
  final bool alignEnd;
  const AmountText(this.minor, this.currency, this.rounding,
      {super.key, this.prefix = '', this.style, this.alignEnd = true});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontSize: 11,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text('$prefix${formatWhole(minor, currency, rounding)}', style: style),
        if (!isWhole(minor, currency)) Text(formatMoney(minor, currency), style: muted),
      ],
    );
  }
}
