import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miga/models/card.dart';
import 'package:miga/utils/deck_share.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  test('deckToJson / deckFromJson 往返一致', () {
    const deck = [
      CardData(
        id: 'wolf',
        name: '狼',
        cost: 2,
        attack: 3,
        health: 2,
        skills: ['锋锐', '潜行'],
      ),
      CardData(id: 'sparrow', name: '麻雀', cost: 1, attack: 1, health: 2),
      CardData(id: 'squirrel', name: '松鼠', cost: 0, attack: 0, health: 1),
    ];
    final json = deckToJson(deck);
    final restored = deckFromJson(json);
    expect(restored, isNotNull);
    expect(restored!.length, 3);
    for (var i = 0; i < deck.length; i++) {
      expect(restored[i].id, deck[i].id);
      expect(restored[i].name, deck[i].name);
      expect(restored[i].cost, deck[i].cost);
      expect(restored[i].attack, deck[i].attack);
      expect(restored[i].health, deck[i].health);
      expect(restored[i].skills, deck[i].skills);
    }
  });

  test('deckFromJson 兼容纯数组与非法输入', () {
    expect(
      deckFromJson('[{"no":"a","name":"甲"},{"no":"a","name":"甲"}]')!.length,
      1,
    );
    expect(deckFromJson('{"type":"miga_deck","version":1,"cards":[]}'),
        isEmpty);
    expect(deckFromJson('not json'), isNull);
    expect(deckFromJson('{"foo":1}'), isNull);
  });

  testWidgets('生成二维码后可解码还原牌组', (tester) async {
    const deck = [
      CardData(id: 'wolf', name: '狼', cost: 2, attack: 3, health: 2),
      CardData(id: 'sparrow', name: '麻雀', cost: 1, attack: 1, health: 2),
      CardData(id: 'fox', name: '狐狸', cost: 1, attack: 2, health: 1),
    ];
    final json = deckToJson(deck);

    // 栅格化需要真实异步，必须放进 tester.runAsync 否则测试会挂起
    final decoded = await tester.runAsync(() async {
      // 用与导出对话框一致的 QrPainter 绘制二维码到离屏画布
      const size = 1024.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // 与导出对话框一致：白底二维码
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, size, size),
        Paint()..color = Colors.white,
      );
      QrPainter(
        data: json,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
        gapless: true,
      ).paint(canvas, const Size(size, size));
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return decodeDeckQr(byteData!.buffer.asUint8List());
    });

    expect(decoded, isNotNull);
    expect(decoded!.length, deck.length);
    expect(decoded.map((c) => c.id), deck.map((c) => c.id));
    expect(decoded.map((c) => c.name), deck.map((c) => c.name));
  });
}
