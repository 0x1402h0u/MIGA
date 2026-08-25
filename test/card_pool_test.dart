import 'package:flutter_test/flutter_test.dart';

import 'package:miga/data/card_pool.dart';

void main() {
  setUp(CardPool.instance.reset);

  test('imports a single card JSON object', () {
    const json = '{"no": "002", "name": "蝌蚪", "cost": 0, "attack": 0, '
        '"health": 1, "skills": ["水袭", "幼雏（牛蛙）"]}';
    final count = CardPool.instance.importJson(json);

    expect(count, 1);
    final cards = CardPool.instance.cards;
    expect(cards.single.id, '002');
    expect(cards.single.name, '蝌蚪');
    expect(cards.single.cost, 0);
    expect(cards.single.attack, 0);
    expect(cards.single.health, 1);
    expect(cards.single.skills, ['水袭', '幼雏（牛蛙）']);
  });

  test('imports a card array JSON', () {
    const json = '['
        '{"no": "001", "name": "A", "cost": 1, "attack": 2, "health": 3, "skills": ["s1"]},'
        '{"no": "002", "name": "B", "cost": 2, "attack": 1, "health": 2, "skills": ["s2", "s3"]}'
        ']';
    final count = CardPool.instance.importJson(json);

    expect(count, 2);
    expect(CardPool.instance.cards.map((c) => c.id), ['001', '002']);
    expect(CardPool.instance.cards[1].skills, ['s2', 's3']);
  });

  test('rejects invalid JSON', () {
    expect(() => CardPool.instance.importJson('not json'), throwsFormatException);
    expect(() => CardPool.instance.importJson('[]'), throwsFormatException);
  });

  test('reads version from wrapper JSON', () {
    const json = '{"version": "1.0.0", "cards": ['
        '{"no": "001", "name": "松鼠", "cost": 0, "attack": 0, "health": 1, "skills": []}'
        ']}';
    final count = CardPool.instance.importJson(json);
    expect(count, 1);
    expect(CardPool.instance.version, '1.0.0');
    expect(CardPool.instance.cards.single.name, '松鼠');
  });

  test('version resets on plain array import and reset', () {
    const json = '{"version": "2.0", "cards": [{"no": "1", "name": "A"}]}';
    CardPool.instance.importJson(json);
    expect(CardPool.instance.version, '2.0');
    CardPool.instance.importJson('[{"no": "2", "name": "B"}]');
    expect(CardPool.instance.version, isNull);
    CardPool.instance.importJson(json);
    expect(CardPool.instance.version, '2.0');
    CardPool.instance.reset();
    expect(CardPool.instance.version, isNull);
  });

  test('attack/health 为中文说明字符串时保存文本并可往返', () {
    const json = '['
        '{"no": "001", "name": "铃铛卡", "cost": 1, "attack": "铃铛", "health": "血祭（本回合献祭次数）", "skills": []},'
        '{"no": "002", "name": "数字卡", "cost": "2", "attack": "3", "health": 4, "skills": []}'
        ']';
    final count = CardPool.instance.importJson(json);
    expect(count, 2);
    final bell = CardPool.instance.cards[0];
    expect(bell.attack, 0);
    expect(bell.health, 0);
    expect(bell.attackText, '铃铛');
    expect(bell.healthText, '血祭（本回合献祭次数）');
    // 往返导出保持原样
    expect(bell.toJson()['attack'], '铃铛');
    expect(bell.toJson()['health'], '血祭（本回合献祭次数）');
    final numeric = CardPool.instance.cards[1];
    expect(numeric.cost, 2); // 数字字符串也能正确解析
    expect(numeric.attack, 3);
    expect(numeric.health, 4);
    expect(numeric.attackText, isNull);
  });

  test('松鼠牌 count 参数动态控制蓝色副牌组大小', () {
    const json = '{"version": "1.0", "cards": ['
        '{"no": "001", "name": "松鼠", "cost": 0, "attack": 0, "health": 1, "skills": [], "count": 9},'
        '{"no": "002", "name": "狼", "cost": 2, "attack": 3, "health": 2, "skills": []}'
        ']}';
    CardPool.instance.importJson(json);
    expect(CardPool.instance.squirrelCard, isNotNull);
    expect(CardPool.instance.squirrelCard!.count, 9);
    expect(CardPool.instance.blueDeckSize, 9);
    expect(CardPool.instance.squirrelCard!.toJson()['count'], 9);
  });

  test('松鼠无 count 参数时蓝色副牌组回退默认 20', () {
    const json = '{"cards": ['
        '{"no": "001", "name": "松鼠", "cost": 0, "attack": 0, "health": 1, "skills": []}'
        ']}';
    CardPool.instance.importJson(json);
    expect(CardPool.instance.squirrelCard!.count, 0);
    expect(CardPool.instance.blueDeckSize, 20);
  });
}
