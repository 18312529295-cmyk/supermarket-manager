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
    final localSymbol = appProvider.countryConfig.currencySymbol;

    if (compact) {
      return _buildCompact(display, localSymbol);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ★ v6.34: 当地货币在前
        if (display == 'both' || display == 'uzs')
          Text(
            CurrencyUtil.formatUzs(amountUzs, symbol: localSymbol),
            style: style ??
                const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
          ),
        if (display == 'both' || display == 'cny')
          Text(
            CurrencyUtil.formatCny(amountCny),
            style: style ?? const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w400),
          ),
      ],
    );
  }

  Widget _buildCompact(String display, String localSymbol) {
    String text = '';
    if (display == 'both') {
      // ★ v6.34: 当地货币在前
      text = '${CurrencyUtil.formatCompact(amountUzs, 'UZS', uzsSymbol: localSymbol)} / ${CurrencyUtil.formatCompact(amountCny, 'CNY')}';
    } else if (display == 'uzs') {
      text = CurrencyUtil.formatCompact(amountUzs, 'UZS', uzsSymbol: localSymbol);
    } else {
      text = CurrencyUtil.formatCompact(amountCny, 'CNY', uzsSymbol: localSymbol);
    }

    return Text(
      text,
      style: style ?? const TextStyle(fontSize: 12, color: Colors.grey),
      overflow: TextOverflow.ellipsis,
    );
  }
}
