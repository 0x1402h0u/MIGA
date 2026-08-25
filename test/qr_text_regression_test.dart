import 'package:flutter_test/flutter_test.dart';
import 'package:miga/models/card.dart';
import 'package:miga/utils/deck_share.dart';

void main() {
  // 模拟用户牌库：包含长文本 attack/health 的卡牌
  final deck = List.generate(
    20,
    (i) => CardData(
      id: 'card_$i',
      name: '卡牌$i号',
      cost: i % 3,
      attack: i % 5 == 0 ? 0 : i % 5,
      health: i % 4 == 0 ? 0 : i % 7,
      attackText: i % 5 == 0 ? '铃铛' : null,
      healthText: i % 4 == 0 ? '血祭（本回合献祭次数）' : null,
      skills: ['冲刺能手', '水袭', '兵分两路'],
    ),
  );

  testWidgets('压缩后的牌组二维码可保存并导入还原', (tester) async {
    // 保存到相册用的图片（真实路径 renderDeckQrPng）
    final saved = await tester.runAsync(() => renderDeckQrPng(deck));
    expect(saved, isNotNull);
    final restored = decodeDeckQr(saved!);
    expect(restored, isNotNull);
    expect(restored!.length, 20);
    expect(restored[0].healthText, '血祭（本回合献祭次数）');
    expect(restored[0].attackText, '铃铛');
    expect(restored[1].attackText, isNull);
  });

  testWidgets('对话框二维码（渲染源 560px）可解码', (tester) async {
    final payload = encodeDeckPayload(deck);
    final bytes = renderQrPng(payload, size: 560);
    final decoded = decodeDeckQr(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.length, 20);
  });
}
