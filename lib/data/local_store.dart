import 'dart:convert';

import 'package:flutter/material.dart' show Colors;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card.dart';
import '../models/saved_deck.dart';

/// 未完成对局的快照：应用被杀后重启时提示恢复上局手牌。
class PendingHand {
  final List<String> handIds;
  final List<int> handColors;
  final List<String> redDeckIds;
  final int redDeckMax;
  final List<String> blueDeckIds;
  final int blueDeckMax;
  final bool isRedFront;

  const PendingHand({
    required this.handIds,
    required this.handColors,
    required this.redDeckIds,
    required this.redDeckMax,
    required this.blueDeckIds,
    required this.blueDeckMax,
    required this.isRedFront,
  });

  Map<String, dynamic> toJson() => {
    'handIds': handIds,
    'handColors': handColors,
    'redDeckIds': redDeckIds,
    'redDeckMax': redDeckMax,
    'blueDeckIds': blueDeckIds,
    'blueDeckMax': blueDeckMax,
    'isRedFront': isRedFront,
  };

  factory PendingHand.fromJson(Map<String, dynamic> json) => PendingHand(
    handIds: (json['handIds'] as List? ?? const []).cast<String>(),
    handColors: (json['handColors'] as List? ?? const []).cast<int>(),
    redDeckIds: (json['redDeckIds'] as List? ?? const []).cast<String>(),
    redDeckMax: json['redDeckMax'] as int? ?? 0,
    blueDeckIds: (json['blueDeckIds'] as List? ?? const []).cast<String>(),
    blueDeckMax: json['blueDeckMax'] as int? ?? 0,
    isRedFront: json['isRedFront'] as bool? ?? true,
  );
}

/// 本地持久化：保存导入的牌库与配装好的牌组，退出 App 后仍可恢复。
class LocalStore {
  LocalStore._();

  static final LocalStore instance = LocalStore._();

  static const _kLibrary = 'card_library_json';
  static const _kDeckIds = 'deck_card_ids';
  static const _kAllDecks = 'all_decks_json';
  static const _kActiveDeckIndex = 'active_deck_index';
  static const _kOnboardingDone = 'onboarding_done';
  static const _kPlayerName = 'player_name';
  static const _kAvatarPath = 'player_avatar_path';
  static const _kDeckAuthEnabled = 'deck_auth_enabled';
  static const _kUiScale = 'ui_scale';
  static const _kDrawHelpShown = 'draw_help_shown';
  static const _kPendingHand = 'pending_hand';

  static const _kThemeMode = 'theme_mode';
  static const _kUseMonet = 'theme_use_monet';
  static const _kSeedColor = 'theme_seed_color';
  static const _kSchemeVariant = 'theme_scheme_variant';

  // ---- 主题设置持久化 ----

  Future<String?> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kThemeMode);
  }

  Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode);
  }

  Future<bool> getUseMonet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kUseMonet) ?? false;
  }

  Future<void> setUseMonet(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseMonet, value);
  }

  Future<int> getSeedColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kSeedColor) ?? Colors.deepPurple.toARGB32();
  }

  Future<void> setSeedColor(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeedColor, value);
  }

  Future<String?> getSchemeVariant() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSchemeVariant);
  }

  Future<void> setSchemeVariant(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSchemeVariant, name);
  }

  /// 是否已展示过发牌页操作说明（首次使用提示一次）
  Future<bool> isDrawHelpShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDrawHelpShown) ?? false;
  }

  Future<void> setDrawHelpShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDrawHelpShown, true);
  }

  /// 界面缩放系数（1.0 为默认）
  Future<double> getUiScale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kUiScale) ?? 1.0;
  }

  Future<void> setUiScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kUiScale, scale);
  }

  /// 配装页生物识别验证是否开启（默认关闭）
  Future<bool> isDeckAuthEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDeckAuthEnabled) ?? false;
  }

  Future<void> setDeckAuthEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDeckAuthEnabled, enabled);
  }

  Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingDone) ?? false;
  }

  Future<void> setOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDone, true);
  }

  Future<String?> getPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPlayerName);
  }

  Future<void> setPlayerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPlayerName, name);
  }

  Future<String?> getAvatarPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAvatarPath);
  }

  Future<void> setAvatarPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_kAvatarPath);
    } else {
      await prefs.setString(_kAvatarPath, path);
    }
  }

  Future<void> saveLibrary(List<CardData> cards, {String? version}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kLibrary,
      jsonEncode({
        'version': version,
        'cards': cards.map((c) => c.toJson()).toList(),
      }),
    );
  }

  Future<List<CardData>?> loadLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kLibrary);
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      final list = decoded is List ? decoded : (decoded['cards'] as List? ?? const []);
      return list
          .map((e) => CardData.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// 读取已保存牌库的版本号；兼容旧的纯数组格式（返回 null）。
  Future<String?> loadLibraryVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kLibrary);
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) return decoded['version']?.toString();
    } catch (_) {}
    return null;
  }

  Future<void> saveDeck(List<CardData> deck) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kDeckIds, deck.map((c) => c.id).toList());
  }

  Future<List<String>?> loadDeckIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kDeckIds);
  }

  /// 保存未完成对局的手牌快照；手牌为空时请用 [clearPendingHand]
  Future<void> savePendingHand(PendingHand hand) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingHand, jsonEncode(hand.toJson()));
  }

  /// 读取未完成对局快照；无存储或数据损坏返回 null
  Future<PendingHand?> loadPendingHand() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kPendingHand);
    if (json == null) return null;
    try {
      return PendingHand.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPendingHand() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingHand);
  }

  /// 保存所有卡组与活动卡组索引
  Future<void> saveAllDecks(List<SavedDeck> decks, int activeIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kAllDecks,
      jsonEncode(decks.map((d) => d.toJson()).toList()),
    );
    await prefs.setInt(_kActiveDeckIndex, activeIndex);
  }

  /// 读取所有卡组与活动索引；没有存储返回 null
  Future<(List<SavedDeck>, int)?> loadAllDecks() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kAllDecks);
    if (json == null) return null;
    try {
      final list = jsonDecode(json) as List;
      final decks = list
          .map((e) => SavedDeck.fromJson(e as Map<String, dynamic>))
          .toList();
      final index = prefs.getInt(_kActiveDeckIndex) ?? 0;
      return (decks, index);
    } catch (_) {
      return null;
    }
  }
}
