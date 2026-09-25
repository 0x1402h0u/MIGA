/// 可视页的数据源：从剪贴板读到的一份对局快照（敌方 / 我方 / 天平进度）。
///
/// 剪贴板格式固定 11 行，`<>` 只是「这里填值」的占位：
///
/// ```
/// 骨头:<>        敌方骨头（必填，≥ 0）
/// 能量:<>        敌方能量（必填，≥ 0）
/// 手牌数:<>      敌方手牌数（必填，≥ 0）
/// [][][][]       敌方四个上场卡位（名字，括号可空）
/// ()()()()       敌方四个卡位数值（攻击/血量，括号可空）
/// 天平:<>        -5 ~ +5，映射成进度条的 0% ~ 100%（必填）
/// [][][][]       我方四个上场卡位
/// ()()()()       我方四个卡位数值
/// 手牌数:<>      我方手牌数（必填，≥ 0）
/// 骨头:<>        我方骨头（必填，≥ 0）
/// 能量:<>        我方能量（必填，≥ 0）
/// ```
///
/// 必填项留空、格式不对、或值超范围时会抛 [AnalyzeParseException]，
/// 异常信息里带上行号和实际读到的内容，直接给用户看。
library;

/// 标准牌桌格式模板（`<>` 是占位符，填真实值）。「复制标准牌桌」用它。
const kBoardTemplate =
    '骨头:<>\n'
    '能量:<>\n'
    '手牌数:<>\n'
    '[][][][]\n'
    '()()()()\n'
    '天平:<>\n'
    '[][][][]\n'
    '()()()()\n'
    '手牌数:<>\n'
    '骨头:<>\n'
    '能量:<>';

/// 是否"像"牌桌数据：四个关键词都在。
///
/// 用来区分两种情况：复制的是别的东西（静静忽略），还是"照抄了但格式不对"
/// （要提示用户「不是标准牌桌格式」并给出标准模板）。
bool looksLikeBoard(String text) =>
    text.contains('骨头') &&
    text.contains('能量') &&
    text.contains('手牌') &&
    text.contains('天平');

/// 一张上场卡牌：剪贴板只给名字和攻击/血量。
class AnalyzeCard {
  const AnalyzeCard({
    required this.name,
    required this.attack,
    required this.health,
  });

  final String name;
  final int attack;
  final int health;
}

/// 一侧（敌方或我方）的数据：三个数值 + 四个上场卡位。
class AnalyzeSide {
  const AnalyzeSide({
    required this.bones,
    required this.energy,
    required this.handCount,
    required this.slots,
  });

  final int bones;
  final int energy;
  final int handCount;

  /// 四个卡位，null = 该位置空着（名字括号里是空的）。
  final List<AnalyzeCard?> slots;
}

/// 一整份快照。
class AnalyzeState {
  const AnalyzeState({
    required this.enemy,
    required this.own,
    required this.balance,
  });

  /// 上半（对面）
  final AnalyzeSide enemy;

  /// 下半（己方，套背景那一半）
  final AnalyzeSide own;

  /// 天平进度，0.0 ~ 1.0（-5 → 0%，+5 → 100%）
  final double balance;

  /// 需要的行数（多出来的行忽略）
  static const lineCount = 11;

  /// 解析剪贴板文本；格式不合法时抛 [AnalyzeParseException]。
  static AnalyzeState parse(String raw) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      throw const AnalyzeParseException('剪贴板里没有文本，请先在游戏里复制对局数据');
    }
    if (lines.length < lineCount) {
      throw AnalyzeParseException(
        '需要 $lineCount 行，只读到 ${lines.length} 行。'
        '顺序是：骨头 / 能量 / 手牌数 / [][][][] / ()()()() / 天平 / '
        '[][][][] / ()()()() / 手牌数 / 骨头 / 能量',
      );
    }

    // 按行号顺序解析，这样报错总是先报最靠上的那一处。
    final enemyBones = _requiredInt(lines[0], '骨头', 1);
    final enemyEnergy = _requiredInt(lines[1], '能量', 2);
    final enemyHand = _requiredInt(lines[2], '手牌数', 3);
    final enemySlots = _slots(lines[4], 5, _names(lines[3], 4));
    final balance = _balance(lines[5], 6);
    final ownSlots = _slots(lines[7], 8, _names(lines[6], 7));
    final ownHand = _requiredInt(lines[8], '手牌数', 9);
    final ownBones = _requiredInt(lines[9], '骨头', 10);
    final ownEnergy = _requiredInt(lines[10], '能量', 11);

    return AnalyzeState(
      enemy: AnalyzeSide(
        bones: enemyBones,
        energy: enemyEnergy,
        handCount: enemyHand,
        slots: enemySlots,
      ),
      own: AnalyzeSide(
        bones: ownBones,
        energy: ownEnergy,
        handCount: ownHand,
        slots: ownSlots,
      ),
      balance: balance,
    );
  }

  /// 取「标签:值」里的值；标签对不上直接报错。
  /// 值两侧的尖括号可有可无（`3` 和 `<3>` 都认，`<>` 视为空）。
  static String _payload(String line, String label, int lineNo) {
    final match = RegExp(
      '^${RegExp.escape(label)}\\s*[:：]\\s*(.*)\$',
    ).firstMatch(line);
    if (match == null) {
      throw AnalyzeParseException('第 $lineNo 行应该是「$label:<>」，实际是「$line」');
    }
    var value = match.group(1)!.trim();
    if (value.length >= 2 && value.startsWith('<') && value.endsWith('>')) {
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  /// 必填的非负整数。
  static int _requiredInt(String line, String label, int lineNo) {
    final value = _payload(line, label, lineNo);
    if (value.isEmpty) {
      throw AnalyzeParseException('第 $lineNo 行「$label」是空的：这一项不能为空，最少填 0');
    }
    final number = int.tryParse(value);
    if (number == null) {
      throw AnalyzeParseException('第 $lineNo 行「$label」应该是整数，实际是「$value」');
    }
    if (number < 0) {
      throw AnalyzeParseException('第 $lineNo 行「$label」不能小于 0，实际是 $number');
    }
    return number;
  }

  /// 必填的天平值：-5 ~ 5，换算成 0.0 ~ 1.0 的进度。
  static double _balance(String line, int lineNo) {
    final value = _payload(line, '天平', lineNo);
    if (value.isEmpty) {
      throw AnalyzeParseException('第 $lineNo 行「天平」是空的：这一项不能为空，范围 -5 ~ 5');
    }
    final number = double.tryParse(value);
    if (number == null) {
      throw AnalyzeParseException('第 $lineNo 行「天平」应该是数字，实际是「$value」');
    }
    if (number < -5 || number > 5) {
      throw AnalyzeParseException('第 $lineNo 行「天平」应该在 -5 ~ 5 之间，实际是 $number');
    }
    return (number + 5) / 10;
  }

  /// 一行里的四个卡牌名（方括号，允许为空）；不够四个后面的按空处理。
  static List<String> _names(String line, int lineNo) {
    final matches = RegExp(r'[\[［]([^\]］]*)[\]］]').allMatches(line).toList();
    if (matches.isEmpty) {
      throw AnalyzeParseException(
        '第 $lineNo 行应该是四个方括号的卡牌名（如 [蝌蚪][螳螂][][]），实际是「$line」',
      );
    }
    return [
      for (var i = 0; i < 4; i++)
        i < matches.length ? matches[i].group(1)!.trim() : '',
    ];
  }

  /// 一行里的四个「攻击/血量」（圆括号，允许为空），和名字按顺序配对。
  static List<AnalyzeCard?> _slots(
    String line,
    int lineNo,
    List<String> names,
  ) {
    final matches = RegExp(r'[\(（]([^\)）]*)[\)）]').allMatches(line).toList();
    if (matches.isEmpty) {
      throw AnalyzeParseException(
        '第 $lineNo 行应该是四个圆括号的数值（如 (1/2)()()()），实际是「$line」',
      );
    }
    return [
      for (var i = 0; i < 4; i++)
        _slot(names[i], i < matches.length ? matches[i].group(1)!.trim() : '',
            lineNo, i + 1),
    ];
  }

  static AnalyzeCard? _slot(String name, String raw, int lineNo, int index) {
    // 名字为空 = 这个位置没有牌，数值一并忽略。
    if (name.isEmpty) return null;
    // 牌在场上、数值留空：按 0/0 显示。
    if (raw.isEmpty) return AnalyzeCard(name: name, attack: 0, health: 0);
    final stat = RegExp(r'^(\d+)\s*[/／]\s*(\d+)$').firstMatch(raw);
    if (stat == null) {
      throw AnalyzeParseException(
        '第 $lineNo 行第 $index 个括号应该是「攻击/血量」，实际是「($raw)」',
      );
    }
    return AnalyzeCard(
      name: name,
      attack: int.parse(stat.group(1)!),
      health: int.parse(stat.group(2)!),
    );
  }
}

/// 剪贴板内容不符合格式时抛出，[message] 是给用户看的说明（含行号）。
class AnalyzeParseException implements Exception {
  const AnalyzeParseException(this.message);

  final String message;

  @override
  String toString() => message;
}
