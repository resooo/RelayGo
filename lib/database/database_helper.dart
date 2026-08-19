import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/config/constants.dart';
import 'package:relaygo/database/migrations.dart';

/// Hive 本地存储封装
///
/// 采用 Map/原生类型直接存入 Box，避免 codegen 依赖，跨平台（iOS/Android/Linux/Web）一致。
class DatabaseHelper {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    await Hive.openBox(Constants.vaultBox);
    await Hive.openBox(Constants.keysBox);
    await Hive.openBox(Constants.logsBox);
    await Hive.openBox(Constants.settingsBox);
    await Hive.openBox(Constants.rulesBox);
    await Hive.openBox(Constants.alertsBox);
    await Hive.openBox(Constants.modelsBox);
    await Hive.openBox(Constants.syncHistoryBox);
    await Hive.openBox(Constants.providersBox);
    await Hive.openBox(Constants.freeApiBox);
    await Migrations.run();
    _initialized = true;
  }

  static bool get initialized => _initialized;

  static Box get vault => Hive.box(Constants.vaultBox);
  static Box get keys => Hive.box(Constants.keysBox);
  static Box get logs => Hive.box(Constants.logsBox);
  static Box get settings => Hive.box(Constants.settingsBox);
  static Box get rules => Hive.box(Constants.rulesBox);
  static Box get alerts => Hive.box(Constants.alertsBox);
  static Box get models => Hive.box(Constants.modelsBox);
  static Box get syncHistory => Hive.box(Constants.syncHistoryBox);
  static Box get providers => Hive.box(Constants.providersBox);
  static Box get freeApi => Hive.box(Constants.freeApiBox);

  /// 清空业务数据（保留 vault 主密钥，避免已存 key 无法解密）
  static Future<void> clearBusinessData() async {
    await keys.clear();
    await logs.clear();
    await rules.clear();
    await alerts.clear();
    await models.clear();
    await syncHistory.clear();
  }
}
