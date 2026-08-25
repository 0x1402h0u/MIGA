import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:miga/data/deck_pool.dart';
import 'package:miga/models/card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeckPool.instance.clear();
  });

  tearDown(DeckPool.instance.clear);

  Map<String, CardData> libraryOf(int n) => {
        for (var i = 1; i <= n; i++)
          '$i': CardData(id: '$i', name: '卡牌$i'),
      };

  test('保存活动卡组创建槽位并可切换', () async {
    final lib = libraryOf(20);
    final deckA = [for (var i = 1; i <= 15; i++) lib['$i']!];
    await DeckPool.instance.saveActiveDeck('卡组A', deckA);

    expect(DeckPool.instance.savedDecks.length, 1);
    expect(DeckPool.instance.activeDeckName, '卡组A');
    expect(DeckPool.instance.cards.length, 15);

    // 新建并切换
    await DeckPool.instance.addDeck('卡组B');
    expect(DeckPool.instance.savedDecks.length, 2);
    expect(DeckPool.instance.activeDeckName, '卡组B');
    expect(DeckPool.instance.cards, isEmpty);

    await DeckPool.instance.switchTo(0, lib);
    expect(DeckPool.instance.activeDeckName, '卡组A');
    expect(DeckPool.instance.cards.length, 15);
  });

  test('删除与重命名', () async {
    final lib = libraryOf(20);
    await DeckPool.instance.addDeck('卡组A');
    await DeckPool.instance.addDeck('卡组B');
    expect(DeckPool.instance.savedDecks.length, 2);

    await DeckPool.instance.renameDeck(0, '改名A');
    expect(DeckPool.instance.savedDecks[0].name, '改名A');

    // 删除活动卡组（卡组B，索引1）
    await DeckPool.instance.deleteDeck(1, lib);
    expect(DeckPool.instance.savedDecks.length, 1);
    expect(DeckPool.instance.activeIndex, 0);
    expect(DeckPool.instance.activeDeckName, '改名A');
  });

  test('持久化：保存后重新加载可恢复', () async {
    final lib = libraryOf(20);
    final deckA = [for (var i = 1; i <= 15; i++) lib['$i']!];
    await DeckPool.instance.saveActiveDeck('卡组A', deckA);
    await DeckPool.instance.addDeck('卡组B');
    await DeckPool.instance.switchTo(0, lib);

    // 模拟重启：新实例重新加载
    DeckPool.instance.clear();
    await DeckPool.instance.loadDecks(lib);
    expect(DeckPool.instance.savedDecks.length, 2);
    expect(DeckPool.instance.activeDeckName, '卡组A');
    expect(DeckPool.instance.cards.length, 15);
    expect(DeckPool.instance.cards.first.id, '1');
  });

  test('兼容旧单卡组数据', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('deck_card_ids', ['1', '2', '3']);
    final lib = libraryOf(20);
    await DeckPool.instance.loadDecks(lib);
    expect(DeckPool.instance.savedDecks.length, 1);
    expect(DeckPool.instance.activeDeckName, '默认卡组');
    expect(DeckPool.instance.cards.length, 3);
  });
}
