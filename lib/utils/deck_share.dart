import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:gal/gal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, MissingPluginException;
import 'package:m3e_core/m3e_core.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr/qr.dart' as qr;
import 'package:zxing2/qrcode.dart' show QRCodeReader;
import 'package:zxing2/zxing2.dart';

import '../data/deck_pool.dart';
import '../data/player_profile.dart';
import '../models/card.dart';

/// 二维码内容前缀：表示内容是 gzip+base64 压缩的牌组 JSON。
const _kPayloadPrefix = 'MIGAZ:';

/// 校验 JSON 能否生成二维码；数据过大（超出 QR 容量）返回错误提示，正常返回 null。
String? qrDataError(String json) {
  try {
    final code = qr.QrCode.fromData(
      data: json,
      errorCorrectLevel: qr.QrErrorCorrectLevel.L,
    );
    qr.QrImage(code); // 触发实际位流生成，数据过大时此处抛出异常
    return null;
  } catch (_) {
    return '牌组数据过大，无法生成二维码';
  }
}

/// 直接把二维码矩阵渲染为 PNG（不依赖 QrPainter）。
///
/// 原因：QrPainter 的模块尺寸会向上取整到 0.5 的整数倍，某些版本下
/// 内容宽度会超过画布导致二维码四周被裁切、无法识别。这里用 floor 取整
/// 保证 module*count <= size，任何版本都不会溢出。
Uint8List renderQrPng(String data, {int size = 800, int quiet = 4}) {
  final code = qr.QrCode.fromData(
    data: data,
    errorCorrectLevel: qr.QrErrorCorrectLevel.L,
  );
  final qrImage = qr.QrImage(code);
  final n = qrImage.moduleCount;
  final total = n + 2 * quiet;
  final module = (size / total).floor();
  final actualSize = module * total;
  final offset = (size - actualSize) ~/ 2;

  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      if (qrImage.isDark(y, x)) {
        img.fillRect(
          canvas,
          x1: offset + (x + quiet) * module,
          y1: offset + (y + quiet) * module,
          x2: offset + (x + quiet + 1) * module,
          y2: offset + (y + quiet + 1) * module,
          color: img.ColorRgba8(0, 0, 0, 255),
        );
      }
    }
  }
  return Uint8List.fromList(img.encodePng(canvas));
}

/// 把配装好的牌组序列化为 JSON 字符串（含版本信息，便于未来扩展）。
String deckToJson(List<CardData> deck) => jsonEncode({
      'type': 'miga_deck',
      'version': 1,
      'cards': deck.map((c) => c.toJson()).toList(),
    });

/// 生成排列好的卡组名称文本（每行一张卡名，便于粘贴/分享）。
String deckNamesText(List<CardData> deck) =>
    deck.map((c) => c.name).join('\n');

/// 生成二维码内容：压缩牌组 JSON（gzip+base64Url）。
/// 显著减小体积、降低二维码版本，避免高版本二维码无法识别。
String encodeDeckPayload(List<CardData> deck) {
  final json = deckToJson(deck);
  final compressed = gzip.encode(utf8.encode(json));
  return '$_kPayloadPrefix${base64Url.encode(compressed)}';
}

/// 从二维码内容还原牌组 JSON。兼容新版压缩格式与旧版纯 JSON。
String? decodeDeckPayload(String text) {
  try {
    if (text.startsWith(_kPayloadPrefix)) {
      final bytes = base64Url.decode(text.substring(_kPayloadPrefix.length));
      return utf8.decode(gzip.decode(bytes));
    }
    return text;
  } catch (_) {
    return null;
  }
}

/// 从 JSON 解析牌组。兼容带包装对象与纯数组两种格式。
/// 返回空列表表示无牌；解析失败返回 null。
List<CardData>? deckFromJson(String json) {
  try {
    final decoded = jsonDecode(json);
    final List<dynamic> raw;
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map && decoded['cards'] is List) {
      raw = decoded['cards'] as List;
    } else {
      return null;
    }
    final cards = <CardData>[];
    final seen = <String>{};
    for (final e in raw) {
      if (e is! Map) continue;
      final card = CardData.fromJson(e.cast<String, dynamic>());
      if (card.id.isEmpty || card.name.isEmpty) continue;
      if (!seen.add(card.id)) continue;
      cards.add(card);
    }
    return cards;
  } catch (_) {
    return null;
  }
}

/// 导出：弹出对话框展示当前牌组的二维码，可保存到相册。
Future<void> showDeckQrDialog(BuildContext context, List<CardData> deck) {
  return showDialog<void>(
    context: context,
    builder: (context) => _DeckQrDialog(deck: deck),
  );
}

class _DeckQrDialog extends StatefulWidget {
  const _DeckQrDialog({required this.deck});

  final List<CardData> deck;

  @override
  State<_DeckQrDialog> createState() => _DeckQrDialogState();
}

class _DeckQrDialogState extends State<_DeckQrDialog> {
  bool _saving = false;
  String? _error;

  late final String _json = encodeDeckPayload(widget.deck);
  late final String? _qrError = qrDataError(_json);
  late final Uint8List? _qrPng =
      _qrError == null ? renderQrPng(_json, size: 560) : null;

  Future<void> _saveToAlbum() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final msg = await saveDeckQrToAlbum(widget.deck);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 复制排列好的卡组名称到剪贴板
  Future<void> _copyNames() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: deckNamesText(widget.deck)));
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('卡组名称已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // State 已缓存 _json/_qrError，重建时不再重跑 gzip+base64 与 QR 位流生成
    final qrError = _qrError;
    return AlertDialog(
      title: const Text('导出牌组'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('共 ${widget.deck.length} 张卡牌，扫码即可分享/导入'),
            const SizedBox(height: 16),
            if (qrError != null)
              Text(
                qrError,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              )
            else
              // 用 renderQrPng 渲染 PNG 显示，避免 QrPainter 的取整裁切问题
              // 和 QrImageView 的 Semantics 断言问题。
              Builder(
                builder: (context) {
                  final qrPng = _qrPng;
                  return Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: qrPng == null
                            ? const SizedBox(width: 280, height: 280)
                            : Image.memory(
                                qrPng,
                                width: 280,
                                height: 280,
                                gaplessPlayback: true,
                              ),
                      ),
                    ),
                  );
                },
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        M3ETextButton(
          onPressed: _saving ? null : _copyNames,
          child: const Text('复制排列'),
        ),
        M3ETextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        M3EFilledButton.tonal(
          onPressed: _saving ? null : _saveToAlbum,
          child: _saving
              // M3E 圆形进度指示器：尺寸 18、细描边，与按钮内一致
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: M3ECircularProgressIndicator(
                    strokeWidth: 2,
                    size: 18,
                  ),
                )
              : const Text('保存相册'),
        ),
      ],
    );
  }
}

/// 渲染牌组二维码 PNG：上方为二维码，下方留白并写上作者名字。
Future<Uint8List> renderDeckQrPng(List<CardData> deck) async {
  const qrSize = 800;
  const nameAreaHeight = 160;
  const width = qrSize;
  const height = qrSize + nameAreaHeight;

  final json = encodeDeckPayload(deck);
  final error = qrDataError(json);
  if (error != null) {
    throw Exception(error);
  }

  // 用 image 包渲染二维码（可靠，无 QrPainter 取整裁切问题），再转成 ui.Image
  final qrPng = renderQrPng(json, size: qrSize);
  final codec = await ui.instantiateImageCodec(qrPng);
  final frame = await codec.getNextFrame();
  final qrUiImage = frame.image;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.white,
  );
  canvas.drawImage(qrUiImage, Offset.zero, Paint());

  final namePainter = TextPainter(
    text: TextSpan(
      text:
          '${PlayerProfile.instance.name}-${DeckPool.instance.activeDeckName}',
      style: const TextStyle(
        color: Colors.black87,
        fontSize: 64,
        fontWeight: FontWeight.w500,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: width.toDouble());
  namePainter.paint(
    canvas,
    Offset((width - namePainter.width) / 2, qrSize + (nameAreaHeight - namePainter.height) / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw Exception('渲染二维码图片失败');
  }
  return byteData.buffer.asUint8List();
}

/// 把牌组二维码保存到系统相册（桌面端无相册则保存为下载目录文件）。
Future<String> saveDeckQrToAlbum(List<CardData> deck) async {
  final bytes = await renderDeckQrPng(deck);
  try {
    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        throw Exception('未获得相册访问权限');
      }
    }
    await Gal.putImageBytes(
      bytes,
      name: 'miga_deck_${DateTime.now().millisecondsSinceEpoch}',
    );
    return '已保存到相册';
  } on MissingPluginException {
    final dir = await getDownloadsDirectory();
    if (dir == null) {
      throw Exception('无法获取下载目录');
    }
    final file = File(
      '${dir.path}/miga_deck_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    return '已保存到 ${file.path}';
  }
}

/// 从相册/文件选择一张二维码图片，解码其中的牌组 JSON。
/// cancelled 为 true 表示用户取消选择；deck 为 null 表示未识别到二维码。
Future<({List<CardData>? deck, bool cancelled})> pickDeckQrImage() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return (deck: null, cancelled: true);
  final bytes = await picked.readAsBytes();
  return (deck: decodeDeckQr(bytes), cancelled: false);
}

/// 从图片字节中解码牌组二维码。为兼顾不同清晰度/方向/光线条件：
/// 先应用 EXIF 方向修正；依次尝试原图、放大图与缩小图几种分辨率
/// （zxing2 对过小的模块识别不稳定，放大后模块更清晰）；二值化用
/// Hybrid 失败后再回退 GlobalHistogram；并开启 tryHarder。
List<CardData>? decodeDeckQr(Uint8List bytes) {
  final original = img.decodeImage(bytes);
  if (original == null) return null;
  img.bakeOrientation(original); // 修正相机照片的旋转/翻转

  final variants = <img.Image>[original];
  final longest = math.max(original.width, original.height);
  // 小图放大：zxing2 对不同模块尺寸很敏感，遍历多种缩放目标，
  // 保证至少命中一个可识别的尺寸（保持宽高比、average 平滑）。
  if (longest < 1600) {
    for (final target in const [700, 800, 900, 1000, 1200, 1400, 1600]) {
      final factor = target / longest;
      variants.add(img.copyResize(
        original,
        width: (original.width * factor).round(),
        height: (original.height * factor).round(),
        interpolation: img.Interpolation.average,
      ));
    }
  }
  // 大图缩小
  for (final target in const [1600, 1200, 800]) {
    if (longest > target) {
      variants.add(img.copyResize(
        original,
        width: (original.width * target / longest).round(),
        height: (original.height * target / longest).round(),
        interpolation: img.Interpolation.average,
      ));
    }
  }

  for (final image in variants) {
    final text = _decodeQrImage(image);
    if (text == null) continue;
    final payload = decodeDeckPayload(text);
    if (payload == null) continue;
    final deck = deckFromJson(payload);
    if (deck != null) return deck;
  }
  return null;
}

String? _decodeQrImage(img.Image image) {
  final rgb = image.convert(numChannels: 3);
  final width = rgb.width;
  final height = rgb.height;
  final bytes = rgb.toUint8List();
  final pixels = Int32List(width * height);
  for (var i = 0; i < pixels.length; i++) {
    final o = i * 3;
    pixels[i] = 0xFF000000 | (bytes[o] << 16) | (bytes[o + 1] << 8) | bytes[o + 2];
  }
  final source = RGBLuminanceSource(width, height, pixels);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  final attempts = <BinaryBitmap>[
    BinaryBitmap(HybridBinarizer(source)),
    BinaryBitmap(GlobalHistogramBinarizer(source)),
  ];
  for (final bitmap in attempts) {
    final text = _decodeBitmap(bitmap, hints);
    if (text != null) return text;
  }
  return null;
}

String? _decodeBitmap(BinaryBitmap bitmap, DecodeHints hints) {
  try {
    final result = QRCodeReader().decode(bitmap, hints: hints);
    // 优先从字节段按 UTF-8 还原文本：qr 包以 UTF-8 字节写入且不带 ECI，
    // zxing2 的 guessCharset 基于有符号字节判断，中文会产生乱码。
    final segments =
        result.resultMetadata[ResultMetadataType.byteSegments];
    if (segments is List) {
      final all = <int>[];
      for (final seg in segments) {
        if (seg is Int8List) {
          for (final b in seg) {
            all.add(b & 0xff);
          }
        }
      }
      if (all.isNotEmpty) {
        try {
          return utf8.decode(all);
        } catch (_) {}
      }
    }
    return result.text;
  } catch (_) {
    return null;
  }
}
