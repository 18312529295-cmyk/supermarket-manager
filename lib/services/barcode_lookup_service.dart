import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';

class BarcodeLookupResult {
  final bool found;
  final String? name;
  final String? brand;
  final String? category;
  final String? imageUrl;
  final String? quantity;
  final String? origin;
  final String source;

  BarcodeLookupResult({
    required this.found,
    this.name,
    this.brand,
    this.category,
    this.imageUrl,
    this.quantity,
    this.origin,
    required this.source,
  });
}

class BarcodeLookupService {
  static final BarcodeLookupService instance = BarcodeLookupService._internal();
  BarcodeLookupService._internal();

  /// 查询条码信息，先查OpenFoodFacts，失败则返回空
  Future<BarcodeLookupResult> lookup(String barcode) async {
    // 1. 先尝试 OpenFoodFacts（免费、支持中文商品）
    final result = await _lookupOpenFoodFacts(barcode);
    if (result.found) return result;

    return BarcodeLookupResult(found: false, source: 'none');
  }

  /// OpenFoodFacts 查询
  /// 文档: https://world.openfoodfacts.org/data
  Future<BarcodeLookupResult> _lookupOpenFoodFacts(String barcode) async {
    try {
      final url = Uri.parse(
        'https://world.openfoodfacts.org/api/v0/product/$barcode.json',
      );
      final response = await http.get(url).timeout(
        const Duration(seconds: 8),
      );

      if (response.statusCode != 200) {
        return BarcodeLookupResult(found: false, source: 'openfoodfacts');
      }

      final data = jsonDecode(response.body);
      final status = data['status'] ?? 0;
      if (status != 1) {
        return BarcodeLookupResult(found: false, source: 'openfoodfacts');
      }

      final product = data['product'];
      if (product == null) {
        return BarcodeLookupResult(found: false, source: 'openfoodfacts');
      }

      // 提取商品名称（优先中文）
      String? productName = _extractName(product);
      String? brand = product['brands']?.toString();
      String? category = _extractCategory(product);
      String? imageUrl = product['image_url']?.toString();
      String? quantityStr = product['quantity']?.toString();
      String? origin = product['countries']?.toString();

      return BarcodeLookupResult(
        found: true,
        name: productName,
        brand: brand,
        category: category,
        imageUrl: imageUrl,
        quantity: quantityStr,
        origin: origin,
        source: 'openfoodfacts',
      );
    } catch (e) {
      return BarcodeLookupResult(found: false, source: 'openfoodfacts');
    }
  }

  /// 从OpenFoodFacts返回的数据中提取最合适的商品名称
  String? _extractName(Map<String, dynamic> product) {
    // 优先尝试中文名称
    final zhName = product['product_name_zh']?.toString();
    if (zhName != null && zhName.isNotEmpty) return zhName;

    final name = product['product_name']?.toString();
    if (name != null && name.isNotEmpty) return name;

    // 尝试从关键词组合
    final keywords = product['_keywords'];
    if (keywords is List && keywords.isNotEmpty) {
      // 过滤掉英文停用词，取中文关键词
      final cnKeywords = keywords.where((k) {
        if (k is! String) return false;
        // 简单判断：包含中文字符或长度大于2的非英文单词
        return RegExp(r'[\u4e00-\u9fff]').hasMatch(k);
      }).toList();
      if (cnKeywords.isNotEmpty) return cnKeywords.join(' ');
    }

    return null;
  }

  /// 提取品类信息
  String? _extractCategory(Map<String, dynamic> product) {
    final cats = product['categories']?.toString();
    if (cats != null && cats.isNotEmpty) {
      // OpenFoodFacts 返回的是逗号分隔的层级分类，取最后一个（最具体的）
      final parts = cats.split(',').map((s) => s.trim()).toList();
      // 过滤掉英文前缀 en:
      for (final part in parts.reversed) {
        final clean = part.replaceAll(RegExp(r'^en:'), '').trim();
        if (clean.isNotEmpty && !RegExp(r'^[a-z]+$').hasMatch(clean)) {
          return clean;
        }
      }
      return parts.last.replaceAll(RegExp(r'^en:'), '').trim();
    }

    // 尝试从分类层级取
    final catHierarchy = product['categories_hierarchy'];
    if (catHierarchy is List && catHierarchy.isNotEmpty) {
      final last = catHierarchy.last.toString();
      return last.replaceAll(RegExp(r'^en:'), '').trim();
    }

    return null;
  }

  /// 将查询结果转换为 Product 对象（预填充）
  Product? toProduct(String barcode, BarcodeLookupResult result) {
    if (!result.found || result.name == null) return null;

    // 根据品牌或名称猜测品类
    String category = result.category ?? _guessCategory(result.name!, result.brand);

    return Product(
      barcode: barcode,
      nameCn: result.name!,
      nameRu: null,
      nameUz: null,
      category: category,
      priceCny: 0,
      priceUzs: 0,
      supplier: result.brand,
      unit: _guessUnit(result.quantity),
    );
  }

  /// 根据商品名称和品牌猜测品类
  String _guessCategory(String name, String? brand) {
    final lower = name.toLowerCase();
    if (lower.contains('水') || lower.contains('饮料') || lower.contains('茶') ||
        lower.contains('可乐') || lower.contains('果汁') || lower.contains('奶')) {
      return '饮料';
    }
    if (lower.contains('面') || lower.contains('饼干') || lower.contains('薯片') ||
        lower.contains('糖') || lower.contains('巧克力')) {
      return '零食';
    }
    if (lower.contains('油') || lower.contains('酱') || lower.contains('醋') ||
        lower.contains('盐') || lower.contains('调料')) {
      return '调味品';
    }
    if (lower.contains('米') || lower.contains('面粉') || lower.contains('粮')) {
      return '粮油';
    }
    if (lower.contains('洗') || lower.contains('纸') || lower.contains('牙膏')) {
      return '日用品';
    }
    if (lower.contains('冷冻') || lower.contains('饺子') || lower.contains('汤圆')) {
      return '冷冻食品';
    }
    return '其他';
  }

  /// 从 quantity 字段猜测单位
  String? _guessUnit(String? quantity) {
    if (quantity == null || quantity.isEmpty) return '瓶/包';
    final lower = quantity.toLowerCase();
    if (lower.contains('ml') || lower.contains('l')) return '瓶';
    if (lower.contains('g') || lower.contains('kg')) return '包';
    if (lower.contains('个') || lower.contains('支')) return '个';
    return '瓶/包';
  }
}
