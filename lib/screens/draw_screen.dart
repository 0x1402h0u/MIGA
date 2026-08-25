// M3E Migration 记录：按钮（M3ETextButton 等）已迁移；
// 规则 3 未覆盖组件 AlertDialog 暂用官方 material 最新组件，
// 待官方 M3E 包覆盖后二次迁移。底部滑轨为主按钮属自定义交互，非标准 FAB。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:m3e_core/m3e_core.dart' hide Cubic;

import '../data/card_pool.dart';
import '../data/deck_pool.dart';
import '../data/local_store.dart';
import '../models/card.dart';
import '../widgets/card_face.dart';
import '../widgets/game_card.dart';

/// 牌堆属性：颜色、指示器配色，避免后期换颜色时散落改动
class DeckStyle {
  /// 卡面/卡背颜色（白色 / 淡灰色）
  final Color color;

  /// 指示器/进度条颜色（浅色模式）
  final Color lightAccent;

  /// 指示器/进度条颜色（深色模式）
  final Color darkAccent;

  const DeckStyle({
    required this.color,
    required this.lightAccent,
    required this.darkAccent,
  });

  Color accentFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkAccent : lightAccent;
}

final _redStyle = const DeckStyle(
  color: Color(0xFFFFFFFF), // 白卡
  lightAccent: Color(0xFF000000), // 浅色模式指示器→黑
  darkAccent: Color(0xFFFFFFFF), // 深色模式指示器→白
);
final _blueStyle = const DeckStyle(
  color: Color(0xFFE0E0E0), // 灰卡
  lightAccent: Color(0xFF616161), // 浅色模式指示器→深灰
  darkAccent: Color(0xFFE0E0E0), // 深色模式指示器→浅灰
);
const _confirmRed = Color(0xFFE53935);

const _deckCardWidth = 160.0;
const _deckCardHeight = 224.0;
const _handCardWidth = 120.0;
const _handCardHeight = 168.0;

const _deckCenterY = -160.0;
const _handCenterY = 120.0;
const _cardSpacing = 90.0;

const _dragThreshold = 100.0;
const _dragMax = 138.0;
const _trackWidth = 336.0;
const _trackHeight = 72.0;

const _scaleDown =
    (_handCardWidth / _deckCardWidth + _handCardHeight / _deckCardHeight) / 2;

final _fastOutSlowIn = Curves.fastOutSlowIn;
final _accelerateCurve = const Cubic(0.4, 0.0, 0.9, 0.4);

class FlyingCard {
  final CardData card;
  final Color cardColor;

  const FlyingCard({
    required this.card,
    required this.cardColor,
  });
}

class ReturningCard {
  final CardData card;
  final int handIndex;
  final int delayMs;
  final Color cardColor;

  const ReturningCard({
    required this.card,
    required this.handIndex,
    required this.delayMs,
    required this.cardColor,
  });
}

class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key, this.embedded = false, this.onInGameChanged});

  /// 作为主界面 Tab 嵌入时隐藏返回按钮、放行 PopScope 退出确认
  final bool embedded;

  /// 对局进行状态变化回调（手牌非空或发牌动画中 = 对局进行中），
  /// 供外部禁用 Tab 滑动切换，防止误触。
  final ValueChanged<bool>? onInGameChanged;

  @override
  State<DrawScreen> createState() => DrawScreenState();
}

class DrawScreenState extends State<DrawScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // 红牌堆上限 = 配装牌组数量；蓝牌堆（松鼠）固定 20 张
  /// 当前两牌堆各自的上限（随换牌一起交换，保证进度条始终对应正确内容）
  int _redDeckMax = 0;
  int _blueDeckMax = 0;
  final _redDeck = <CardData>[];
  final _blueDeck = <CardData>[];
  final _handCards = <CardData>[];
  final _handCardColors = <Color>[];
  final _returningCards = <ReturningCard>[];

  FlyingCard? _flyingCard;
  bool _showEmptyHint = true;
  bool _isFirstDraw = true;
  bool _isDrawing = false;
  bool _isRedFront = true;
  double _wheelScroll = 0;

  /// 是否允许直接退出（确认后置为 true，配合 PopScope 放行）
  bool _allowExit = false;

  int _lastHapticCard = -1;
  int _focusedIndex = 0;
  int? _playingCardIndex;

  bool _isDragging = false;
  bool _isPressing = false;
  String? _dragTarget;
  bool _hasSnapped = false;
  bool _confirmResetVisible = false;

  late final AnimationController _handScrollAnim;
  late final AnimationController _deckSwapProgress;
  late final AnimationController _drawButtonScale;
  late final AnimationController _dragOffset;
  late final AnimationController _mainButtonShakeOffset;
  late final AnimationController _lightPulse;
  late Animation<double> _lightPulseAnim;
  late final AnimationController _wheelShift;
  int? _wheelGapIndex;
  bool _isBattle = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _handScrollAnim = AnimationController.unbounded(vsync: this);
    _deckSwapProgress = AnimationController.unbounded(vsync: this);
    _drawButtonScale = AnimationController.unbounded(vsync: this)..value = 1;
    _dragOffset = AnimationController.unbounded(vsync: this);
    _mainButtonShakeOffset = AnimationController.unbounded(vsync: this);
    _lightPulse = AnimationController(vsync: this);
    _wheelShift = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _lightPulseAnim = const AlwaysStoppedAnimation(0.5);
    _setLightPulse(false);

    _handScrollAnim.addListener(() {
      final max = math.max(0, _handCards.length - 1);
      final current = _handScrollAnim.value.round().clamp(0, max);
      if (current != _lastHapticCard && _handCards.isNotEmpty) {
        HapticFeedback.selectionClick();
        _lastHapticCard = current;
      }
    });

    // 牌组在页面初始化后才配置/更新时，空牌堆会一直卡死（_redDeck.isEmpty 挡住发牌），
    // 这里监听牌组变化，牌堆仍为空时重新填充。
    DeckPool.instance.addListener(_onDeckPoolChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_redDeck.isEmpty && _blueDeck.isEmpty) {
        _initDecks();
      }
    });
  }

  /// 牌组更新后，若红牌堆仍为空（启动时牌组未就绪、或之后才配置好牌组）且未开局，
  /// 重新填充牌堆。
  void _onDeckPoolChanged() {
    if (!mounted || _isDrawing) return;
    if (_redDeck.isEmpty && _handCards.isEmpty) {
      _initDecks();
    }
  }

  @override
  void dispose() {
    DeckPool.instance.removeListener(_onDeckPoolChanged);
    _handScrollAnim.dispose();
    _deckSwapProgress.dispose();
    _drawButtonScale.dispose();
    _dragOffset.dispose();
    _mainButtonShakeOffset.dispose();
    _lightPulse.dispose();
    _wheelShift.dispose();
    super.dispose();
  }

  /// 构建红/蓝两堆及其上限，供初始化与重置复用。
  void _fillDecks() {
    final squirrel = CardPool.instance.squirrelCard;
    final squirrelId = squirrel?.id;
    final blueSize = CardPool.instance.blueDeckSize;
    // 红牌堆绝不可能包含松鼠（排除后取配装牌组）；同一洗牌列表供两堆复用
    final pool =
        DeckPool.instance.cards.where((c) => c.id != squirrelId).toList()
          ..shuffle();
    _redDeckMax = math.min(pool.length, 20);
    _redDeck
      ..clear()
      ..addAll(pool.take(_redDeckMax));
    if (squirrel != null) {
      // 蓝色牌堆全部为「松鼠」，数量由 JSON count 参数控制
      _blueDeck
        ..clear()
        ..addAll(List<CardData>.filled(blueSize, squirrel));
      _blueDeckMax = blueSize;
    } else {
      _blueDeck
        ..clear()
        ..addAll(pool.take(blueSize));
      _blueDeckMax = math.min(pool.length, blueSize);
    }
  }

  void _initDecks() {
    setState(_fillDecks);
  }

  /// 将当前手牌/牌堆状态持久化：手牌非空时保存（应用被杀后提示恢复），
  /// 手牌为空（重置 / 全部打出）时清除存档。
  void _persistPendingHand() {
    if (_handCards.isEmpty) {
      unawaited(LocalStore.instance.clearPendingHand());
      return;
    }
    unawaited(
      LocalStore.instance.savePendingHand(
        PendingHand(
          handIds: _handCards.map((c) => c.id).toList(),
          handColors: _handCardColors.map((c) => c.toARGB32()).toList(),
          redDeckIds: _redDeck.map((c) => c.id).toList(),
          redDeckMax: _redDeckMax,
          blueDeckIds: _blueDeck.map((c) => c.id).toList(),
          blueDeckMax: _blueDeckMax,
          isRedFront: _isRedFront,
        ),
      ),
    );
  }

  /// 通知外部对局进行状态是否变化（用于禁用 Tab 滑动切换）
  void _syncGameActive() {
    widget.onInGameChanged?.call(_handCards.isNotEmpty);
  }

  /// 从本地存档恢复未完成的对局（牌堆与手牌）。卡牌不在当前牌库中时跳过；
  /// 手牌全部缺失则视为无效快照并清除存档。
  bool restorePendingHand(PendingHand data) {
    final byId = {for (final c in CardPool.instance.cards) c.id: c};
    final hand = <CardData>[];
    final colors = <Color>[];
    for (var i = 0; i < data.handIds.length; i++) {
      final card = byId[data.handIds[i]];
      if (card == null) continue;
      hand.add(card);
      colors.add(Color(data.handColors[i]));
    }
    if (hand.isEmpty) {
      unawaited(LocalStore.instance.clearPendingHand());
      return false;
    }
    setState(() {
      _handCards
        ..clear()
        ..addAll(hand);
      _handCardColors
        ..clear()
        ..addAll(colors);
      _redDeck
        ..clear()
        ..addAll([
          for (final id in data.redDeckIds)
            if (byId[id] != null) byId[id]!,
        ]);
      _redDeckMax = data.redDeckMax;
      _blueDeck
        ..clear()
        ..addAll([
          for (final id in data.blueDeckIds)
            if (byId[id] != null) byId[id]!,
        ]);
      _blueDeckMax = data.blueDeckMax;
      _isRedFront = data.isRedFront;
      _isFirstDraw = false;
      _showEmptyHint = false;
      _wheelScroll = 0;
      _focusedIndex = 0;
      _handScrollAnim.value = 0;
    });
    // 重新持久化，保证存档与恢复后的实况一致
    _persistPendingHand();
    _syncGameActive();
    return true;
  }

  void _setLightPulse(bool battle) {
    _lightPulseAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: battle ? 0.6 : 0.35, end: battle ? 1.0 : 0.55),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: battle ? 1.0 : 0.55, end: battle ? 0.6 : 0.35),
        weight: 50,
      ),
    ]).animate(_lightPulse);
    _lightPulse
      ..stop()
      ..duration = battle
          ? const Duration(milliseconds: 2400)
          : const Duration(milliseconds: 4000)
      ..repeat();
  }

  Future<void> _shakeMainButton() async {
    Future<void> seq(double to, int ms) => _mainButtonShakeOffset.animateTo(
      to,
      duration: Duration(milliseconds: ms),
    );

    await seq(8, 60);
    await seq(-8, 60);
    await seq(6, 60);
    await seq(-6, 60);
    await seq(4, 50);
    await seq(-4, 50);
    await seq(0, 40);
  }

  /// 首次使用：点击发牌后弹出本页操作说明（只提示一次，持久化记录）
  Future<void> _maybeShowFirstDrawHelp() async {
    if (await LocalStore.instance.isDrawHelpShown()) return;
    await LocalStore.instance.setDrawHelpShown();
    if (!mounted) return;
    showDrawHelp();
  }

  /// 弹出发牌页操作说明（可由标题栏帮助按钮随时重新打开）
  void showDrawHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发牌页操作说明'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HelpRow(icon: Icons.back_hand, text: '点击主按钮抽牌；再次点击继续抽牌'),
              _HelpRow(icon: Icons.refresh, text: '按住主按钮滑到左端重置钮，右端变红后再反向滑到底确认收回手牌'),
              _HelpRow(icon: Icons.swap_horiz, text: '按住主按钮向右滑，切换牌堆'),
              _HelpRow(icon: Icons.touch_app, text: '点击手牌可查看并打出这张牌'),
              _HelpRow(icon: Icons.swipe, text: '在下方手牌区左右滑动浏览卡牌'),
              _HelpRow(icon: Icons.arrow_back, text: '左上角返回键退出对局'),
              SizedBox(height: 8),
              _HelpRow(icon: Icons.help_outline, text: '点击标题栏右上角「？」帮助键可随时重新打开本说明'),
            ],
          ),
        ),
        actions: [
          M3EFilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _drawCards(int count) async {
    if (_isDrawing || _redDeck.isEmpty) return;
    setState(() => _showEmptyHint = false);
    _isDrawing = true;
    _syncGameActive();
    // 异常时也要复位发牌状态并恢复牌堆，避免永久卡死在「发不出牌」
    try {
      unawaited(
        _drawButtonScale.animateTo(
          0.85,
          duration: const Duration(milliseconds: 150),
          curve: _fastOutSlowIn,
        ),
      );

      final isFirstFour = _handCards.isEmpty && count >= 4;
      for (var i = 0; i < count; i++) {
        final fromBlue = isFirstFour && i == 0;
        final deck = fromBlue && _blueDeck.isNotEmpty ? _blueDeck : _redDeck;
        if (deck.isNotEmpty) {
          final card = deck.removeLast();
          final cardColor = fromBlue
              ? _blueStyle.color
              : (_isRedFront ? _redStyle.color : _blueStyle.color);
          final targetIndex = _handCards.length;
          setState(() {
            _flyingCard = FlyingCard(
              card: card,
              cardColor: cardColor,
            );
          });
          unawaited(
            _handScrollAnim.animateTo(
              targetIndex.toDouble(),
              duration: const Duration(milliseconds: 400),
              curve: _fastOutSlowIn,
            ),
          );
          await Future.delayed(const Duration(milliseconds: 1000));
          setState(() {
            _flyingCard = null;
            _handCards.add(card);
            _handCardColors.add(cardColor);
            _focusedIndex = targetIndex;
          });
          _persistPendingHand();
          await Future.delayed(const Duration(milliseconds: 80));
        }
      }
      unawaited(
        _drawButtonScale.animateTo(
          1,
          duration: const Duration(milliseconds: 200),
          curve: _fastOutSlowIn,
        ),
      );
    } finally {
      _isDrawing = false;
      // 发牌动画结束时手牌已达最终状态，同步对局状态（手牌非空则锁定 Tab 滑动）
      _syncGameActive();
      // 若牌堆意外抽空，重新填充，避免卡在「空」无法继续
      if (_redDeck.isEmpty && _blueDeck.isNotEmpty) {
        setState(() {
          _redDeck
            ..clear()
            ..addAll(_blueDeck);
          _redDeckMax = _blueDeckMax;
          _blueDeck.clear();
          _isRedFront = !_isRedFront;
        });
      }
      _persistPendingHand();
    }
  }

  Future<void> _resetGame() async {
    if (_isDrawing || _handCards.isEmpty) return;
    _isDrawing = true;
    _wheelScroll = 0;
    _focusedIndex = 0;
    // 先完整播完滚动回第一张牌的动画，再收回手牌
    await _handScrollAnim.animateTo(
      0,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
    );
    await Future.delayed(const Duration(milliseconds: 80));

    final cards = List<CardData>.from(_handCards);
    final colors = List<Color>.from(_handCardColors);
    final newReturning = <ReturningCard>[
      for (var i = 0; i < cards.length; i++)
        ReturningCard(
          card: cards[i],
          handIndex: i,
          delayMs: i * 60,
          cardColor: colors[i],
        ),
    ];
    setState(() {
      _handCards.clear();
      _handCardColors.clear();
      _returningCards
        ..clear()
        ..addAll(newReturning);
    });

    final maxDelay = cards.length * 60 + 500;
    await Future.delayed(Duration(milliseconds: maxDelay));

    setState(() {
      _returningCards.clear();
      _flyingCard = null;
      _fillDecks();
      _isFirstDraw = true;
      _isRedFront = true;
      _showEmptyHint = true;
    });
    _persistPendingHand();
    _syncGameActive();
    _isDrawing = false;
  }

  Future<void> _swapDecks() async {
    if (_isDrawing || _redDeck.length < 2) return;
    await _deckSwapProgress.animateTo(
      1,
      duration: const Duration(milliseconds: 300),
      curve: _fastOutSlowIn,
    );
    final temp = List<CardData>.from(_redDeck);
    final tempMax = _redDeckMax;
    setState(() {
      _redDeck
        ..clear()
        ..addAll(_blueDeck);
      _redDeckMax = _blueDeckMax;
      _blueDeck
        ..clear()
        ..addAll(temp);
      _blueDeckMax = tempMax;
      _isRedFront = !_isRedFront;
    });
    _persistPendingHand();
    _deckSwapProgress.value = 0;
  }

  /// 点击焦点牌：确认后打出（向上飞出屏幕）
  Future<void> _onPlayFocused(Offset startPos) async {
    if (_handCards.isEmpty || _isDrawing) return;
    final index = _focusedIndex.clamp(0, _handCards.length - 1);
    final card = _handCards[index];
    final color = _handCardColors[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打出这张牌？'),
        content: Text('确定要打出「${card.name}」吗？'),
        actions: [
          M3ETextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          M3EFilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('打出'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _playingCardIndex = index);
      _playCard(index, card, color, startPos);
    }
  }

  void _playCard(int index, CardData card, Color color, Offset startPos) {
    late final OverlayEntry entry;
    var done = false;
    entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: _PlayedCardAnimation(
          card: card,
          color: color,
          startPos: startPos,
          onDone: () {
            if (done || !mounted) return;
            done = true;
            entry.remove();
            _removePlayedCard(index);
          },
        ),
      ),
    );
    Overlay.of(context).insert(entry);
  }

  void _removePlayedCard(int index) {
    if (!mounted) return;
    setState(() {
      if (index < _handCards.length) {
        _handCards.removeAt(index);
        _handCardColors.removeAt(index);
      }
      _playingCardIndex = null;
    });
    _persistPendingHand();
    _syncGameActive();
    if (!mounted) return;
    if (_handCards.isEmpty) {
      setState(() {
        _focusedIndex = 0;
        _wheelScroll = 0;
        _handScrollAnim.value = 0;
      });
      return;
    }
    final maxIdx = (_handCards.length - 1).toDouble();
    final target = _handScrollAnim.value.clamp(0.0, maxIdx).toDouble();
    if (index < _handCards.length) {
      // 打出中间牌：后续牌平滑滑动补位到焦点
      setState(() {
        _focusedIndex = _focusedIndex.clamp(0, _handCards.length - 1);
        _wheelScroll = _handScrollAnim.value.clamp(0.0, maxIdx).toDouble();
        _wheelGapIndex = index;
      });
      _wheelShift.value = 0;
      unawaited(
        _wheelShift.forward().then((_) {
          if (mounted) {
            setState(() => _wheelGapIndex = null);
          }
        }),
      );
    } else if ((_handScrollAnim.value - target).abs() > 0.01) {
      // 打出末尾牌：平滑回卷
      unawaited(
        _handScrollAnim
            .animateTo(
              target,
              duration: const Duration(milliseconds: 250),
              curve: _fastOutSlowIn,
            )
            .then((_) {
              if (!mounted) return;
              setState(() {
                _focusedIndex = _focusedIndex.clamp(0, _handCards.length - 1);
                _wheelScroll = target;
              });
            }),
      );
    } else {
      setState(() {
        _focusedIndex = _focusedIndex.clamp(0, _handCards.length - 1);
        _wheelScroll = _handScrollAnim.value.clamp(0.0, maxIdx).toDouble();
      });
    }
  }

  /// 已进入发牌状态（手牌非空或在发牌动画中）
  bool get _hasDealt => _handCards.isNotEmpty || _isDrawing;

  /// 确认是否退出发牌页
  Future<void> _confirmExit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出发牌'),
        content: const Text('当前手牌还未使用，确定要退出吗？'),
        actions: [
          M3ETextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          M3EFilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      // 先放行 PopScope，等重建完成后再触发退出
      setState(() => _allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isBattle = !_isFirstDraw;
    if (isBattle != _isBattle) {
      _isBattle = isBattle;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _setLightPulse(isBattle),
      );
    }

    return PopScope(
      canPop: widget.embedded || _allowExit || !_hasDealt,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _handScrollAnim,
          _deckSwapProgress,
          _drawButtonScale,
          _dragOffset,
          _mainButtonShakeOffset,
          _wheelShift,
        ]),
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final contentH = h - 100.0;
              final centerX = w / 2;
              final centerY = contentH / 2;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // background
                  Positioned.fill(
                    child: ColoredBox(color: theme.colorScheme.surface),
                  ),
                  // top light effect
                  Positioned.fill(child: _buildLightEffect(isBattle)),
                  // centered content (deck / flying / returning / wheel)
                  Positioned(
                    left: 0,
                    top: 0,
                    width: w,
                    height: contentH,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _buildDeckArea(theme, centerX, centerY),
                        for (var i = 0; i < _returningCards.length; i++)
                          Positioned(
                            left: centerX - _deckCardWidth / 2,
                            top: centerY - _deckCardHeight / 2,
                            child: _ReturningCardView(
                              key: ValueKey(
                                'rc-$i-${_returningCards[i].card.id}',
                              ),
                              returningCard: _returningCards[i],
                              deckCenterY: _deckCenterY,
                              handCenterY: _handCenterY,
                              cardSpacing: _cardSpacing,
                              currentScroll: _wheelScroll,
                              scaleDown: _scaleDown,
                              deckCardWidth: _deckCardWidth,
                              deckCardHeight: _deckCardHeight,
                            ),
                          ),
                        _buildWheel(theme, w, centerY),
                        if (_flyingCard != null)
                          Positioned(
                            left: centerX - _deckCardWidth / 2,
                            top: centerY - _deckCardHeight / 2,
                            child: _FlyingCardView(
                              flyingCard: _flyingCard!,
                              deckCenterY: _deckCenterY,
                              handCenterY: _handCenterY,
                              deckCardWidth: _deckCardWidth,
                              deckCardHeight: _deckCardHeight,
                              scaleDown: _scaleDown,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // bottom buttons
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 80,
                    child: _buildBottomButtons(theme),
                  ),
                  // back button (only when pushed as a secondary page)
                  if (!widget.embedded && Navigator.of(context).canPop())
                    Positioned.fill(
                      child: SafeArea(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Material(
                              color: theme.colorScheme.surfaceContainerHighest,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => Navigator.of(context).maybePop(),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.arrow_back,
                                    size: 24,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // 牌组合规性遮罩：不合规（非 15~20 张）时模糊压暗整页并提示
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: DeckPool.instance,
                      builder: (context, _) {
                        final n = DeckPool.instance.cards.length;
                        final ok =
                            n >= 15 && n <= 20;
                        if (ok) return const SizedBox.shrink();
                        return BackdropFilter(
                          filter: ui.ImageFilter.blur(
                            sigmaX: 4,
                            sigmaY: 4,
                          ),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.55),
                            alignment: Alignment.center,
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: M3ECard(
                                index: 0,
                                position: M3ECardPosition.single,
                                outerRadius: 16,
                                innerRadius: 4,
                                gap: 0,
                                padding: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.warning_amber_rounded,
                                        size: 40,
                                        color: Color(0xFFB00020),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '牌组合规数量为 15~20 张',
                                        style: theme.textTheme.titleMedium,
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '当前为 $n 张，请先在「配装」页调整牌组。',
                                        style: theme.textTheme.bodyMedium,
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLightEffect(bool isBattle) {
    final color = isBattle ? const Color(0xFFCC2200) : const Color(0xFF2266BB);
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: const Duration(milliseconds: 800),
      builder: (context, lightColor, _) {
        // 光效脉冲自己驱动，避免整屏因 _lightPulse 无限 repeat 每帧重建
        return AnimatedBuilder(
          animation: _lightPulse,
          builder: (context, _) => CustomPaint(
            painter: _LightEffectPainter(
              color: lightColor ?? const Color(0xFF2266BB),
              pulse: _lightPulseAnim.value,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }

  Widget _buildDeckArea(ThemeData theme, double centerX, double centerY) {
    final deckLeft = centerX - _deckCardWidth / 2;
    final deckTop = centerY + _deckCenterY - _deckCardHeight / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // deck cards
        Positioned(
          left: deckLeft,
          top: deckTop,
          width: _deckCardWidth,
          height: _deckCardHeight,
          child: _buildDeckCards(),
        ),
        // deck count
        if (_redDeck.length > 2)
          Positioned(
            left: 0,
            right: 0,
            top: centerY + _deckCenterY + _deckCardHeight / 2 + 20 - 12,
            child: Center(
              child: Text(
                '${_redDeck.length}',
                style: theme.textTheme.labelLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDeckCards() {
    if (_redDeck.length >= 2) {
      final p = _deckSwapProgress.value;
      const behindDp = 4.0;
      const slidePx = _deckCardWidth;
      final aX = p * slidePx;
      final aY = p * behindDp;
      final aAlpha = 1 - p;
      final aElev = 6 - p * 2;
      final bX = (1 - p) * -behindDp;
      final bY = (1 - p) * -behindDp;
      final bAlpha = p;
      final bElev = 4 + p * 2;
      final frontColor = _isRedFront ? _redStyle.color : _blueStyle.color;
      final backColor = _isRedFront ? _blueStyle.color : _redStyle.color;

      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: Offset(bX, bY),
            child: Opacity(
              opacity: bAlpha,
              child: GameCard(
                color: backColor,
                elevation: bElev,
                width: _deckCardWidth,
                height: _deckCardHeight,
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(aX, aY),
            child: Opacity(
              opacity: aAlpha,
              child: GameCard(
                color: frontColor,
                elevation: aElev,
                width: _deckCardWidth,
                height: _deckCardHeight,
              ),
            ),
          ),
        ],
      );
    } else if (_redDeck.length == 1) {
      return GameCard(
        color: _isRedFront ? _redStyle.color : _blueStyle.color,
        elevation: 6,
        width: _deckCardWidth,
        height: _deckCardHeight,
      );
    } else if (_flyingCard == null && _returningCards.isEmpty) {
      return Container(
        width: _deckCardWidth,
        height: _deckCardHeight,
        decoration: BoxDecoration(
          color: const Color(0xFFD3D3D3).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          '空',
          style: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
        ),
      );
    }
    return const SizedBox(width: _deckCardWidth, height: _deckCardHeight);
  }

  Widget _buildWheel(ThemeData theme, double width, double centerY) {
    final wheelTop = centerY + _handCenterY - 100;
    return Positioned(
      left: 0,
      right: 0,
      top: wheelTop,
      height: 200,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_showEmptyHint && _handCards.isEmpty)
            Center(
              child: Text(
                '你的手牌是空的',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          if (_handCards.isNotEmpty) ..._buildWheelCards(theme, width),
          if (_handCards.isNotEmpty && !_isDrawing)
            Positioned.fill(
              child: _WheelDragSurface(
                cardSpacing: _cardSpacing,
                cardCount: _handCards.length,
                scroll: _handScrollAnim,
                focusedIndex: _focusedIndex.clamp(
                  0,
                  math.max(0, _handCards.length - 1),
                ),
                onScrollChange: (v) {
                  setState(() {
                    _wheelScroll = v;
                    _focusedIndex = v.round().clamp(
                      0,
                      math.max(0, _handCards.length - 1),
                    );
                  });
                },
                onFocusedCardTap: () =>
                    _onPlayFocused(Offset(width / 2, centerY + _handCenterY)),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildWheelCards(ThemeData theme, double width) {
    final safeFocused = _focusedIndex.clamp(0, _handCards.length - 1);
    final indices = List<int>.generate(_handCards.length, (i) => i);
    // 按与焦点（滚动位置）的距离排序：距离越大越靠前（底层），
    // 越接近焦点的越靠后渲染（在上层），实现「牌进入焦点范围时逐渐置顶」。
    indices.sort((a, b) {
      final da = (a - _handScrollAnim.value).abs();
      final db = (b - _handScrollAnim.value).abs();
      final c = db.compareTo(da);
      return c != 0 ? c : a.compareTo(b);
    });
    return [for (final i in indices) _wheelCard(i, width, safeFocused)];
  }

  Widget _wheelCard(int index, double width, int safeFocused) {
    final distance = index - _handScrollAnim.value;
    final absDist = distance.abs();
    final scale = (1 - absDist * 0.1).clamp(0.6, 1.0);
    final rotation = distance * 5;
    final alpha = (1 - absDist * 0.18).clamp(0.4, 1.0);
    final isFocused = index == safeFocused;
    // 打出中间牌后，后续牌平滑滑动补位
    var gapSlideX = 0.0;
    final gap = _wheelGapIndex;
    if (gap != null && index >= gap) {
      gapSlideX = (1 - _wheelShift.value) * _cardSpacing;
    }

    return Positioned(
      key: ValueKey('wheel-card-$index-${_handCards[index].id}'),
      left:
          width / 2 + distance * _cardSpacing - _handCardWidth / 2 + gapSlideX,
      top: 100 - _handCardHeight / 2,
      // 透明度 + 缩放 + 旋转合并为单个矩阵变换，减少渲染层
      child: Transform(
        transform: Matrix4.rotationZ(rotation * math.pi / 180)
          ..scaleByDouble(scale, scale, 1, 1),
        alignment: Alignment.center,
        child: Opacity(
          opacity: _playingCardIndex == index ? 0 : alpha,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GameCard(
                key: ValueKey(_handCards[index].id),
                color: _handCardColors[index],
                width: _handCardWidth,
                height: _handCardHeight,
                shadowElevation: isFocused ? 10 : 4,
              ),
              Positioned.fill(
                child: CardFace(
                  card: _handCards[index],
                  width: _handCardWidth,
                  height: _handCardHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButtons(ThemeData theme) {
    final isResetEnabled = !_isDrawing;
    // 换堆仅在另一牌堆还有牌时可用
    final isSwapEnabled = !_isDrawing &&
        _redDeck.length >= 2 &&
        _blueDeck.isNotEmpty;
    final inactiveRingColor =
        (_isRedFront ? _blueStyle : _redStyle).accentFor(theme.brightness);
    final activeRingColor =
        (_isRedFront ? _redStyle : _blueStyle).accentFor(theme.brightness);

    return SizedBox(
      height: 88,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 未开局时只显示发牌按钮；首次点击后凹槽从中心向两侧展开、
          // 左右按钮从中心滑出到两端
          IgnorePointer(
            ignoring: _isFirstDraw,
            child: _AnimatedProgress(
              target: _isFirstDraw ? 0.0 : 1.0,
              builder: (p) => SizedBox(
                width: _trackWidth,
                height: 88,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // 凹槽：从中心向两侧水平展开
                    Center(
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment.center,
                          widthFactor: p,
                          heightFactor: 1,
                          child: SizedBox(
                            width: _trackWidth,
                            height: _trackHeight,
                            child: CustomPaint(
                              painter: _GroovePainter(theme.colorScheme),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 重置确认提示：滑到左端重置钮时在轨道上浮现红字
                    IgnorePointer(
                      child: Center(
                        child: Opacity(
                          opacity: _confirmResetVisible ? 1.0 : 0.0,
                          child: const Text(
                            '向右滑动至红色图标以完成重置',
                            style: TextStyle(
                              color: _confirmRed,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 左侧：重置钮，从中心向左滑出
                    Opacity(
                      opacity: p,
                      child: Transform.translate(
                        offset: Offset(_dragMax * (1 - p), 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _buildResetCap(theme),
                          ),
                        ),
                      ),
                    ),
                    // 右侧：换堆钮（环形显示另一牌堆剩余进度），
                    // 向左滑触发重置时变红成确认钮，从中心向右滑出
                    Opacity(
                      opacity: p,
                      child: Transform.translate(
                        offset: Offset(-_dragMax * (1 - p), 0),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _buildSwapCap(
                              theme,
                              isSwapEnabled,
                              inactiveRingColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 中间可在凹槽内左右滑动的拇指按钮
          _buildDrawButton(
            theme,
            isResetEnabled,
            isSwapEnabled,
            activeRingColor,
          ),
        ],
      ),
    );
  }

  /// 左端钮：重置。重置确认态显示在右端换堆钮上
  Widget _buildResetCap(ThemeData theme) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.refresh,
        size: 24,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildSwapCap(ThemeData theme, bool enabled, Color progressColor) {
    final confirming = _confirmResetVisible;
    final isActive = _dragTarget == 'swap' && enabled;
    final scale = confirming || isActive ? 1.15 : 1.0;
    // 外层 AnimatedBuilder 每帧重建，若用 TweenAnimationBuilder 会每帧重置动画、
    // 进度永远停在初始值，因此直接按当前剩余比例渲染。
    final progress =
        _blueDeck.isNotEmpty && _blueDeckMax > 0
            ? _blueDeck.length / _blueDeckMax
            : 0.0;
    return Transform.scale(
      scale: scale,
      child: _AnimatedProgress(
        target: progress,
        builder: (v) => _RingBox(
          size: 48,
          radius: 20,
          strokeWidth: 3,
          progress: confirming ? 1.0 : v,
          color: confirming ? _confirmRed : progressColor,
          bgColor: theme.colorScheme.surface,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: _fastOutSlowIn,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: confirming
                  ? _confirmRed
                  : isActive
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: confirming
                  ? [
                      BoxShadow(
                        color: _confirmRed.withValues(alpha: 0.45),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Icon(
                confirming ? Icons.check : Icons.swap_horiz,
                key: ValueKey<bool>(confirming),
                size: 22,
                color: confirming
                    ? Colors.white
                    : isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawButton(
    ThemeData theme,
    bool isResetEnabled,
    bool isSwapEnabled,
    Color activeRingColor,
  ) {
    final enabled = !_isDrawing && _redDeck.isNotEmpty;
    final ringAlpha = _isFirstDraw ? 0.0 : 1.0;
    final ringScale = _isDragging ? 0.0 : 1.0;
    final icon = switch (_dragTarget) {
      'reset' => Icons.refresh,
      'swap' => Icons.swap_horiz,
      _ => Icons.back_hand,
    };
    final activeProgressTarget = _redDeck.isNotEmpty && _redDeckMax > 0
        ? _redDeck.length / _redDeckMax
        : 0.0;

    return GestureDetector(
      onTap: () {
        if (_dragOffset.value == 0) {
          if (_isFirstDraw) {
            unawaited(_drawCards(4));
            _isFirstDraw = false;
            // 首次使用：弹出本页操作说明
            unawaited(_maybeShowFirstDrawHelp());
          } else {
            unawaited(_drawCards(1));
          }
        }
      },
      onPanStart: (_) {
        if ((_handCards.isEmpty && _isFirstDraw) || _isDrawing) {
          _isDragging = false;
          return;
        }
        setState(() {
          _isDragging = true;
          _hasSnapped = false;
          _confirmResetVisible = false;
        });
      },
      onPanUpdate: (details) {
        if ((_handCards.isEmpty && _isFirstDraw) || _isDrawing) return;
        final newOffset = (_dragOffset.value + details.delta.dx).clamp(
          -_dragMax,
          _dragMax,
        );
        _dragOffset.value = newOffset;

        if (_confirmResetVisible) {
          // 已滑到左端重置钮触发确认：再反向滑完全程、盖住右端确认钮才真正重置
          final reachedConfirm = newOffset >= _dragMax - 20;
          _dragTarget = reachedConfirm ? 'confirm_reset' : null;
          if (reachedConfirm != _hasSnapped) {
            HapticFeedback.heavyImpact();
            _hasSnapped = reachedConfirm;
          }
        } else {
          final String? rawTarget = switch (newOffset) {
            < -_dragThreshold => 'reset',
            > _dragThreshold => 'swap',
            _ => null,
          };
          final isTargetEnabled = switch (rawTarget) {
            'reset' => isResetEnabled,
            'swap' => isSwapEnabled,
            _ => true,
          };
          final newTarget = isTargetEnabled ? rawTarget : null;
          if (newTarget != null && !_hasSnapped) {
            HapticFeedback.heavyImpact();
            _hasSnapped = true;
            if (newTarget == 'reset') {
              // 换成红色确认态，再往左推到底才真正重置
              _confirmResetVisible = true;
            }
          }
          if (rawTarget != null && !isTargetEnabled && !_hasSnapped) {
            HapticFeedback.heavyImpact();
            HapticFeedback.heavyImpact();
            unawaited(_shakeMainButton());
            _hasSnapped = true;
          }
          if (rawTarget == null) _hasSnapped = false;
          _dragTarget = newTarget;
        }
      },
      onPanEnd: (_) {
        if ((_handCards.isEmpty && _isFirstDraw) || _isDrawing) {
          _isDragging = false;
          _dragTarget = null;
          unawaited(
            _dragOffset.animateTo(
              0,
              duration: const Duration(milliseconds: 200),
              curve: _fastOutSlowIn,
            ),
          );
          return;
        }
        _isDragging = false;
        final target = _dragTarget;
        unawaited(
          _dragOffset.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: _fastOutSlowIn,
          ),
        );
        _dragTarget = null;
        _hasSnapped = false;
        _confirmResetVisible = false;
        if (target == 'confirm_reset' && !_isDrawing) {
          unawaited(_resetGame());
        }
        if (target == 'swap' && !_isDrawing && _redDeck.length >= 2) {
          unawaited(_swapDecks());
        }
      },
      onPanCancel: () {
        _isDragging = false;
        _dragTarget = null;
        _confirmResetVisible = false;
        unawaited(
          _dragOffset.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: _fastOutSlowIn,
          ),
        );
      },
      child: Transform.translate(
        offset: Offset(_dragOffset.value + _mainButtonShakeOffset.value, 0),
        child: Listener(
          onPointerDown: (_) {
            if (_isPressing) return;
            setState(() => _isPressing = true);
          },
          onPointerUp: (_) => setState(() => _isPressing = false),
          onPointerCancel: (_) => setState(() => _isPressing = false),
          child: SizedBox(
            width: 68,
            height: 68,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // active ring
              TweenAnimationBuilder<double>(
                tween: Tween(end: ringAlpha),
                duration: const Duration(milliseconds: 400),
                curve: _fastOutSlowIn,
                builder: (context, alpha, _) {
                  return Opacity(
                    opacity: alpha.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: ringScale,
                        child: _AnimatedProgress(
                          target: activeProgressTarget,
                          builder: (v) => _RingBox(
                            size: 68,
                            radius: 30,
                            strokeWidth: 3.5,
                            progress: v,
                            color: activeRingColor,
                            bgColor: theme.colorScheme.surfaceContainerHighest,
                            child: const SizedBox.shrink(),
                          ),
                        ),
                      ),
                  );
                },
              ),
              // button（按住时微微放大，像是被压扁）
              Transform.scale(
                scale: _drawButtonScale.value,
                child: AnimatedScale(
                  scale: _isPressing ? 1.2 : 1.0,
                  duration: const Duration(milliseconds: 120),
                  curve: _fastOutSlowIn,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: enabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 28,
                          color: enabled
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _isPressing ? 0.3 : 0.0,
                            duration: const Duration(milliseconds: 120),
                            curve: _fastOutSlowIn,
                            child: const SizedBox(
                              width: 56,
                              height: 56,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _LightEffectPainter extends CustomPainter {
  const _LightEffectPainter({required this.color, required this.pulse});

  final Color color;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final center = Offset(cx, 0);

    final outerRadius = size.width * 0.9;
    final outerPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: pulse * 0.15),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius));
    canvas.drawCircle(center, outerRadius, outerPaint);

    final innerRadius = size.width * 0.35;
    final innerPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: pulse * 0.25),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: innerRadius));
    canvas.drawCircle(center, innerRadius, innerPaint);
  }

  @override
  bool shouldRepaint(_LightEffectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pulse != pulse;
}

/// 操作说明中的一行：图标 + 文字
class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// 平滑过渡到目标值的进度动画。
/// 外层 AnimatedBuilder 每帧重建，若直接传新的 Tween 会每帧重启动画；
/// 这里缓存 Tween，只在目标真正变化时才新建，交给框架的 TweenAnimationBuilder 驱动。
class _AnimatedProgress extends StatefulWidget {
  const _AnimatedProgress({required this.target, required this.builder});

  final double target;
  final Widget Function(double value) builder;

  @override
  State<_AnimatedProgress> createState() => _AnimatedProgressState();
}

class _AnimatedProgressState extends State<_AnimatedProgress> {
  late Tween<double> _tween =
      Tween<double>(begin: widget.target, end: widget.target);

  @override
  void didUpdateWidget(_AnimatedProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target != oldWidget.target) {
      _tween = Tween<double>(begin: _tween.end!, end: widget.target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: _tween,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => widget.builder(value),
    );
  }
}

/// 凹槽轨道背景：扁平圆角槽，仅靠底色与内层浅色区分
class _GroovePainter extends CustomPainter {
  const _GroovePainter(this.colorScheme);

  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = colorScheme.surfaceContainerHighest,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colorScheme.outlineVariant.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_GroovePainter oldDelegate) =>
      oldDelegate.colorScheme != colorScheme;
}

class _RingBox extends StatelessWidget {  const _RingBox({
    required this.size,
    required this.radius,
    required this.strokeWidth,
    required this.progress,
    required this.color,
    required this.bgColor,
    required this.child,
  });

  final double size;
  final double radius;
  final double strokeWidth;
  final double progress;
  final Color color;
  final Color bgColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress,
          color: color,
          bgColor: bgColor,
          radius: radius,
          strokeWidth: strokeWidth,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.bgColor,
    required this.radius,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color bgColor;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 2;
    final rect = Rect.fromCircle(center: Offset(c, c), radius: radius);
    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi, false, bgPaint);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        fgPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.bgColor != bgColor ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _WheelDragSurface extends StatefulWidget {
  const _WheelDragSurface({
    required this.cardSpacing,
    required this.cardCount,
    required this.scroll,
    required this.focusedIndex,
    required this.onScrollChange,
    required this.onFocusedCardTap,
  });

  final double cardSpacing;
  final int cardCount;
  final AnimationController scroll;
  final int focusedIndex;
  final ValueChanged<double> onScrollChange;
  final VoidCallback onFocusedCardTap;

  @override
  State<_WheelDragSurface> createState() => _WheelDragSurfaceState();
}

class _WheelDragSurfaceState extends State<_WheelDragSurface> {
  final _posHistory = <(double, double)>[];

  /// 越界阻尼：指数式，越拖越「紧」，像拉橡皮筋
  double _damp(double over) {
    const k = 36.0;
    return k * (1 - math.exp(-over / k));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        widget.scroll.stop();
        _posHistory.clear();
      },
      onHorizontalDragUpdate: (details) {
        final now = details.sourceTimeStamp!.inMilliseconds;
        _posHistory.removeWhere((entry) => entry.$1 < now - 100);
        _posHistory.add((now.toDouble(), details.localPosition.dx));

        final deltaInCards = -details.delta.dx / widget.cardSpacing * 1.8;
        final currentMax = math.max(0, (widget.cardCount - 1).toDouble());
        final raw = widget.scroll.value + deltaInCards;
        // 两端越界时施加指数阻尼，制造弹簧手感
        final target = raw < 0
            ? -_damp(-raw)
            : raw > currentMax
            ? currentMax + _damp(raw - currentMax)
            : raw.clamp(0.0, currentMax).toDouble();
        widget.scroll.value = target;
      },
      onHorizontalDragEnd: (details) {
        final currentMax = math.max(0, (widget.cardCount - 1).toDouble());
        final pos = widget.scroll.value;

        double velocityPxPerSec = 0;
        double amplitudeCards = 0;
        if (_posHistory.length >= 2) {
          final (t1, x1) = _posHistory.first;
          final (t2, x2) = _posHistory.last;
          final dt = t2 - t1;
          if (dt > 0) velocityPxPerSec = (x2 - x1) / dt * 1000;
          amplitudeCards = (x2 - x1).abs() / widget.cardSpacing;
        }
        final velocityInCards = -velocityPxPerSec / widget.cardSpacing;

        if (pos < 0 || pos > currentMax) {
          // 越界回弹：用弹簧动画轻微过冲后弹回端点
          final clamped = pos.clamp(0.0, currentMax).toDouble();
          unawaited(
            widget.scroll
                .animateWith(
                  SpringSimulation(
                    const SpringDescription(
                      mass: 1,
                      stiffness: 1800,
                      damping: 30,
                    ),
                    pos,
                    clamped,
                    0,
                  ),
                )
                .then((_) => widget.onScrollChange(clamped)),
          );
        } else {
          final nearestCard = pos
              .roundToDouble()
              .clamp(0.0, currentMax)
              .toDouble();
          final targetPos = amplitudeCards < 1
              ? nearestCard
              : (pos + velocityInCards * 0.3 + amplitudeCards * 0.5)
                    .clamp(0.0, currentMax)
                    .roundToDouble();
          unawaited(
            widget.scroll
                .animateTo(
                  targetPos,
                  duration: const Duration(milliseconds: 250),
                  curve: _fastOutSlowIn,
                )
                .then((_) => widget.onScrollChange(targetPos)),
          );
        }
        _posHistory.clear();
      },
      onTapUp: (details) {
        final width = context.size?.width ?? 0;
        if (width <= 0) return;
        // 只剩一张牌时，点击即视为点中焦点牌（可直接打出）
        if (widget.cardCount <= 1) {
          widget.onFocusedCardTap();
          return;
        }
        // 点击非焦点牌：把轮盘旋转到让这张牌回到眼前
        final centerX = width / 2;
        final deltaInCards =
            (details.localPosition.dx - centerX) / widget.cardSpacing;
        final tappedIndex = (widget.scroll.value + deltaInCards).round().clamp(
          0,
          widget.cardCount - 1,
        );
        // 点击当前焦点牌：视为要打出这张牌
        if (tappedIndex == widget.focusedIndex) {
          widget.onFocusedCardTap();
          return;
        }
        unawaited(
          widget.scroll
              .animateTo(
                tappedIndex.toDouble(),
                duration: const Duration(milliseconds: 250),
                curve: _fastOutSlowIn,
              )
              .then((_) => widget.onScrollChange(tappedIndex.toDouble())),
        );
      },
      child: const SizedBox.expand(),
    );
  }
}

class _FlyingCardView extends StatefulWidget {
  const _FlyingCardView({
    required this.flyingCard,
    required this.deckCenterY,
    required this.handCenterY,
    required this.deckCardWidth,
    required this.deckCardHeight,
    required this.scaleDown,
  });

  final FlyingCard flyingCard;
  final double deckCenterY;
  final double handCenterY;
  final double deckCardWidth;
  final double deckCardHeight;
  final double scaleDown;

  @override
  State<_FlyingCardView> createState() => _FlyingCardViewState();
}

class _FlyingCardViewState extends State<_FlyingCardView>
    with TickerProviderStateMixin {
  late final AnimationController _animY;
  late final AnimationController _animX;
  late final AnimationController _animRotation;
  late final AnimationController _animScale;
  late final AnimationController _flipRotation;

  @override
  void initState() {
    super.initState();
    _animY = AnimationController.unbounded(vsync: this)
      ..value = widget.deckCenterY;
    _animX = AnimationController.unbounded(vsync: this);
    _animRotation = AnimationController.unbounded(vsync: this);
    _animScale = AnimationController.unbounded(vsync: this)..value = 1;
    _flipRotation = AnimationController.unbounded(vsync: this)..value = 0;

    _run();
  }

  Future<void> _run() async {
    // 1. 悬浮升起
    await Future.wait([
      _animScale.animateTo(
        1.15,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      ),
      _animY.animateTo(
        widget.deckCenterY - 40,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      ),
    ]);
    // 2. 翻面，露出卡面信息
    await _flipRotation.animateTo(
      math.pi,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    // 3. 飞向手牌
    await Future.wait([
      _animY.animateTo(
        widget.handCenterY,
        duration: const Duration(milliseconds: 450),
        curve: _fastOutSlowIn,
      ),
      _animScale.animateTo(
        widget.scaleDown,
        duration: const Duration(milliseconds: 450),
        curve: _fastOutSlowIn,
      ),
    ]);
  }

  @override
  void dispose() {
    _animY.dispose();
    _animX.dispose();
    _animRotation.dispose();
    _animScale.dispose();
    _flipRotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _animY,
        _animX,
        _animRotation,
        _animScale,
        _flipRotation,
      ]),
      builder: (context, _) {
        final flip = _flipRotation.value;
        final showFront = flip >= math.pi / 2;
        final angle = showFront ? flip - math.pi : flip;
        final back = GameCard(
          color: widget.flyingCard.cardColor,
          elevation: 12,
          width: widget.deckCardWidth,
          height: widget.deckCardHeight,
        );
        final front = Stack(
          clipBehavior: Clip.none,
          children: [
            GameCard(
              color: widget.flyingCard.cardColor,
              elevation: 12,
              width: widget.deckCardWidth,
              height: widget.deckCardHeight,
            ),
            Positioned.fill(
              child: CardFace(
                card: widget.flyingCard.card,
                width: widget.deckCardWidth,
                height: widget.deckCardHeight,
                reveal: true,
              ),
            ),
          ],
        );
        return Transform.translate(
          offset: Offset(_animX.value, _animY.value),
          child: Transform.rotate(
            angle: _animRotation.value * math.pi / 180,
            child: Transform.scale(
              scale: _animScale.value,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY(angle),
                child: showFront ? front : back,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReturningCardView extends StatefulWidget {
  const _ReturningCardView({
    super.key,
    required this.returningCard,
    required this.deckCenterY,
    required this.handCenterY,
    required this.cardSpacing,
    required this.currentScroll,
    required this.scaleDown,
    required this.deckCardWidth,
    required this.deckCardHeight,
  });

  final ReturningCard returningCard;
  final double deckCenterY;
  final double handCenterY;
  final double cardSpacing;
  final double currentScroll;
  final double scaleDown;
  final double deckCardWidth;
  final double deckCardHeight;

  @override
  State<_ReturningCardView> createState() => _ReturningCardViewState();
}

class _ReturningCardViewState extends State<_ReturningCardView>
    with TickerProviderStateMixin {
  late final AnimationController _animY;
  late final AnimationController _animX;
  late final AnimationController _animRotation;
  late final AnimationController _animScale;
  late final AnimationController _opacity;

  @override
  void initState() {
    super.initState();
    final distance = widget.returningCard.handIndex - widget.currentScroll;
    final absDist = distance.abs();
    final startX = distance * widget.cardSpacing;
    final startRotation = distance * 5;
    final startScale = (1 - absDist * 0.1).clamp(0.6, 1.0) * widget.scaleDown;

    _animY = AnimationController.unbounded(vsync: this)
      ..value = widget.handCenterY;
    _animX = AnimationController.unbounded(vsync: this)..value = startX;
    _animRotation = AnimationController.unbounded(vsync: this)
      ..value = startRotation;
    _animScale = AnimationController.unbounded(vsync: this)..value = startScale;
    _opacity = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..value = 1;

    _run();
  }

  Future<void> _run() async {
    await Future.delayed(Duration(milliseconds: widget.returningCard.delayMs));
    unawaited(
      Future.wait([
        _animY.animateTo(
          widget.deckCenterY,
          duration: const Duration(milliseconds: 450),
          curve: _accelerateCurve,
        ),
        _animX.animateTo(
          0,
          duration: const Duration(milliseconds: 450),
          curve: _accelerateCurve,
        ),
        _animRotation.animateTo(
          0,
          duration: const Duration(milliseconds: 450),
          curve: _accelerateCurve,
        ),
        _animScale.animateTo(
          1,
          duration: const Duration(milliseconds: 450),
          curve: _accelerateCurve,
        ),
      ]),
    );
    // 飞行最后阶段淡出，落地时已融入牌堆，避免阴影堆叠
    await Future.delayed(const Duration(milliseconds: 350));
    await _opacity.animateTo(
      0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _animY.dispose();
    _animX.dispose();
    _animRotation.dispose();
    _animScale.dispose();
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _animY,
        _animX,
        _animRotation,
        _animScale,
        _opacity,
      ]),
      builder: (context, _) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(_animX.value, _animY.value),
            child: Transform.rotate(
              angle: _animRotation.value * math.pi / 180,
              child: Transform.scale(
                scale: _animScale.value,
                child: GameCard(
                  color: widget.returningCard.cardColor,
                  elevation: 3,
                  width: widget.deckCardWidth,
                  height: widget.deckCardHeight,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlayedCardAnimation extends StatefulWidget {
  const _PlayedCardAnimation({
    required this.card,
    required this.color,
    required this.startPos,
    required this.onDone,
  });

  final CardData card;
  final Color color;
  final Offset startPos;
  final VoidCallback onDone;

  @override
  State<_PlayedCardAnimation> createState() => _PlayedCardAnimationState();
}

class _PlayedCardAnimationState extends State<_PlayedCardAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _animY = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _animRotation = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _animScale = AnimationController.unbounded(
    vsync: this,
  )..value = 1;
  late final AnimationController _animOpacity = AnimationController(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    // 向上飞出屏幕：上移 + 旋转 + 放大 + 淡出
    unawaited(
      Future.wait([
        _animY.animateTo(
          -widget.startPos.dy - 300,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeIn,
        ),
        _animRotation.animateTo(
          -12,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeIn,
        ),
        _animScale.animateTo(
          1.15,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeIn,
        ),
      ]),
    );
    await Future.delayed(const Duration(milliseconds: 150));
    await _animOpacity.animateTo(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeIn,
    );
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _animY.dispose();
    _animRotation.dispose();
    _animScale.dispose();
    _animOpacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _animY,
        _animRotation,
        _animScale,
        _animOpacity,
      ]),
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: widget.startPos.dx - _handCardWidth / 2,
              top: widget.startPos.dy - _handCardHeight / 2 + _animY.value,
              width: _handCardWidth,
              height: _handCardHeight,
              child: Transform.rotate(
                angle: _animRotation.value * math.pi / 180,
                child: Transform.scale(
                  scale: _animScale.value,
                  child: Opacity(
                    opacity: (1 - _animOpacity.value).clamp(0.0, 1.0),
                    child: Stack(
                      children: [
                        GameCard(
                          color: widget.color,
                          elevation: 8,
                          width: _handCardWidth,
                          height: _handCardHeight,
                        ),
                        Positioned.fill(
                          child: CardFace(
                            card: widget.card,
                            width: _handCardWidth,
                            height: _handCardHeight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
