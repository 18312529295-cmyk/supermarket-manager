import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../utils/currency_util.dart';

class CurrencyDisplay extends StatelessWidget {
  final double amountCny;
  final double amountUzs;
  final TextStyle? style;
  final bool compact;

  const CurrencyDisplay({
    super.key,
    required this.amountCny,
    required this.amountUzs,
    this.style,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final display = appProvider.currencyDisplay;
    final uzsSymbol = appProvider.countryConfig.currencySymbol;

    if (compact) {
      return _buildCompact(display, uzsSymbol);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (display == 'both' || display == 'cny')
          Text(
            CurrencyUtil.formatCny(amountCny),
            style: style ?? const TextStyle(fontSize: 14),
          ),
        if (display == 'both' || display == 'uzs')
          Text(
            CurrencyUtil.formatUzs(amountUzs, symbol: uzsSymbol),
            style: style ??
                const TextStyle(
                  fontSize: 14,
                  color: Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
          ),
      ],
    );
  }

  Widget _buildCompact(String display, String uzsSymbol) {
    String text = '';
    if (display == 'both') {
      text = '${CurrencyUtil.formatCompact(amountCny, 'CNY', uzsSymbol: uzsSymbol)} / ${CurrencyUtil.formatCompact(amountUzs, 'UZS', uzsSymbol: uzsSymbol)}';
    } else if (display == 'cny') {
      text = CurrencyUtil.formatCompact(amountCny, 'CNY', uzsSymbol: uzsSymbol);
    } else {
      text = CurrencyUtil.formatCompact(amountUzs, 'UZS', uzsSymbol: uzsSymbol);
    }

    return Text(
      text,
      style: style ?? const TextStyle(fontSize: 12, color: Colors.grey),
      overflow: TextOverflow.ellipsis,
    );
  }
}
