import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/card.dart';

/// 卡牌变量池：全局持有的当前牌库，支持通过 JSON 导入预设牌库。
class CardPool extends ChangeNotifier {
  CardPool._();

  static final CardPool instance = CardPool._();

  final List<CardData> _cards = [];

  /// 当前导入牌库的版本号（JSON 顶层 version 字段），没有则为 null
  String? _version;

  /// 当前牌库（返回副本，避免外部直接修改内部列表）
  List<CardData> get cards => List<CardData>.of(_cards);

  /// 当前导入牌库的版本号
  String? get version => _version;

  /// 直接设置整库（用于启动时从本地恢复）
  void setCards(List<CardData> cards) {
    _cards
      ..clear()
      ..addAll(cards);
    notifyListeners();
  }

  /// 设置牌库版本号（从本地恢复时使用）
  void setVersion(String? version) {
    if (version == _version) return;
    _version = version;
    notifyListeners();
  }

  /// 名为「松鼠」的特殊卡牌（导入牌库后自动识别），没有则返回 null
  CardData? get squirrelCard {
    for (final c in _cards) {
      if (c.name == '松鼠') return c;
    }
    return null;
  }

  /// 蓝色副牌组大小：读取松鼠牌的 count 参数（动态，随 JSON 调整），
  /// 未设置时回退到默认 20。异常值（0/负数/超大）统一收敛到 20。
  int get blueDeckSize {
    final count = squirrelCard?.count ?? 0;
    if (count <= 0 || count > 200) return 20;
    return count;
  }

  void reset() {
    _cards.clear();
    _version = null;
    notifyListeners();
  }

  /// 从 JSON 导入牌库。支持以下格式：
  /// - 单张卡牌对象 `{...}`
  /// - 卡牌数组 `[{...}, {...}]`
  /// - 包装对象 `{"version": "...", "cards": [{...}]}`
  /// 导入成功后替换整个牌库并记录版本号，返回导入的卡牌数量。
  int importJson(String source) {
    final decoded = jsonDecode(source);

    final List<CardData> imported;
    if (decoded is List) {
      _version = null;
      imported = decoded
          .map((e) => CardData.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (decoded is Map<String, dynamic>) {
      _version = decoded['version']?.toString();
      final list = decoded['cards'];
      if (list is List) {
        imported = list
            .map((e) => CardData.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        imported = [CardData.fromJson(decoded)];
      }
    } else {
      throw const FormatException('JSON 格式不正确');
    }

    if (imported.isEmpty) {
      throw const FormatException('牌库为空');
    }

    _cards
      ..clear()
      ..addAll(imported);
    notifyListeners();
    return imported.length;
  }
}
