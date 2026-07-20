import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../services/database_service.dart';
import '../../providers/app_provider.dart';
import '../../config/country_config.dart';
import '../../widgets/common/currency_display.dart';

/// ==========================================================
/// 销售分析页面 (Sales Analysis Screen)
/// 功能：
///   Tab1: 销售趋势 - 折线图 + 汇总卡片
///   Tab2: 分类排行 - 横向柱状图 (金额/数量切换)
///   Tab3: 单品TOP10 - 列表排名 (按销量/销售额排序)
/// ==========================================================
class SalesAnalysisScreen extends StatefulWidget {
  const SalesAnalysisScreen({super.key});

  @override
  State<SalesAnalysisScreen> createState() => _SalesAnalysisScreenState();
}

class _SalesAnalysisScreenState extends State<SalesAnalysisScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('销售分析'),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          tabs: const [
            Tab(text: '销售趋势'),
            Tab(text: '分类排行'),
            Tab(text: '单品TOP10'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _SalesTrendTab(),
          _CategoryRankingTab(),
          _ProductTop10Tab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('导出功能开发中...'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        icon: const Icon(Icons.ios_share),
        label: const Text('导出报表'),
      ),
    );
  }
}

// ==============================================================
// Tab 1: 销售趋势
// ==============================================================

class _SalesTrendTab extends StatefulWidget {
  const _SalesTrendTab();

  @override
  State<_SalesTrendTab> createState() => _SalesTrendTabState();
}

enum _TimeGranularity { daily, weekly, monthly }

class _SalesTrendTabState extends State<_SalesTrendTab>
 {
  _TimeGranularity _granularity = _TimeGranularity.daily;
  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _trendData = [];
  double _totalSales = 0;
  double _totalSalesUzs = 0;     // ★ v6.34: 当地货币总额
  int _totalQuantity = 0;
  double _avgDailySales = 0;
  double _avgDailySalesUzs = 0;  // ★ v6.34
  double _totalProfit = 0;
  double _totalProfitUzs = 0;    // ★ v6.34

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = DatabaseService.instance;
      List<Map<String, dynamic>> data;

      switch (_granularity) {
        case _TimeGranularity.daily:
          final now = DateTime.now();
          final start = now.subtract(const Duration(days: 30));
          data = await db.getSalesByDateRange(start, now);
          break;
        case _TimeGranularity.weekly:
          data = await db.getWeeklySalesTrend(8);
          break;
        case _TimeGranularity.monthly:
          data = await db.getMonthlySalesTrend(6);
          break;
      }

      // Calculate summary statistics
      double total = 0;
      int qty = 0;
      double profit = 0;
      for (final item in data) {
        total += (item['total_amount_cny'] as num?)?.toDouble() ?? 0;
        qty += (item['total_quantity'] as num?)?.toInt() ?? 0;
        profit += (item['profit_cny'] as num?)?.toDouble() ?? 0;
      }

      if (mounted) {
        setState(() {
          _trendData = data;
          _totalSales = total;
          _totalSalesUzs = data.fold<double>(0, (s, item) => s + ((item['total_amount_uzs'] as num?)?.toDouble() ?? 0));
          _totalQuantity = qty;
          _totalProfit = profit;
          _totalProfitUzs = data.fold<double>(0, (s, item) => s + ((item['profit_cny'] as num?)?.toDouble() ?? 0) * exchangeRate);
          _avgDailySales = data.isNotEmpty ? total / data.length : 0;
          _avgDailySalesUzs = data.isNotEmpty ? _totalSalesUzs / data.length : 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载数据失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildErrorView(_errorMessage!);
    }

      return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Consumer<AppProvider>(
          builder: (context, appProvider, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGranularitySelector(),
                const SizedBox(height: 20),
                _buildTrendChart(),
                const SizedBox(height: 24),
                _buildSummaryCards(appProvider.countryConfig, appProvider.isManager),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGranularitySelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _granularityButton('日', _TimeGranularity.daily),
          _granularityButton('周', _TimeGranularity.weekly),
          _granularityButton('月', _TimeGranularity.monthly),
        ],
      ),
    );
  }

  Widget _granularityButton(String label, _TimeGranularity value) {
    final isSelected = _granularity == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_granularity != value) {
            setState(() => _granularity = value);
            _loadData();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey.shade700,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrendChart() {
    if (_trendData.isEmpty) {
      return _buildEmptyChart('暂无销售趋势数据');
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < _trendData.length; i++) {
      final amount = (_trendData[i]['total_amount_cny'] as num?)?.toDouble() ?? 0;
      spots.add(FlSpot(i.toDouble(), amount));
    }

    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final adjustedMaxY = maxY * 1.2;

    return Container(
      height: 240,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              '销售金额趋势 (¥)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: adjustedMaxY > 0 ? adjustedMaxY / 4 : 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          _formatAxisValue(value),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: _getBottomInterval(),
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= _trendData.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _getBottomLabel(index),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (_trendData.length - 1).toDouble(),
                minY: 0,
                maxY: adjustedMaxY > 0 ? adjustedMaxY : 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: Colors.blue.shade600,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: _trendData.length <= 15,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 3,
                          color: Colors.white,
                          strokeWidth: 2,
                          strokeColor: Colors.blue.shade600,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.shade400.withOpacity(0.3),
                          Colors.blue.shade100.withOpacity(0.05),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final index = spot.x.toInt();
                        final label = index < _trendData.length
                            ? _getTooltipLabel(index)
                            : '';
                        return LineTooltipItem(
                          '$label\n¥${spot.y.toStringAsFixed(2)}',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(CountryConfig countryConfig, bool isManager) {
    final totalCny = _totalSales * countryConfig.cnyExchangeRate > 0 ? _totalSales : 0;
    final avgCny = _avgDailySales * countryConfig.cnyExchangeRate > 0 ? _avgDailySales : 0;
    final profitCny = _totalProfit * countryConfig.cnyExchangeRate > 0 ? _totalProfit : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '销售汇总',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                '总销售额',
                '${_totalSalesUzs.toStringAsFixed(0)} ${countryConfig.currencySymbol}',
                Icons.monetization_on_outlined,
                Colors.blue,
                subtitle: '≈ ¥${_totalSales.toStringAsFixed(2)}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                '总销量',
                '$_totalQuantity 件',
                Icons.shopping_cart_outlined,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSummaryCard(
          '平均日销售额',
          '${_avgDailySalesUzs.toStringAsFixed(0)} ${countryConfig.currencySymbol}',
          Icons.trending_up,
          Colors.orange,
          fullWidth: true,
          subtitle: '≈ ¥${_avgDailySales.toStringAsFixed(2)}',
        ),
        if (isManager) ...[
          const SizedBox(height: 12),
          _buildSummaryCard(
            '盈利',
            '${_totalProfitUzs.toStringAsFixed(0)} ${countryConfig.currencySymbol}',
            Icons.account_balance_wallet_outlined,
            Colors.purple,
            fullWidth: true,
            subtitle: '≈ ¥${_totalProfit.toStringAsFixed(2)}',
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    bool fullWidth = false,
    String? subtitle,
  }) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for chart labels
  double _getBottomInterval() {
    if (_trendData.length <= 7) return 1;
    if (_trendData.length <= 14) return 2;
    return (_trendData.length / 6).ceilToDouble();
  }

  String _getBottomLabel(int index) {
    final item = _trendData[index];
    final date = item['date'] as String? ?? item['period'] as String? ?? '';
    if (date.length >= 10) {
      return '${date.substring(5, 7)}/${date.substring(8, 10)}';
    }
    if (date.length >= 7) {
      return date.substring(5);
    }
    return date;
  }

  String _getTooltipLabel(int index) {
    final item = _trendData[index];
    return item['date'] as String? ?? item['period'] as String? ?? '';
  }

  String _formatAxisValue(double value) {
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}万';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toInt().toString();
  }

  Widget _buildEmptyChart(String message) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================
// Tab 2: 分类排行
// ==============================================================

class _CategoryRankingTab extends StatefulWidget {
  const _CategoryRankingTab();

  @override
  State<_CategoryRankingTab> createState() => _CategoryRankingTabState();
}

enum _CategoryMetric { amount, quantity }

enum _DateRangeOption { last7Days, last30Days, custom }

class _CategoryRankingTabState extends State<_CategoryRankingTab>
 {
  _CategoryMetric _metric = _CategoryMetric.amount;
  _DateRangeOption _dateRange = _DateRangeOption.last7Days;
  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _categoryData = [];
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = DatabaseService.instance;
      final now = DateTime.now();
      late DateTime startDate;
      late DateTime endDate;

      endDate = now;

      switch (_dateRange) {
        case _DateRangeOption.last7Days:
          startDate = now.subtract(const Duration(days: 7));
          break;
        case _DateRangeOption.last30Days:
          startDate = now.subtract(const Duration(days: 30));
          break;
        case _DateRangeOption.custom:
          if (_customRange != null) {
            startDate = _customRange!.start;
            endDate = _customRange!.end;
          } else {
            startDate = now.subtract(const Duration(days: 7));
          }
          break;
      }

      final data = await db.getSalesByCategory(startDate, endDate);

      if (mounted) {
        setState(() {
          _categoryData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载数据失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      locale: const Locale('zh', 'CN'),
      helpText: '选择日期范围',
      cancelText: '取消',
      confirmText: '确定',
      saveText: '确定',
    );

    if (result != null) {
      setState(() {
        _customRange = result;
        _dateRange = _DateRangeOption.custom;
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildErrorView(_errorMessage!);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateRangeSelector(),
            const SizedBox(height: 16),
            _buildMetricToggle(),
            const SizedBox(height: 20),
            _buildBarChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    return Row(
      children: [
        _dateChip('近7天', _DateRangeOption.last7Days),
        const SizedBox(width: 8),
        _dateChip('近30天', _DateRangeOption.last30Days),
        const SizedBox(width: 8),
        ActionChip(
          label: Text(
            _dateRange == _DateRangeOption.custom && _customRange != null
                ? '${_customRange!.start.month}/${_customRange!.start.day}-${_customRange!.end.month}/${_customRange!.end.day}'
                : '自定义',
            style: TextStyle(
              color: _dateRange == _DateRangeOption.custom
                  ? Colors.white
                  : Colors.grey.shade700,
              fontSize: 13,
            ),
          ),
          backgroundColor: _dateRange == _DateRangeOption.custom
              ? Colors.blue
              : Colors.grey.shade100,
          onPressed: _pickCustomDateRange,
        ),
      ],
    );
  }

  Widget _dateChip(String label, _DateRangeOption option) {
    final isSelected = _dateRange == option;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.grey.shade700,
          fontSize: 13,
        ),
      ),
      selected: isSelected,
      selectedColor: Colors.blue,
      backgroundColor: Colors.grey.shade100,
      onSelected: (selected) {
        if (selected) {
          setState(() => _dateRange = option);
          _loadData();
        }
      },
    );
  }

  Widget _buildMetricToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _metricButton('金额 (¥)', _CategoryMetric.amount),
          _metricButton('数量 (件)', _CategoryMetric.quantity),
        ],
      ),
    );
  }

  Widget _metricButton(String label, _CategoryMetric value) {
    final isSelected = _metric == value;
    return GestureDetector(
      onTap: () {
        if (_metric != value) {
          setState(() => _metric = value);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green.shade600 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade600,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    if (_categoryData.isEmpty) {
      return _buildEmptyState('暂无分类销售数据');
    }

    // Sort by selected metric descending
    final sorted = List<Map<String, dynamic>>.from(_categoryData);
    sorted.sort((a, b) {
      if (_metric == _CategoryMetric.amount) {
        final aVal = (a['total_amount_cny'] as num?)?.toDouble() ?? 0;
        final bVal = (b['total_amount_cny'] as num?)?.toDouble() ?? 0;
        return bVal.compareTo(aVal);
      } else {
        final aVal = (a['total_quantity'] as num?)?.toInt() ?? 0;
        final bVal = (b['total_quantity'] as num?)?.toInt() ?? 0;
        return bVal.compareTo(aVal);
      }
    });

    // Take top 8 categories at most
    final displayData = sorted.take(8).toList();

    final maxValue = displayData.map((item) {
      if (_metric == _CategoryMetric.amount) {
        return (item['total_amount_cny'] as num?)?.toDouble() ?? 0;
      } else {
        return (item['total_quantity'] as num?)?.toDouble() ?? 0;
      }
    }).reduce((a, b) => a > b ? a : b);

    final chartHeight = (displayData.length * 52.0).clamp(200.0, 450.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _metric == _CategoryMetric.amount ? '分类销售金额排行' : '分类销售数量排行',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: chartHeight,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxValue * 1.15,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final item = displayData[group.x.toInt()];
                      final category =
                          item['category'] as String? ?? '未分类';
                      final value = _metric == _CategoryMetric.amount
                          ? '¥${rod.toY.toStringAsFixed(2)}'
                          : '${rod.toY.toInt()} 件';
                      return BarTooltipItem(
                        '$category\n$value',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 70,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= displayData.length) {
                          return const SizedBox.shrink();
                        }
                        final category =
                            displayData[index]['category'] as String? ??
                                '未分类';
                        return SizedBox(
                          width: 65,
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: false,
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                barGroups: List.generate(displayData.length, (index) {
                  final item = displayData[index];
                  final value = _metric == _CategoryMetric.amount
                      ? (item['total_amount_cny'] as num?)?.toDouble() ?? 0
                      : (item['total_quantity'] as num?)?.toDouble() ?? 0;

                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: value,
                        width: 18,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(4),
                        ),
                        gradient: LinearGradient(
                          colors: _metric == _CategoryMetric.amount
                              ? [
                                  Colors.blue.shade300,
                                  Colors.blue.shade600,
                                ]
                              : [
                                  Colors.green.shade300,
                                  Colors.green.shade600,
                                ],
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pie_chart_outline, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================
// Tab 3: 单品TOP10
// ==============================================================

class _ProductTop10Tab extends StatefulWidget {
  const _ProductTop10Tab();

  @override
  State<_ProductTop10Tab> createState() => _ProductTop10TabState();
}

enum _SortBy { quantity, revenue }

class _ProductTop10TabState extends State<_ProductTop10Tab>
 {
  _SortBy _sortBy = _SortBy.revenue;
  _DateRangeOption _dateRange = _DateRangeOption.last7Days;
  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _topProducts = [];
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = DatabaseService.instance;
      final now = DateTime.now();
      late DateTime startDate;
      late DateTime endDate;

      endDate = now;

      switch (_dateRange) {
        case _DateRangeOption.last7Days:
          startDate = now.subtract(const Duration(days: 7));
          break;
        case _DateRangeOption.last30Days:
          startDate = now.subtract(const Duration(days: 30));
          break;
        case _DateRangeOption.custom:
          if (_customRange != null) {
            startDate = _customRange!.start;
            endDate = _customRange!.end;
          } else {
            startDate = now.subtract(const Duration(days: 7));
          }
          break;
      }

      final sortField =
          _sortBy == _SortBy.revenue ? 'total_amount_cny' : 'total_quantity';
      final data =
          await db.getTopSellingProducts(startDate, endDate, limit: 10);

      if (mounted) {
        setState(() {
          _topProducts = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载数据失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      locale: const Locale('zh', 'CN'),
      helpText: '选择日期范围',
      cancelText: '取消',
      confirmText: '确定',
      saveText: '确定',
    );

    if (result != null) {
      setState(() {
        _customRange = result;
        _dateRange = _DateRangeOption.custom;
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildErrorView(_errorMessage!);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateRangeSelector(),
            const SizedBox(height: 16),
            _buildSortToggle(),
            const SizedBox(height: 20),
            _buildProductList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    return Row(
      children: [
        _dateChip('近7天', _DateRangeOption.last7Days),
        const SizedBox(width: 8),
        _dateChip('近30天', _DateRangeOption.last30Days),
        const SizedBox(width: 8),
        ActionChip(
          label: Text(
            _dateRange == _DateRangeOption.custom && _customRange != null
                ? '${_customRange!.start.month}/${_customRange!.start.day}-${_customRange!.end.month}/${_customRange!.end.day}'
                : '自定义',
            style: TextStyle(
              color: _dateRange == _DateRangeOption.custom
                  ? Colors.white
                  : Colors.grey.shade700,
              fontSize: 13,
            ),
          ),
          backgroundColor: _dateRange == _DateRangeOption.custom
              ? Colors.blue
              : Colors.grey.shade100,
          onPressed: _pickCustomDateRange,
        ),
      ],
    );
  }

  Widget _dateChip(String label, _DateRangeOption option) {
    final isSelected = _dateRange == option;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.grey.shade700,
          fontSize: 13,
        ),
      ),
      selected: isSelected,
      selectedColor: Colors.blue,
      backgroundColor: Colors.grey.shade100,
      onSelected: (selected) {
        if (selected) {
          setState(() => _dateRange = option);
          _loadData();
        }
      },
    );
  }

  Widget _buildSortToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sortButton('按销售额', _SortBy.revenue),
          _sortButton('按销量', _SortBy.quantity),
        ],
      ),
    );
  }

  Widget _sortButton(String label, _SortBy value) {
    final isSelected = _sortBy == value;
    return GestureDetector(
      onTap: () {
        if (_sortBy != value) {
          setState(() => _sortBy = value);
          _loadData();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade600 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade600,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildProductList() {
    if (_topProducts.isEmpty) {
      return _buildEmptyState('暂无销售数据');
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 32,
                  child: Text('排名',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  flex: 3,
                  child: Text('商品',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const Expanded(
                  flex: 2,
                  child: Text('销量',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const Expanded(
                  flex: 2,
                  child: Text('销售额',
                      textAlign: TextAlign.right,
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          // List items
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _topProducts.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: Colors.grey.shade100),
            itemBuilder: (context, index) {
              final product = _topProducts[index];
              return _buildProductItem(product, index);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProductItem(Map<String, dynamic> product, int index) {
    final name = product['name_cn'] as String? ?? '未知商品';
    final barcode = product['barcode'] as String? ?? '';
    final quantity = (product['total_quantity'] as num?)?.toInt() ?? 0;
    final revenue = (product['total_amount_cny'] as num?)?.toDouble() ?? 0;
    final revenueUzs = (product['total_amount_uzs'] as num?)?.toDouble();

    // ★ v6.31: 获取动态货币符号
    final currencySymbol = context.read<AppProvider>().countryConfig.currencySymbol;

    // Rank badge colors
    Color rankColor;
    Color rankTextColor = Colors.white;
    if (index == 0) {
      rankColor = const Color(0xFFFFD700); // Gold
      rankTextColor = Colors.black87;
    } else if (index == 1) {
      rankColor = const Color(0xFFC0C0C0); // Silver
      rankTextColor = Colors.black87;
    } else if (index == 2) {
      rankColor = const Color(0xFFCD7F32); // Bronze
    } else {
      rankColor = Colors.grey.shade300;
      rankTextColor = Colors.grey.shade700;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rankColor,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: rankTextColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Product info
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  barcode,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          // Quantity
          Expanded(
            flex: 2,
            child: Text(
              '$quantity 件',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: _sortBy == _SortBy.quantity
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
          // Revenue
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '¥${revenue.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _sortBy == _SortBy.revenue
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: Colors.blue.shade700,
                  ),
                ),
                if (revenueUzs != null)
                  Text(
                    '${revenueUzs.toStringAsFixed(0)} $currencySymbol',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
