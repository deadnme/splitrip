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
    // bodyLarge: a ListTile trailing slot would otherwise shrink it to 11sp.
    // Tabular figures: digits line up down a column of amounts.
    const tab = [FontFeature.tabularFigures()];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text('$prefix${formatWhole(minor, currency, rounding)}', style: Theme.of(context).textTheme.bodyLarge!.merge(style).copyWith(fontFeatures: tab)),
        if (!isWhole(minor, currency)) Text(formatMoney(minor, currency), style: muted?.copyWith(fontFeatures: tab)),
      ],
    );
  }
}
