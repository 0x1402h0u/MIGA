class CardData {
  final String id;
  final String name;
  final int cost;
  final int attack;
  final int health;
  final List<String> skills;

  /// 副牌组可选项数量（如松鼠牌的 count 参数：蓝色副牌组最多提供的张数），
  /// 0 表示未设置。
  final int count;

  /// 当 cost/attack/health 在 JSON 中是非数字文本（如「铃铛」「血祭（本回合献祭次数）」）时，
  /// 原样保存以便卡面显示提示文字，数值字段为 0。
  final String? costText;
  final String? attackText;
  final String? healthText;

  const CardData({
    required this.id,
    required this.name,
    this.cost = 0,
    this.attack = 0,
    this.health = 0,
    this.skills = const [],
    this.count = 0,
    this.costText,
    this.attackText,
    this.healthText,
  });

  factory CardData.fromJson(Map<String, dynamic> json) {
    final rawSkills = json['skills'];
    return CardData(
      id: (json['no'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      cost: _parseInt(json['cost']),
      attack: _parseInt(json['attack']),
      health: _parseInt(json['health']),
      costText: _textIfNonNumeric(json['cost']),
      attackText: _textIfNonNumeric(json['attack']),
      healthText: _textIfNonNumeric(json['health']),
      skills: rawSkills is List
          ? rawSkills.map((e) => e.toString()).toList()
          : const [],
      count: _parseInt(json['count']),
    );
  }

  Map<String, dynamic> toJson() => {
        'no': id,
        'name': name,
        'cost': costText ?? cost,
        'attack': attackText ?? attack,
        'health': healthText ?? health,
        'skills': skills,
        if (count > 0) 'count': count,
      };

  /// 容错解析数值：支持数字、数字字符串；非数字内容（如特殊牌的中文说明）返回 0。
  static int _parseInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) {
      final n = int.tryParse(value.trim());
      if (n != null) return n;
    }
    return 0;
  }

  /// 若值是非数字文本则原样返回（用于卡面提示），否则返回 null。
  static String? _textIfNonNumeric(dynamic value) {
    if (value is num) return null;
    if (value is String && int.tryParse(value.trim()) == null) {
      return value.trim();
    }
    return null;
  }
}
