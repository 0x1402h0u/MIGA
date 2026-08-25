import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:miga/data/local_store.dart';
import 'package:miga/data/player_profile.dart';
import 'package:miga/screens/profile_edit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('PlayerProfile 默认名字为 MIGA 玩家', () async {
    await PlayerProfile.instance.load();
    expect(PlayerProfile.instance.name, 'MIGA 玩家');
    expect(PlayerProfile.instance.avatarPath, isNull);
  });

  test('修改名字后持久化并可恢复', () async {
    await PlayerProfile.instance.load();
    await PlayerProfile.instance.setName(' 谜咖大佬 ');
    expect(PlayerProfile.instance.name, '谜咖大佬');
    // 模拟重启：重新加载
    final fresh = await LocalStore.instance.getPlayerName();
    expect(fresh, '谜咖大佬');
    await PlayerProfile.instance.setName('MIGA 玩家');
  });

  testWidgets('编辑页修改昵称并保存', (tester) async {
    await PlayerProfile.instance.load();
    await tester.pumpWidget(const MaterialApp(home: ProfileEditScreen()));
    expect(find.text('编辑个人信息'), findsOneWidget);

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    await tester.enterText(field, '新名字');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(PlayerProfile.instance.name, '新名字');
    expect(await LocalStore.instance.getPlayerName(), '新名字');
    // 保存后返回上一页
    expect(find.text('编辑个人信息'), findsNothing);

    await PlayerProfile.instance.setName('MIGA 玩家');
  });
}
