import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/inventory_provider.dart';
import '../../models/check_task.dart';
import '../../services/database_service.dart';
import '../../config/constants.dart';

class CheckReportScreen extends StatefulWidget {
  final CheckTask? initialTask;
  const CheckReportScreen({super.key, this.initialTask});

  @override
  State<CheckReportScreen> createState() => _CheckReportScreenState();
}

class _CheckReportScreenState extends State<CheckReportScreen> {
  CheckTask? _selectedTask;
  Map<String, dynamic> _summary = {};
  List<CheckDetail> _allDetails = [];
  Map<String, String> _productNameCache = {};
  Map<String, int> _currentStockCache = {};
  bool _showingAnalysis = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().loadCheckTasks(status: CheckTaskStatus.completed);
      if (widget.initialTask != null) {
        _loadTaskReport(widget.initialTask!);
      }
    });
  }

  Future<void> _loadTaskReport(CheckTask task) async {
    final provider = context.read<InventoryProvider>();
    final summary = await provider.getCheckSummary(task.id!);
    final details = await provider.getCheckDetails(task.id!);

    final db = DatabaseService.instance;
    final nameCache = <String, String>{};
    final stockCache = <String, int>{};
    for (final d in details) {
      if (!nameCache.containsKey(d.barcode)) {
        final product = await db.getProductByBarcode(d.barcode);
        nameCache[d.barcode] = product?.nameCn ?? d.barcode;
        if (product != null) {
          final inv = await db.getInventoryByProductId(product.id!);
          stockCache[d.barcode] = inv?.currentQuantity ?? 0;
        }
      }
    }

    setState(() {
      _selectedTask = task;
      _summary = summary;
      _allDetails = details;
      _productNameCache = nameCache;
      _currentStockCache = stockCache;
      _showingAnalysis = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showingAnalysis ? '盘点分析' : '盘点报表'),
        leading: _showingAnalysis
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _showingAnalysis = false))
            : null,
      ),
      body: Consumer<InventoryProvider>(
        builder: (context, provider, child) {
          final tasks = provider.checkTasks.where((t) => t.status == CheckTaskStatus.completed).toList();

          if (_showingAnalysis && _selectedTask != null) {
            return _buildAnalysisView();
          }

          if (_selectedTask != null && _allDetails.isNotEmpty) {
            return _buildTaskDetailList();
          }

          // ★ v6.18: 选中了任务但没有明细（可能是从云端同步的，明细未上传）
          if (_selectedTask != null && _allDetails.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('暂无盘点明细', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text('盘点明细未上传或已被清除', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('返回任务列表'),
                    onPressed: () => setState(() => _selectedTask = null),
                  ),
                ],
              ),
            );
          }

          if (tasks.isEmpty) {
            return const Center(child: Text('暂无已完成的盘点任务'));
          }

          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final isSelected = _selectedTask?.id == task.id;
              return ListTile(
                selected: isSelected,
                selectedTileColor: AppConstants.primaryColor.withOpacity(0.1),
                title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${task.completedAt?.toString().substring(0, 10) ?? ''} · ${task.checkedItems}项 · ${task.operatorName}',
                    style: const TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _loadTaskReport(task),
              );
            },
          );
        },
      ),
    );
  }

  /// ★ v6.8：任务明细（全屏单列表，含"查看分析"按钮）
  Widget _buildTaskDetailList() {
    final timeStr = _selectedTask?.completedAt?.toString().substring(0, 19) ?? '';
    final operatorName = _selectedTask?.operatorName ?? '';

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.blue.shade50,
          child: Row(children: [
            Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text('$timeStr · 操作人: $operatorName · 共${_allDetails.length}项',
                style: TextStyle(fontSize: 13, color: Colors.blue.shade700))),
            ElevatedButton.icon(
              onPressed: () => setState(() => _showingAnalysis = true),
              icon: const Icon(Icons.analytics, size: 16),
              label: const Text('查看分析', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
            ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() { _selectedTask = null; _allDetails = []; })),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _allDetails.length,
            itemBuilder: (context, index) {
              final d = _allDetails[index];
              final diff = d.difference;
              final diffStr = diff >= 0 ? '+$diff' : '$diff';
              final diffColor = diff > 0 ? Colors.blue : (diff < 0 ? Colors.red : Colors.green);
              final nameCn = _productNameCache[d.barcode] ?? d.barcode;
              final currentStock = _currentStockCache[d.barcode] ?? 0;

              return ListTile(
                leading: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: diffColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text(diffStr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: diffColor))),
                ),
                title: Text(nameCn, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text('条码: ${d.barcode}  |  系统: ${d.systemQuantity}  |  实盘: ${d.actualQuantity}',
                    style: const TextStyle(fontSize: 12)),
                trailing: Text('当前: $currentStock', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              );
            },
          ),
        ),
      ],
    );
  }

  /// ★ v6.8：分析视图（全屏，点返回退到任务明细列表）
  Widget _buildAnalysisView() {
    final totalItems = _summary['total_items'] as int? ?? 0;
    final surplusCount = _summary['surplus_count'] as int? ?? 0;
    final shortageCount = _summary['shortage_count'] as int? ?? 0;
    final matchCount = _summary['match_count'] as int? ?? 0;
    final totalDiff = _summary['total_difference'] as int? ?? 0;
    final matchRate = totalItems > 0 ? (matchCount / totalItems * 100) : 0.0;

    final sorted = List<CheckDetail>.from(_allDetails)
      ..sort((a, b) => b.difference.abs().compareTo(a.difference.abs()));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_selectedTask!.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text('完成: ${_selectedTask!.completedAt?.toString().substring(0, 19) ?? '-'} · ${_selectedTask!.operatorName}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 20),
        _buildSummaryCards(totalItems, surplusCount, shortageCount, matchCount, totalDiff),
        const SizedBox(height: 24),
        _buildPieChart(matchCount, surplusCount, shortageCount, totalItems),
        const SizedBox(height: 24),
        if (sorted.length >= 2) ...[_buildTrendChart(sorted), const SizedBox(height: 24)],
        _buildMatchRate(matchRate),
        const SizedBox(height: 24),
        _buildCoverageAnalysis(),  // ★ v6.27: 全店覆盖率分析
        const SizedBox(height: 24),
        _buildItemDetailTable(sorted),
      ]),
    );
  }

  Widget _buildSummaryCards(int total, int surplus, int shortage, int match, int totalDiff) {
    return Wrap(spacing: 12, runSpacing: 12, children: [
      _card('总数', '$total', Icons.format_list_numbered, Colors.blue),
      _card('吻合', '$match', Icons.check_circle, Colors.green),
      _card('盘盈', '$surplus', Icons.trending_up, Colors.blue),
      _card('盘亏', '$shortage', Icons.trending_down, Colors.red),
      _card('总差异', '${totalDiff >= 0 ? "+" : ""}$totalDiff', Icons.compare_arrows, Colors.orange),
    ]);
  }

  Widget _card(String label, String value, IconData icon, Color color) {
    return Container(width: 105, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(children: [
        Icon(icon, color: color, size: 20), const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ]),
    );
  }

  Widget _buildPieChart(int match, int surplus, int shortage, int total) {
    if (total == 0) return const SizedBox.shrink();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('盘点结果分布', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 16),
      SizedBox(height: 200, child: PieChart(PieChartData(sections: [
        PieChartSectionData(value: match.toDouble(), color: Colors.green, title: '吻合\n$match', radius: 60, titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
        PieChartSectionData(value: surplus.toDouble(), color: Colors.blue, title: '盘盈\n$surplus', radius: 60, titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
        PieChartSectionData(value: shortage.toDouble(), color: Colors.red, title: '盘亏\n$shortage', radius: 60, titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
      ]))),
    ])));
  }

  Widget _buildTrendChart(List<CheckDetail> sorted) {
    final spots = sorted.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.difference.toDouble())).toList();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('差异趋势', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 16),
      SizedBox(height: 200, child: LineChart(LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: const FlTitlesData(leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
        borderData: FlBorderData(show: true),
        lineBarsData: [LineChartBarData(spots: spots, isCurved: false, color: AppConstants.primaryColor, barWidth: 2, dotData: const FlDotData(show: true))],
      ))),
    ])));
  }

  Widget _buildMatchRate(double rate) {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('吻合率', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 12),
      LinearProgressIndicator(value: rate / 100, minHeight: 20, backgroundColor: Colors.grey.shade200, color: rate >= 95 ? Colors.green : rate >= 80 ? Colors.orange : Colors.red, borderRadius: BorderRadius.circular(10)),
      const SizedBox(height: 8),
      Text('${rate.toStringAsFixed(1)}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: rate >= 95 ? Colors.green : rate >= 80 ? Colors.orange : Colors.red)),
    ])));
  }

  /// ★ v6.27: 全店覆盖率分析 — 当前盘点覆盖了多少库存商品
  Widget _buildCoverageAnalysis() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseService.instance.getUncheckedProducts(
        _allDetails.map((d) => d.barcode).toList(),
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final unchecked = snapshot.data!;
        final checkedCount = _allDetails.length;
        final totalCount = checkedCount + unchecked.length;
        if (totalCount == 0) return const SizedBox.shrink();
        final coverageRate = (checkedCount / totalCount * 100);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.store, size: 20, color: coverageRate >= 90 ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                const Text('全店覆盖率', style: TextStyle(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: coverageRate / 100, minHeight: 20, backgroundColor: Colors.grey.shade200,
                color: coverageRate >= 90 ? Colors.green : coverageRate >= 60 ? Colors.orange : Colors.red,
                borderRadius: BorderRadius.circular(10)),
              const SizedBox(height: 8),
              Text('已盘 $checkedCount / 全店库存 $totalCount 种商品 (${coverageRate.toStringAsFixed(1)}%)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                  color: coverageRate >= 90 ? Colors.green : Colors.orange.shade800)),
              if (unchecked.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('未盘到的商品:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ...unchecked.take(5).map((p) => Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                  child: Row(children: [
                    Icon(Icons.radio_button_unchecked, size: 12, color: Colors.red.shade300),
                    const SizedBox(width: 6),
                    Expanded(child: Text(p['name_cn'] as String? ?? '', style: const TextStyle(fontSize: 13))),
                    Text('${p['barcode']}', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                )),
                if (unchecked.length > 5)
                  Text('...等 ${unchecked.length - 5} 种', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ]),
          ),
        );
      },
    );
  }

  Widget _buildItemDetailTable(List<CheckDetail> sorted) {
    if (sorted.isEmpty) return const SizedBox.shrink();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('盘点明细', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const Divider(),
      ConstrainedBox(constraints: const BoxConstraints(maxHeight: 400),
        child: ListView.separated(shrinkWrap: true, itemCount: sorted.length, separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final d = sorted[index]; final diff = d.difference;
            final diffStr = diff >= 0 ? '+$diff' : '$diff';
            final diffColor = diff > 0 ? Colors.blue : (diff < 0 ? Colors.red : Colors.green);
            return ListTile(dense: true,
              leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: diffColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text(diffStr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: diffColor)))),
              title: Text(_productNameCache[d.barcode] ?? d.barcode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text('${d.barcode}  |  系统: ${d.systemQuantity} → 实盘: ${d.actualQuantity}', style: const TextStyle(fontSize: 12)),
            );
          },
        ),
      ),
    ])));
  }
}
