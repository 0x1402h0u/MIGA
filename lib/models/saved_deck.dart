/// 已保存的卡组：名称 + 卡牌 id 顺序列表（卡牌本体从牌库按 id 解析）。
class SavedDeck {
  final String name;
  final List<String> cardIds;

  const SavedDeck({required this.name, required this.cardIds});

  Map<String, dynamic> toJson() => {
        'name': name,
        'cardIds': cardIds,
      };

  factory SavedDeck.fromJson(Map<String, dynamic> json) => SavedDeck(
        name: json['name']?.toString() ?? '默认卡组',
        cardIds: (json['cardIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}
