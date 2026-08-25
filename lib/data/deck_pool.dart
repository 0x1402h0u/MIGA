import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/card.dart';
import '../models/saved_deck.dart';
import 'local_store.dart';

/// 配装好的牌组池：支持同时持有多个命名卡组，并可切换活动卡组。
/// 活动卡组的牌会在发牌页可用。
class DeckPool extends ChangeNotifier {
  DeckPool._();

  static final DeckPool instance = DeckPool._();

  /// 活动卡组的牌（发牌页使用）
  final List<CardData> _cards = [];

  /// 所有已保存的卡组（名称 + 卡牌 id）
  final List<SavedDeck> _savedDecks = [];

  /// 活动卡组索引
  int _activeIndex = 0;

  /// 活动卡组（当前发牌用）的牌
  List<CardData> get cards => List<CardData>.of(_cards);

  /// 所有已保存卡组
  List<SavedDeck> get savedDecks => List<SavedDeck>.of(_savedDecks);

  /// 活动卡组索引
  int get activeIndex => _activeIndex;

  /// 活动卡组名称
  String get activeDeckName => _activeIndex >= 0 && _activeIndex < _savedDecks.length
      ? _savedDecks[_activeIndex].name
      : '默认卡组';

  /// 直接设置活动卡组（用于测试/兼容），并同步到活动卡组槽
  void setDeck(List<CardData> deck) {
    _cards
      ..clear()
      ..addAll(deck);
    final slot = SavedDeck(name: activeDeckName, cardIds: deck.map((c) => c.id).toList());
    if (_savedDecks.isEmpty) {
      _savedDecks.add(slot);
      _activeIndex = 0;
    } else if (_activeIndex >= 0 && _activeIndex < _savedDecks.length) {
      _savedDecks[_activeIndex] = slot;
    }
    notifyListeners();
  }

  void clear() {
    _cards.clear();
    _savedDecks.clear();
    _activeIndex = 0;
    notifyListeners();
  }

  /// 从本地恢复所有卡组；兼容旧的单卡组数据。
  Future<void> loadDecks(Map<String, CardData> library) async {
    final data = await LocalStore.instance.loadAllDecks();
    if (data != null) {
      _savedDecks
        ..clear()
        ..addAll(data.$1);
      _activeIndex = data.$2.clamp(0, math.max(0, _savedDecks.length - 1));
      _materializeActive(library);
      notifyListeners();
      return;
    }
    // 兼容旧数据：单个卡组
    final oldIds = await LocalStore.instance.loadDeckIds();
    if (oldIds != null && oldIds.isNotEmpty) {
      _savedDecks
        ..clear()
        ..add(SavedDeck(name: '默认卡组', cardIds: List.of(oldIds)));
      _activeIndex = 0;
      _materializeActive(library);
      notifyListeners();
    }
  }

  void _materializeActive(Map<String, CardData> library) {
    _cards.clear();
    if (_activeIndex >= 0 && _activeIndex < _savedDecks.length) {
      for (final id in _savedDecks[_activeIndex].cardIds) {
        final c = library[id];
        if (c != null) _cards.add(c);
      }
    }
  }

  Future<void> _persist() =>
      LocalStore.instance.saveAllDecks(_savedDecks, _activeIndex);

  /// 保存当前选配到活动卡组槽（槽不存在则新建），并设为活动卡组。
  Future<void> saveActiveDeck(String name, List<CardData> deck) async {
    _cards
      ..clear()
      ..addAll(deck);
    final slot = SavedDeck(name: name, cardIds: deck.map((c) => c.id).toList());
    if (_activeIndex >= 0 && _activeIndex < _savedDecks.length) {
      _savedDecks[_activeIndex] = slot;
    } else {
      _savedDecks.add(slot);
      _activeIndex = _savedDecks.length - 1;
    }
    await _persist();
    notifyListeners();
  }

  /// 切换到指定卡组
  Future<void> switchTo(int index, Map<String, CardData> library) async {
    if (index < 0 || index >= _savedDecks.length || index == _activeIndex) {
      return;
    }
    _activeIndex = index;
    _materializeActive(library);
    await _persist();
    notifyListeners();
  }

  /// 新建空卡组并切换过去
  Future<void> addDeck(String name) async {
    _savedDecks.add(SavedDeck(name: name, cardIds: const []));
    _activeIndex = _savedDecks.length - 1;
    _cards.clear();
    await _persist();
    notifyListeners();
  }

  /// 删除指定卡组；删除活动卡组时自动切到相邻卡组
  Future<void> deleteDeck(int index, Map<String, CardData> library) async {
    if (index < 0 || index >= _savedDecks.length) return;
    _savedDecks.removeAt(index);
    if (_savedDecks.isEmpty) {
      _activeIndex = 0;
      _cards.clear();
    } else {
      if (_activeIndex >= _savedDecks.length) {
        _activeIndex = _savedDecks.length - 1;
      }
      _materializeActive(library);
    }
    await _persist();
    notifyListeners();
  }

  /// 重命名指定卡组
  Future<void> renameDeck(int index, String name) async {
    if (index < 0 || index >= _savedDecks.length) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _savedDecks[index] =
        SavedDeck(name: trimmed, cardIds: _savedDecks[index].cardIds);
    await _persist();
    notifyListeners();
  }
}
