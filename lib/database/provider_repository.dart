import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/models/provider_definition.dart';

/// 提供商仓库
///
/// 内置预设 + 用户自定义提供商（持久化到 Hive）。
/// 用户自定义的提供商可以覆盖同 ID 的内置预设（例如修改 DeepSeek 的 API URL）。
class ProviderRepository {
  final Box _box;

  ProviderRepository(this._box);

  /// 全部提供商：内置预设 + 自定义
  List<ProviderDefinition> getAll() {
    final map = <String, ProviderDefinition>{};
    for (final p in BuiltInProviders.all) {
      map[p.id] = p;
    }
    for (final v in _box.values) {
      if (v is Map) {
        final p = ProviderDefinition.fromJson(Map<String, dynamic>.from(v));
        map[p.id] = p; // 自定义覆盖同 ID 内置
      }
    }
    final list = map.values.toList();
    // 内置优先，自定义按创建时间排序
    list.sort((a, b) {
      if (a.builtIn != b.builtIn) return a.builtIn ? -1 : 1;
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  /// 仅用户自定义的提供商
  List<ProviderDefinition> getCustom() {
    final list = _box.values
        .whereType<Map>()
        .map((m) => ProviderDefinition.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// 按 ID 查找（先查自定义，再查内置）
  ProviderDefinition? byId(String id) {
    final v = _box.get(id);
    if (v != null) {
      return ProviderDefinition.fromJson(Map<String, dynamic>.from(v as Map));
    }
    return BuiltInProviders.byId(id);
  }

  /// 是否存在自定义定义
  bool isCustom(String id) => _box.containsKey(id);

  Future<void> save(ProviderDefinition p) async {
    await _box.put(p.id, p.toJson());
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
  }

  /// 生成唯一 ID
  static String genId() {
    final t = DateTime.now().microsecondsSinceEpoch;
    final suffix = (DateTime.now().millisecondsSinceEpoch % 0xFFFF)
        .toRadixString(16)
        .padLeft(4, '0');
    return 'custom_${t.toRadixString(16)}_$suffix';
  }
}