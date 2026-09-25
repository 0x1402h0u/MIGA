import 'package:flutter_test/flutter_test.dart';
import 'package:miga/models/analyze_state.dart';

/// 剪贴板格式模板：11 行，参数化每一项以便逐条构造错误用例。
String tmpl({
  String bones = '1',
  String energy = '2',
  String hand = '3',
  String enemyNames = '[蝌蚪][螳螂][][]',
  String enemyStats = '(1/2)(3/4)()()',
  String balance = '0',
  String ownNames = '[麻雀][][]',
  String ownStats = '(5/6)()()()',
  String ownHand = '4',
  String ownBones = '5',
  String ownEnergy = '6',
}) =>
    '骨头:$bones\n'
    '能量:$energy\n'
    '手牌数:$hand\n'
    '$enemyNames\n'
    '$enemyStats\n'
    '天平:$balance\n'
    '$ownNames\n'
    '$ownStats\n'
    '手牌数:$ownHand\n'
    '骨头:$ownBones\n'
    '能量:$ownEnergy\n';

/// 取出解析异常（没抛出就 fail）。
AnalyzeParseException err(String text) {
  try {
    AnalyzeState.parse(text);
  } on AnalyzeParseException catch (e) {
    return e;
  }
  fail('本该抛 AnalyzeParseException，但解析成功了');
}

void main() {
  group('正常解析', () {
    test('11 行全部映射到对应字段', () {
      final s = AnalyzeState.parse(tmpl());
      expect(s.enemy.bones, 1);
      expect(s.enemy.energy, 2);
      expect(s.enemy.handCount, 3);
      expect(s.enemy.slots[0]!.name, '蝌蚪');
      expect(s.enemy.slots[0]!.attack, 1);
      expect(s.enemy.slots[0]!.health, 2);
      expect(s.enemy.slots[1]!.name, '螳螂');
      expect(s.enemy.slots[1]!.attack, 3);
      expect(s.enemy.slots[1]!.health, 4);
      expect(s.enemy.slots[2], isNull);
      expect(s.enemy.slots[3], isNull);
      expect(s.own.bones, 5);
      expect(s.own.energy, 6);
      expect(s.own.handCount, 4);
      expect(s.own.slots[0]!.name, '麻雀');
      expect(s.own.slots[0]!.attack, 5);
      expect(s.own.slots[0]!.health, 6);
      expect(s.own.slots[1], isNull);
    });

    test('天平 -5/0/+5 映射成 0% / 50% / 100%', () {
      expect(AnalyzeState.parse(tmpl(balance: '-5')).balance, 0.0);
      expect(AnalyzeState.parse(tmpl(balance: '0')).balance, 0.5);
      expect(AnalyzeState.parse(tmpl(balance: '5')).balance, 1.0);
      expect(AnalyzeState.parse(tmpl(balance: '2.5')).balance, 0.75);
    });

    test('括号可空：名字空则卡位为空，名字在而数值空按 0/0', () {
      final s = AnalyzeState.parse(
        tmpl(enemyNames: '[A][][][]', enemyStats: '(9/9)(9/9)(9/9)(9/9)'),
      );
      expect(s.enemy.slots[0]!.attack, 9);
      expect(s.enemy.slots[1], isNull);
      final t = AnalyzeState.parse(
        tmpl(enemyNames: '[A][B][][]', enemyStats: '()()()()'),
      );
      expect(t.enemy.slots[0]!.name, 'A');
      expect(t.enemy.slots[0]!.attack, 0);
      expect(t.enemy.slots[0]!.health, 0);
    });

    test('宽容处理：整行前后空格、多余空行、多出来的行、全角括号、尖括号包住的值', () {
      final s = AnalyzeState.parse(
        '  骨头: <7>  \n'
        '\n'
        '能量：8\n'
        '手牌数:9\n'
        '［甲］［乙］\n'
        '（1／2）\n'
        '天平:0\n'
        '[丙]\n'
        '(3/4)\n'
        '手牌数:10\n'
        '骨头:11\n'
        '能量:12\n'
        '这是多出来的一行，应该被忽略\n',
      );
      expect(s.enemy.bones, 7);
      expect(s.enemy.energy, 8);
      expect(s.enemy.handCount, 9);
      expect(s.enemy.slots[0]!.name, '甲');
      expect(s.enemy.slots[0]!.attack, 1);
      expect(s.enemy.slots[0]!.health, 2);
      expect(s.enemy.slots[1]!.name, '乙');
      expect(s.enemy.slots[1]!.attack, 0);
      expect(s.own.bones, 11);
      expect(s.own.energy, 12);
      expect(s.own.handCount, 10);
    });
  });

  group('必填项为空 -> 报错并指出位置', () {
    test('骨头留空（冒号后什么都没有）', () {
      expect(err(tmpl(bones: '')).message, contains('第 1 行「骨头」是空的'));
    });

    test('骨头留成 <> 占位', () {
      expect(err(tmpl(bones: '<>')).message, contains('第 1 行「骨头」是空的'));
    });

    test('每一处必填项都能报出正确行号', () {
      expect(err(tmpl(energy: '')).message, contains('第 2 行「能量」'));
      expect(err(tmpl(hand: '')).message, contains('第 3 行「手牌数」'));
      expect(err(tmpl(balance: '')).message, contains('第 6 行「天平」'));
      expect(err(tmpl(ownHand: '')).message, contains('第 9 行「手牌数」'));
      expect(err(tmpl(ownBones: '')).message, contains('第 10 行「骨头」'));
      expect(err(tmpl(ownEnergy: '')).message, contains('第 11 行「能量」'));
    });
  });

  group('数值不合法', () {
    test('负数', () {
      expect(err(tmpl(bones: '-1')).message, contains('不能小于 0'));
    });

    test('非整数', () {
      expect(err(tmpl(energy: '两个')).message, contains('应该是整数'));
    });

    test('天平超出 -5 ~ 5', () {
      expect(err(tmpl(balance: '5.1')).message, contains('应该在 -5 ~ 5 之间'));
      expect(err(tmpl(balance: '-6')).message, contains('应该在 -5 ~ 5 之间'));
    });

    test('天平不是数字', () {
      expect(err(tmpl(balance: '略')).message, contains('应该是数字'));
    });
  });

  group('结构不对', () {
    test('剪贴板为空', () {
      expect(err('').message, contains('剪贴板里没有文本'));
      expect(err('   \n\n ').message, contains('剪贴板里没有文本'));
    });

    test('行数不足', () {
      expect(err('骨头:1\n能量:2\n手牌数:3\n').message, contains('需要 11 行'));
    });

    test('标签对不上时报出该行', () {
      expect(
        err(tmpl().replaceFirst('骨头:1', '骨:1')).message,
        allOf(contains('第 1 行'), contains('骨头')),
      );
    });

    test('卡牌名行没有方括号', () {
      expect(err(tmpl(enemyNames: '甲 乙')).message, contains('第 4 行'));
    });

    test('数值行没有圆括号', () {
      expect(err(tmpl(ownStats: '1/2 3/4')).message, contains('第 8 行'));
    });

    test('括号内容不是 攻击/血量', () {
      expect(
        err(tmpl(enemyStats: '(1-2)()()()')).message,
        allOf(contains('第 5 行'), contains('第 1 个括号'), contains('攻击/血量')),
      );
    });
  });
}
