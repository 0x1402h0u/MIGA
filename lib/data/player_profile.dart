import 'package:flutter/foundation.dart';

import 'local_store.dart';

/// 默认玩家名，与导出二维码下方的署名保持一致。
const kDefaultPlayerName = 'MIGA 玩家';

/// 玩家资料（名字 + 头像路径）的全局状态，负责持久化与界面通知。
class PlayerProfile extends ChangeNotifier {
  PlayerProfile._();

  static final PlayerProfile instance = PlayerProfile._();

  String _name = kDefaultPlayerName;
  String? _avatarPath;

  String get name => _name;
  String? get avatarPath => _avatarPath;

  /// 启动时从本地恢复。
  Future<void> load() async {
    _name = await LocalStore.instance.getPlayerName() ?? kDefaultPlayerName;
    _avatarPath = await LocalStore.instance.getAvatarPath();
    notifyListeners();
  }

  Future<void> setName(String value) async {
    final name = value.trim();
    if (name.isEmpty || name == _name) return;
    _name = name;
    await LocalStore.instance.setPlayerName(name);
    notifyListeners();
  }

  Future<void> setAvatarPath(String? path) async {
    if (path == _avatarPath) return;
    _avatarPath = path;
    await LocalStore.instance.setAvatarPath(path);
    notifyListeners();
  }
}
