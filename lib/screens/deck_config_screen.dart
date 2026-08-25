// M3E Migration 记录：
// - 已迁移：按钮（M3ETextButton/M3EFilledButton.*）、卡组下拉（M3EDropdownMenu）、
//   卡牌徽标（M3ECard）。
// - 规则 3 未覆盖组件（m3e_core 1.1.0 未提供 → 暂用官方 material 最新组件，
//   待官方 M3E 包覆盖后二次迁移）：AlertDialog、TextField、SnackBar、IconButton。
// - 规则 4 不确定组件：牌库/牌组卡牌条目列表为高度定制的飞行/预览动画 UI，
//   M3ECardList 的语义（整列卡片）不匹配，保持自定义实现（见 _LibraryCardItem）。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3e_core/m3e_core.dart';

import '../data/card_pool.dart';
import '../data/deck_pool.dart';
import '../data/local_store.dart';
import '../models/card.dart';
import '../utils/card_import.dart';
import '../utils/deck_share.dart';
import '../utils/log_collector.dart';
import '../widgets/card_face.dart';
import '../widgets/game_card.dart';

class DeckConfigScreen extends StatefulWidget {
  const DeckConfigScreen({super.key});

  @override
  State<DeckConfigScreen> createState() => DeckConfigScreenState();
}

class DeckConfigScreenState extends State<DeckConfigScreen>
    with AutomaticKeepAliveClientMixin {
  static const _maxDeckSize = 20;

  final _selectedDeck = <CardData>[];
  String _searchQuery = '';
  final _deckListKey = GlobalKey();
  final _deckContentKey = GlobalKey();
  final _inFlightCardIds = <String>{};
  final _collapsingCardIds = <String>{};
  final _flightEntries = <OverlayEntry>{};
  bool _disposed = false;

  // 卡组配置操作的撤销 / 重做历史（记录卡牌 id 列表）
  final _undoStack = <List<String>>[];
  final _redoStack = <List<String>>[];

  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  @override
  bool get wantKeepAlive => true;

  /// 在修改当前选配前记录历史
  void _pushHistory() {
    _undoStack.add(_selectedDeck.map((c) => c.id).toList());
    if (_undoStack.length > 100) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _applyIds(List<String> ids) {
    final lib = {for (final c in CardPool.instance.cards) c.id: c};
    setState(() {
      _selectedDeck
        ..clear()
        ..addAll(ids.map((id) => lib[id]).whereType<CardData>());
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_selectedDeck.map((c) => c.id).toList());
    _applyIds(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_selectedDeck.map((c) => c.id).toList());
    _applyIds(_redoStack.removeLast());
  }

  @override
  void initState() {
    super.initState();
    // 载入已保存的牌组
    _selectedDeck.addAll(DeckPool.instance.cards);
  }

  /// 当前选配是否与已保存牌组不同（与活动卡组槽对比）
  bool get hasUnsavedChanges {
    final decks = DeckPool.instance.savedDecks;
    final idx = DeckPool.instance.activeIndex;
    final savedIds = idx >= 0 && idx < decks.length
        ? decks[idx].cardIds
        : const <String>[];
    if (_selectedDeck.length != savedIds.length) return true;
    for (var i = 0; i < _selectedDeck.length; i++) {
      if (_selectedDeck[i].id != savedIds[i]) return true;
    }
    return false;
  }

  /// 牌库 id -> 卡牌 映射（用于按 id 还原卡组）
  Map<String, CardData> get _libraryMap => {
    for (final c in CardPool.instance.cards) c.id: c,
  };

  /// 合规的牌组数量区间
  static const minDeckSize = 15;

  /// 当前牌组数量是否合规（15~20 张）
  bool get isValidDeckSize =>
      _selectedDeck.length >= minDeckSize &&
      _selectedDeck.length <= _maxDeckSize;

  /// 提示牌组数量不合规
  Future<void> showInvalidDeckSizeDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('牌组数量不合规'),
        content: Text(
          '牌组数量必须为 $minDeckSize~$_maxDeckSize 张，当前为 ${_selectedDeck.length} 张。',
        ),
        actions: [
          M3ETextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 保存当前选配到活动卡组槽
  Future<void> saveChanges() async {
    await DeckPool.instance.saveActiveDeck(
      DeckPool.instance.activeDeckName,
      _selectedDeck,
    );
    LogCollector.instance.log(
      '保存卡组「${DeckPool.instance.activeDeckName}」'
      ' ${_selectedDeck.length} 张',
    );
  }

  /// 放弃未保存更改，回退到已保存的牌组
  void revertChanges() {
    _pushHistory();
    setState(() {
      _selectedDeck
        ..clear()
        ..addAll(DeckPool.instance.cards);
    });
  }

  /// 切换到指定卡组槽（有未保存修改时先询问）
  Future<void> _switchToSlot(int index) async {
    if (index == DeckPool.instance.activeIndex) return;
    if (hasUnsavedChanges) {
      final action = await _promptUnsaved();
      if (action == null || action == 'cancel' || !mounted) return;
      if (action == 'save') {
        if (!isValidDeckSize) {
          await showInvalidDeckSizeDialog(context);
          return;
        }
        await saveChanges();
      }
    }
    if (!mounted) return;
    _pushHistory();
    await DeckPool.instance.switchTo(index, _libraryMap);
    setState(() {
      _selectedDeck
        ..clear()
        ..addAll(DeckPool.instance.cards);
    });
  }

  Future<String?> _promptUnsaved() {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('未保存的更改'),
        content: const Text('当前卡组有未保存的修改，是否保存？'),
        actions: [
          M3ETextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('取消'),
          ),
          M3ETextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('放弃'),
          ),
          M3EFilledButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> addDeck() async {
    final name = await _promptDeckName('新建卡组', '');
    if (name == null || !mounted) return;
    await DeckPool.instance.addDeck(name);
    setState(() {
      _selectedDeck.clear();
      _searchQuery = '';
    });
  }

  Future<void> renameActiveDeck() async {
    final name = await _promptDeckName(
      '重命名卡组',
      DeckPool.instance.activeDeckName,
    );
    if (name == null || !mounted) return;
    await DeckPool.instance.renameDeck(DeckPool.instance.activeIndex, name);
  }

  Future<void> deleteActiveDeck() async {
    final index = DeckPool.instance.activeIndex;
    final decks = DeckPool.instance.savedDecks;
    if (index < 0 || index >= decks.length) return;
    final name = decks[index].name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除卡组'),
        content: Text('确定要删除卡组「$name」吗？此操作不可撤销。'),
        actions: [
          M3ETextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          M3EFilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await DeckPool.instance.deleteDeck(index, _libraryMap);
    setState(() {
      _selectedDeck
        ..clear()
        ..addAll(DeckPool.instance.cards);
    });
  }

  Future<String?> _promptDeckName(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '卡组名称'),
        ),
        actions: [
          M3ETextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          M3EFilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 导出当前牌组为二维码，并默认把排列好的卡组名称复制到剪贴板
  Future<void> exportDeck() async {
    LogCollector.instance.log('导出卡组（${_selectedDeck.length} 张）');
    await Clipboard.setData(ClipboardData(text: deckNamesText(_selectedDeck)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('卡组名称已复制到剪贴板')),
    );
    await showDeckQrDialog(context, _selectedDeck);
  }

  /// 从相册导入牌组（静默导入：直接填充当前选配，缺失卡牌自动并入牌库）
  Future<void> importDeck() async {
    try {
      final result = await pickDeckQrImage();
      if (!mounted || result.cancelled) return;
      final deck = result.deck;
      if (deck == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未能识别图片中的二维码')));
        return;
      }
      if (deck.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('二维码中没有有效牌组')));
        return;
      }
      // 导入会清空当前卡组，需确认（当前卡组为空时无需确认）
      if (_selectedDeck.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('导入牌组'),
            content: const Text('导入新牌组将清空当前卡组，是否继续？'),
            actions: [
              M3ETextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              M3EFilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('继续'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      final squirrelId = CardPool.instance.squirrelCard?.id;
      final imported = deck
          .where((c) => c.id != squirrelId)
          .take(_maxDeckSize)
          .toList();
      // 牌库中缺失的卡牌静默并入牌库，保证导入的牌组可直接使用
      final knownIds = {for (final c in CardPool.instance.cards) c.id};
      final missing = imported.where((c) => !knownIds.contains(c.id)).toList();
      if (missing.isNotEmpty) {
        CardPool.instance.setCards([...CardPool.instance.cards, ...missing]);
        await LocalStore.instance.saveLibrary(CardPool.instance.cards);
      }
      if (!mounted) return;
      LogCollector.instance.log('二维码导入卡组 ${imported.length} 张');
      _pushHistory();
      setState(() {
        _selectedDeck
          ..clear()
          ..addAll(imported);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入牌组（${imported.length} 张）')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  /// 牌组滚动视口（含全局位置）
  Rect? _deckViewport() {
    final ctx = _deckListKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 牌组当前滚动偏移
  double _deckScrollOffset() {
    final ctx = _deckContentKey.currentContext;
    if (ctx == null) return 0;
    return Scrollable.maybeOf(ctx)?.position.pixels ?? 0;
  }

  void _addCardWithFlight(
    BuildContext context,
    CardData card,
    Offset sourcePos,
  ) {
    if (_selectedDeck.length >= _maxDeckSize || _selectedDeck.contains(card)) {
      return;
    }
    _pushHistory();
    // 精确计算新卡在牌组列表中的落点（点击时树已稳定）
    var dest = sourcePos;
    final viewport = _deckViewport();
    if (viewport != null) {
      final index = _selectedDeck.length;
      final itemCenterY =
          viewport.top + index * 62.0 - _deckScrollOffset() + 29;
      final destY = itemCenterY.clamp(viewport.top + 29, viewport.bottom - 29);
      dest = Offset(viewport.left + 28, destY);
    }
    setState(() {
      _selectedDeck.add(card);
      _inFlightCardIds.add(card.id);
      _collapsingCardIds.add(card.id);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startFlight(context, card, sourcePos, dest);
    });
  }

  void _startFlight(
    BuildContext context,
    CardData card,
    Offset from,
    Offset to,
  ) {
    late final OverlayEntry entry;
    var removed = false;
    entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: _FlyingMiniCard(
          from: from,
          to: to,
          onDone: () {
            if (removed || _disposed) return;
            removed = true;
            _flightEntries.remove(entry);
            entry.remove();
            _finishFlight(card);
          },
        ),
      ),
    );
    _flightEntries.add(entry);
    Overlay.of(context).insert(entry);
  }

  void _finishFlight(CardData card) {
    if (!mounted) return;
    setState(() {
      _inFlightCardIds.remove(card.id);
      _collapsingCardIds.remove(card.id);
    });
    // 落地后把新卡滚动进可视区（安全读取滚动状态）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed) {
        _revealDeckCard(card);
      }
    });
  }

  void _revealDeckCard(CardData card) {
    final ctx = _deckContentKey.currentContext;
    final scrollable = ctx == null ? null : Scrollable.maybeOf(ctx);
    if (scrollable == null) return;
    final position = scrollable.position;
    final index = _selectedDeck.indexOf(card);
    if (index < 0) return;
    final itemBottom = index * 62.0 + 58.0;
    if (itemBottom > position.pixels + position.viewportDimension) {
      position.animateTo(
        itemBottom - position.viewportDimension,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _removeCardFromDeck(CardData card) {
    if (!_selectedDeck.contains(card)) return;
    _pushHistory();
    setState(() => _selectedDeck.remove(card));
  }

  OverlayEntry? _previewEntry;
  final GlobalKey<_CardPreviewOverlayState> _previewKey = GlobalKey();
  bool _previewEntryRemoved = true;

  @override
  void dispose() {
    _disposed = true;
    final preview = _previewEntry;
    if (preview != null) {
      _removePreviewEntry(preview);
    }
    for (final e in _flightEntries) {
      e.remove();
    }
    _flightEntries.clear();
    super.dispose();
  }

  /// 安全移除预览入口，防止重复 remove() 抛异常导致预览卡死。
  void _removePreviewEntry(OverlayEntry entry) {
    if (_previewEntry == entry) {
      _previewEntry = null;
    }
    if (!_previewEntryRemoved) {
      _previewEntryRemoved = true;
      entry.remove();
    }
  }

  void _showPreview(BuildContext context, CardData card, Offset sourcePos) {
    final old = _previewEntry;
    if (old != null) {
      _removePreviewEntry(old);
    }
    _previewEntryRemoved = false;
    final overlay = Overlay.of(context);
    final size = MediaQuery.of(context).size;
    final destCenter = Offset(size.width / 2, size.height / 2);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: _CardPreviewOverlay(
          key: _previewKey,
          card: card,
          sourcePos: sourcePos,
          destCenter: destCenter,
          onClosed: () => _removePreviewEntry(entry),
        ),
      ),
    );
    _previewEntry = entry;
    overlay.insert(entry);
  }

  void _hidePreview() {
    final state = _previewKey.currentState;
    if (state != null) {
      state.close();
    } else if (_previewEntry != null && !_previewEntryRemoved) {
      _removePreviewEntry(_previewEntry!);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: CardPool.instance,
      builder: (context, _) {
        final library = CardPool.instance.cards;
        return Column(
          children: [
            Expanded(
              // 牌库与卡组共用一个带渐变的容器，左浅右深区分两个区域
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    // 左右分明、正中间明显渐变分界
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        theme.colorScheme.surfaceContainerHighest,
                        theme.colorScheme.surfaceContainerHighest,
                        theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.55,
                        ),
                        theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.55,
                        ),
                      ],
                      stops: const [0.0, 0.48, 0.52, 1.0],
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildLibraryPanel(theme, library)),
                      Expanded(child: _buildDeckPanel(theme)),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  // 撤销 / 重做
                  IconButton(
                    tooltip: '撤销',
                    icon: const Icon(Icons.undo),
                    onPressed: _canUndo ? _undo : null,
                  ),
                  IconButton(
                    tooltip: '重做',
                    icon: const Icon(Icons.redo),
                    onPressed: _canRedo ? _redo : null,
                  ),
                  const SizedBox(width: 8),
                  // 确认牌组（自适应宽度，靠右）
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: M3EFilledButton.tonalIcon(
                        onPressed: () async {
                          if (!isValidDeckSize) {
                            showInvalidDeckSizeDialog(context);
                            return;
                          }
                          await saveChanges();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '已保存到「${DeckPool.instance.activeDeckName}」'
                                ' (${_selectedDeck.length}/$_maxDeckSize)',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.check),
                        label: Text(
                          '确认牌组' ' (${_selectedDeck.length}/$_maxDeckSize)',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLibraryPanel(ThemeData theme, List<CardData> library) {
    final hasCards = library.isNotEmpty;
    final query = _searchQuery.trim().toLowerCase();
    final squirrelId = CardPool.instance.squirrelCard?.id;
    final filtered = library.where((c) {
      if (c.id == squirrelId) return false; // 松鼠为特殊牌，隐藏不可装卸
      final inDeck = _selectedDeck.contains(c);
      final animatingOut = _collapsingCardIds.contains(c.id);
      if (inDeck && !animatingOut) return false;
      return query.isEmpty ||
          c.name.toLowerCase().contains(query) ||
          c.id.toLowerCase().contains(query);
    }).toList();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏（含牌库版本号）
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text('牌库', style: theme.textTheme.titleMedium),
                if (CardPool.instance.version != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'v${CardPool.instance.version}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!hasCards)
            // 首次使用：空牌库，显示导入按钮
            Expanded(
              child: Center(
                child: M3EFilledButton.icon(
                  onPressed: () => importCardLibrary(context),
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('导入卡牌JSON'),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: '搜索卡牌',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        query.isEmpty ? '没有可添加的卡牌' : '未找到匹配的卡牌',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final card = filtered[index];
                        final collapsing = _collapsingCardIds.contains(card.id);
                        // TODO: M3E Migration - 若 m3e_core 提供可定制
                        // item 的 M3ECardList（带自定义 onTap 落点），再评估替换；
                        // 当前条目含飞行动画/长按预览，与标准卡片列表语义不同。
                        return _LibraryCardItem(
                          key: ValueKey('lib-card-${card.id}'),
                          card: card,
                          collapsing: collapsing,
                          // 主色填充 + 主色文字，与浅色牌库背景明显区分
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          onTap: (pos) =>
                              _addCardWithFlight(context, card, pos),
                          onPreviewStart: (pos) =>
                              _showPreview(context, card, pos),
                          onPreviewEnd: _hidePreview,
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeckPanel(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildDeckHeader(theme),
          ),
          Expanded(
            child: SingleChildScrollView(
              key: _deckListKey,
              child: Column(
                key: _deckContentKey,
                children: [
                  if (_selectedDeck.isEmpty)
                    SizedBox(
                      height: 120,
                      child: Center(
                        child: Text(
                          '从牌库点击卡牌即可加入',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < _selectedDeck.length; i++) ...[
                      if (i > 0) const SizedBox(height: 4),
                      Builder(
                        builder: (context) {
                          final card = _selectedDeck[i];
                          final inFlight = _inFlightCardIds.contains(card.id);
                          return _DeckCardItem(
                            key: ValueKey('deck-card-${card.id}'),
                            card: card,
                            hidden: inFlight,
                            showRemoveIndicator: true,
                            onTap: (_) => _removeCardFromDeck(card),
                            onPreviewStart: (pos) =>
                                _showPreview(context, card, pos),
                            onPreviewEnd: _hidePreview,
                          );
                        },
                      ),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 右侧牌组框标题：卡组下拉选择
  Widget _buildDeckHeader(ThemeData theme) {
    final decks = DeckPool.instance.savedDecks;
    final active = DeckPool.instance.activeIndex;

    if (decks.isEmpty) {
      return Text('当前牌组', style: theme.textTheme.titleMedium);
    }

    final validActive = active >= 0 && active < decks.length;
    return Row(
      children: [
        Expanded(
          child: M3EDropdownMenu<int>(
            items: [
              for (var i = 0; i < decks.length; i++)
                M3EDropdownItem<int>(
                  label: decks[i].name,
                  value: i,
                  selected: i == active,
                ),
            ],
            singleSelect: true,
            enabled: validActive,
            containerRadius: 12,
            fieldStyle: M3EDropdownFieldStyle(
              hintText: '选择卡组',
              selectedTextStyle: theme.textTheme.titleMedium,
              hintStyle: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            onSelectionChanged: (sel) {
              if (sel.isNotEmpty) _switchToSlot(sel.first.value);
            },
          ),
        ),
      ],
    );
  }
}

class _DeckCardItem extends StatefulWidget {
  const _DeckCardItem({
    super.key,
    required this.card,
    required this.hidden,
    required this.onTap,
    this.onPreviewStart,
    this.onPreviewEnd,
    this.showRemoveIndicator = false,
  });

  final CardData card;
  final bool hidden;
  final ValueChanged<Offset> onTap;
  final ValueChanged<Offset>? onPreviewStart;
  final VoidCallback? onPreviewEnd;
  final bool showRemoveIndicator;

  @override
  State<_DeckCardItem> createState() => _DeckCardItemState();
}

class _DeckCardItemState extends State<_DeckCardItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  @override
  void initState() {
    super.initState();
    // 若组件在非隐藏状态下新建（如列表复用），直接保持可见
    if (!widget.hidden) {
      _expand.value = 1;
    }
  }

  @override
  void didUpdateWidget(_DeckCardItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hidden && oldWidget.hidden) {
      _expand.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _expand.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _expand,
      builder: (context, _) {
        final v = _expand.value;
        return RepaintBoundary(
          child: Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: _CardListItem(
              card: widget.card,
              isSelectable: true,
              showRemoveIndicator: widget.showRemoveIndicator,
              onTap: widget.onTap,
              onPreviewStart: widget.onPreviewStart,
              onPreviewEnd: widget.onPreviewEnd,
            ),
          ),
        );
      },
    );
  }
}

class _LibraryCardItem extends StatefulWidget {
  const _LibraryCardItem({
    super.key,
    required this.card,
    required this.collapsing,
    required this.onTap,
    this.onPreviewStart,
    this.onPreviewEnd,
    this.backgroundColor,
    this.foregroundColor,
  });

  final CardData card;
  final bool collapsing;
  final ValueChanged<Offset> onTap;
  final ValueChanged<Offset>? onPreviewStart;
  final VoidCallback? onPreviewEnd;

  /// 卡牌背景色（牌库卡片使用 primary，与浅色背景明显区分）
  final Color? backgroundColor;

  /// 卡牌文字前景色
  final Color? foregroundColor;

  @override
  State<_LibraryCardItem> createState() => _LibraryCardItemState();
}

class _LibraryCardItemState extends State<_LibraryCardItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _collapse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void initState() {
    super.initState();
    // 若组件在折叠状态下新建，直接开始折叠
    if (widget.collapsing) {
      _collapse.forward();
    }
  }

  @override
  void didUpdateWidget(_LibraryCardItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsing && !oldWidget.collapsing) {
      _collapse.forward();
    } else if (!widget.collapsing && oldWidget.collapsing) {
      _collapse.value = 0;
    }
  }

  @override
  void dispose() {
    _collapse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _collapse,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_collapse.value);
        final opacity = 1 - t;
        return RepaintBoundary(
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              alignment: Alignment.center,
              scaleY: 1 - t,
              child: _CardListItem(
                card: widget.card,
                isSelectable: !widget.collapsing,
                onTap: widget.onTap,
                backgroundColor: widget.backgroundColor,
                foregroundColor: widget.foregroundColor,
                onPreviewStart: widget.collapsing
                    ? null
                    : widget.onPreviewStart,
                onPreviewEnd: widget.collapsing ? null : widget.onPreviewEnd,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CardListItem extends StatelessWidget {
  const _CardListItem({
    required this.card,
    required this.isSelectable,
    required this.onTap,
    this.onPreviewStart,
    this.onPreviewEnd,
    this.showRemoveIndicator = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  final CardData card;
  final bool isSelectable;
  final ValueChanged<Offset> onTap;
  final ValueChanged<Offset>? onPreviewStart;
  final VoidCallback? onPreviewEnd;
  final bool showRemoveIndicator;

  /// 卡牌背景色（不传则用默认表面色）
  final Color? backgroundColor;

  /// 卡牌文字前景色（配合自定义背景色使用）
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = Container(
      width: 32,
      height: 45,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.2),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
    return GestureDetector(
      // 用 GestureDetector 接管长按，onLongPressEnd/Cancel 都能收回预览，
      // 避免依赖 InkWell 的 onLongPressUp 在个别情况下不触发导致预览卡住。
      onLongPressStart: onPreviewStart == null
          ? null
          : (_) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final rect = box.localToGlobal(Offset.zero) & box.size;
              // 迷你卡预览位于行内左侧 (padding 12 + 半宽 16)
              onPreviewStart!(Offset(rect.left + 28, rect.center.dy));
            },
      onLongPressEnd: (_) => onPreviewEnd?.call(),
      onLongPressCancel: onPreviewEnd,
      child: Material(
        color: backgroundColor ??
            (isSelectable
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  )),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: isSelectable
              ? () {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  final rect = box.localToGlobal(Offset.zero) & box.size;
                  onTap(Offset(rect.left + 28, rect.center.dy));
                }
              : null,
          borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 58,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  preview,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      card.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foregroundColor ??
                            (isSelectable
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.5)),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showRemoveIndicator)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '移除',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardPreviewOverlay extends StatefulWidget {
  const _CardPreviewOverlay({
    super.key,
    required this.card,
    required this.sourcePos,
    required this.destCenter,
    required this.onClosed,
  });

  final CardData card;
  final Offset sourcePos;
  final Offset destCenter;
  final VoidCallback onClosed;

  @override
  State<_CardPreviewOverlay> createState() => _CardPreviewOverlayState();
}

class _CardPreviewOverlayState extends State<_CardPreviewOverlay>
    with SingleTickerProviderStateMixin {
  static const _width = 240.0;
  static const _height = 336.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();
  bool _closing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    try {
      await _controller.reverse();
    } catch (_) {
      // 动画控制器可能已被释放（如入口被提前移除），忽略即可
    }
    if (mounted) widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        final scale = 0.133 + (1 - 0.133) * t;
        final center = Offset.lerp(widget.sourcePos, widget.destCenter, t)!;
        return SizedBox.expand(
          child: Transform.translate(
            offset: center - widget.destCenter,
            child: Transform.scale(
              scale: scale,
              child: Center(
                child: RepaintBoundary(
                  child: SizedBox(
                    width: _width,
                    height: _height,
                    child: Stack(
                      children: [
                        const GameCard(
                          color: Colors.white,
                          width: _width,
                          height: _height,
                          elevation: 8,
                        ),
                        Positioned.fill(
                          child: CardFace(
                            card: widget.card,
                            width: _width,
                            height: _height,
                            reveal: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FlyingMiniCard extends StatefulWidget {
  const _FlyingMiniCard({
    required this.from,
    required this.to,
    required this.onDone,
  });

  final Offset from;
  final Offset to;
  final VoidCallback onDone;

  @override
  State<_FlyingMiniCard> createState() => _FlyingMiniCardState();
}

class _FlyingMiniCardState extends State<_FlyingMiniCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final raw = _controller.value;
        final t = Curves.easeInOutCubic.transform(raw);
        final base = Offset.lerp(widget.from, widget.to, t)!;
        // 轻微上抛弧线与缩放，移动更丝滑
        final lift = -math.sin(math.pi * raw) * 24;
        final scale = 1 + 0.12 * math.sin(math.pi * raw);
        final pos = base + Offset(0, lift);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: pos.dx - 16,
              top: pos.dy - 22.5,
              width: 32,
              height: 45,
              child: Transform.scale(
                scale: scale,
                child: RepaintBoundary(
                  child: Container(
                    width: 32,
                    height: 45,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: cs.outlineVariant, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
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
