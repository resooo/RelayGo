// REQ-003：模型库仓储（Hive）增删改查、过滤、启用开关、下线标记
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/database/model_repository.dart';
import 'package:relaygo/models/model_info.dart';

ModelInfo _m(
  String provider,
  String name, {
  List<String> caps = const ['chat'],
  String status = 'active',
  bool enabled = true,
  int synced = 1000,
  String sourceKey = '',
}) =>
    ModelInfo.unified(
      provider: provider,
      name: name,
      capabilities: caps,
      status: status,
      isEnabled: enabled,
      lastSynced: synced,
      sourceKeyId: sourceKey,
    );

void main() {
  late ModelRepository repo;

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('model_repo_test');
    Hive.init(tmp.path);
    await Hive.openBox('models_repo_test');
    repo = ModelRepository(Hive.box('models_repo_test'));
  });

  setUp(() async => repo.clear());

  test('upsertAll 写入后可按统一 ID 读取', () async {
    await repo.upsertAll([_m('openai', 'gpt-4o'), _m('openai', 'gpt-4o-mini')]);
    expect(repo.getAll().length, 2);
    expect(repo.getById('openai:gpt-4o')!.name, 'gpt-4o');
    expect(repo.getById('openai:not-exist'), isNull);
  });

  test('重复 upsert 同一模型不会产生重复记录（按 ID 覆盖）', () async {
    await repo.upsertAll([_m('openai', 'gpt-4o', synced: 1000)]);
    await repo.upsertAll([_m('openai', 'gpt-4o', synced: 2000)]);
    expect(repo.getAll().length, 1);
    expect(repo.getById('openai:gpt-4o')!.lastSynced, 2000);
  });

  test('getAll 按 provider + name 稳定排序', () async {
    await repo.upsertAll([
      _m('openai', 'gpt-4o'),
      _m('anthropic', 'claude-3-opus'),
      _m('anthropic', 'claude-3-haiku'),
    ]);
    final ids = repo.getAll().map((m) => m.id).toList();
    expect(ids, [
      'anthropic:claude-3-haiku',
      'anthropic:claude-3-opus',
      'openai:gpt-4o',
    ]);
  });

  test('getByProvider / providerCounts / lastSyncAt', () async {
    await repo.upsertAll([
      _m('openai', 'gpt-4o', synced: 1000),
      _m('openai', 'gpt-4o-mini', synced: 3000),
      _m('google', 'gemini-1.5-pro', synced: 2000),
    ]);
    expect(repo.getByProvider('openai').length, 2);
    expect(repo.providerCounts(), {'google': 1, 'openai': 2});
    expect(repo.lastSyncAt('openai'), 3000);
    expect(repo.lastSyncAt('azure'), 0);
  });

  test('setEnabled 切换启用状态；getEnabled 只返回启用且 active', () async {
    await repo.upsertAll([
      _m('openai', 'gpt-4o'),
      _m('openai', 'gpt-3.5-turbo'),
      _m('openai', 'old-model', status: 'deprecated'),
    ]);
    await repo.setEnabled('openai:gpt-3.5-turbo', false);
    final enabled = repo.getEnabled().map((m) => m.name).toList();
    expect(enabled, ['gpt-4o']); // 停用的和已下线的都被排除
    // 再打开
    await repo.setEnabled('openai:gpt-3.5-turbo', true);
    expect(repo.getEnabled().length, 2);
    // 不存在的 ID 不抛异常
    await repo.setEnabled('openai:ghost', false);
  });

  test('sourceKeyId 随序列化持久化', () async {
    await repo.upsertAll([
      ModelInfo.unified(
        provider: 'openai',
        name: 'gpt-4o',
        lastSynced: 1000,
        sourceKeyId: 'key-123',
      ),
    ]);
    expect(repo.getById('openai:gpt-4o')!.sourceKeyId, 'key-123');
  });

  test('删除来源 key 仅清除其拉取的模型，不影响其他 key 的模型', () async {
    await repo.upsertAll([
      _m('openai', 'gpt-4o', sourceKey: 'key-A'),
      _m('openai', 'gpt-4o-mini', sourceKey: 'key-A'),
      _m('anthropic', 'claude-3-haiku', sourceKey: 'key-B'),
      _m('google', 'gemini-pro', sourceKey: ''), // 旧数据：无来源
    ]);
    final removed = await repo.removeBySourceKey('key-A');
    expect(removed, 2);
    expect(repo.getById('openai:gpt-4o'), isNull);
    expect(repo.getById('openai:gpt-4o-mini'), isNull);
    // 其他 key 与旧数据模型保留
    expect(repo.getById('anthropic:claude-3-haiku'), isNotNull);
    expect(repo.getById('google:gemini-pro'), isNotNull);
    // 空来源 id / 不存在 id 是幂等的安全操作
    await repo.removeBySourceKey('');
    await repo.removeBySourceKey('key-not-exist');
  });

  test('getFiltered 支持服务商 / 能力 / 状态 / 仅启用 组合过滤', () async {
    await repo.upsertAll([
      _m('openai', 'gpt-4o', caps: ['chat', 'vision']),
      _m('openai', 'text-embedding-3-small', caps: ['embedding']),
      _m('openai', 'legacy', caps: ['chat'], status: 'deprecated'),
      _m('google', 'gemini-1.5-pro', caps: ['chat'], enabled: false),
    ]);
    expect(repo.getFiltered(provider: 'openai').length, 3);
    expect(repo.getFiltered(capability: 'chat').length, 3);
    expect(repo.getFiltered(capability: 'embedding').single.name,
        'text-embedding-3-small');
    expect(repo.getFiltered(status: 'deprecated').single.name, 'legacy');
    expect(repo.getFiltered(enabledOnly: true).length, 3);
    expect(
        repo
            .getFiltered(provider: 'openai', capability: 'chat', status: 'active')
            .single
            .name,
        'gpt-4o');
    // 空字符串视为不过滤
    expect(repo.getFiltered(provider: '', capability: '').length, 4);
  });

  test('markRemoved 将本次未返回的模型标记下线并停用，返回数量', () async {
    await repo.upsertAll([
      _m('openai', 'gpt-4o'),
      _m('openai', 'gpt-4-old'),
      _m('google', 'gemini-1.5-pro'),
    ]);
    final removed = await repo.markRemoved({'openai:gpt-4o'}, 'openai');
    expect(removed, 1);
    final old = repo.getById('openai:gpt-4-old')!;
    expect(old.status, 'deprecated');
    expect(old.isEnabled, isFalse);
    // 不影响其他服务商
    expect(repo.getById('google:gemini-1.5-pro')!.status, 'active');
    // 全部保留时返回 0
    expect(await repo.markRemoved({'google:gemini-1.5-pro'}, 'google'), 0);
  });

  test('markRemoved 尊重用户手动启用的已下线模型（仅标记不强制停用）',
      () async {
    // 用户此前手动启用一个已下线的模型（status=deprecated 但 isEnabled=true）
    await repo.upsertAll([
      _m('openai', 'gpt-4o'),
      _m('openai', 'legacy', status: 'deprecated', enabled: true),
    ]);
    // 本次同步 legacy 仍未返回
    await repo.markRemoved({'openai:gpt-4o'}, 'openai');
    final legacy = repo.getById('openai:legacy')!;
    expect(legacy.status, 'deprecated');
    expect(legacy.isEnabled, isTrue); // 用户的启用偏好被保留
    // 对照：未启用的活跃模型被下线时仍应停用
    await repo.upsertAll([
      _m('openai', 'gpt-4o'),
      _m('openai', 'gone'),
    ]);
    await repo.markRemoved({'openai:gpt-4o'}, 'openai');
    expect(repo.getById('openai:gone')!.isEnabled, isFalse);
  });

  test('clear 清空全部模型', () async {
    await repo.upsertAll([_m('openai', 'gpt-4o')]);
    await repo.clear();
    expect(repo.getAll(), isEmpty);
  });

  test('性能验收：500 个模型的本地查询 < 100ms', () async {
    await repo.upsertAll([
      for (var i = 0; i < 250; i++) _m('openai', 'model-openai-$i'),
      for (var i = 0; i < 250; i++)
        _m('anthropic', 'model-anthropic-$i', caps: ['chat', 'vision']),
    ]);
    expect(repo.getAll().length, 500);

    final sw = Stopwatch()..start();
    final filtered = repo.getFiltered(
        provider: 'anthropic', capability: 'vision', enabledOnly: true);
    sw.stop();
    expect(filtered.length, 250);
    expect(sw.elapsedMilliseconds, lessThan(100),
        reason: '本地模型查询应 < 100ms，实际 ${sw.elapsedMilliseconds}ms');
  });

  test('deprecatedCounts 统计已下线模型数量', () async {
    await repo.upsertAll([
      _m('openai', 'gpt-4o'),
      _m('openai', 'old-o1', status: 'deprecated'),
      _m('openai', 'old-o2', status: 'deprecated'),
      _m('google', 'gemini-old', status: 'deprecated'),
    ]);
    final counts = repo.deprecatedCounts();
    expect(counts['openai'], 2);
    expect(counts['google'], 1);
  });

  test('removeDeprecated 删除指定服务商的已下线模型', () async {
    await repo.upsertAll([
      _m('openai', 'gpt-4o'),
      _m('openai', 'old-model', status: 'deprecated'),
      _m('google', 'gemini-old', status: 'deprecated'),
    ]);
    final removed = await repo.removeDeprecated(provider: 'openai');
    expect(removed, 1);
    expect(repo.getById('openai:old-model'), isNull);
    expect(repo.getById('openai:gpt-4o'), isNotNull);
    // google 的已下线模型不受影响
    expect(repo.getById('google:gemini-old'), isNotNull);
  });

  test('removeDeprecated 不指定服务商时删除所有已下线模型', () async {
    await repo.upsertAll([
      _m('openai', 'gpt-4o'),
      _m('openai', 'old-o1', status: 'deprecated'),
      _m('google', 'gemini-old', status: 'deprecated'),
    ]);
    final removed = await repo.removeDeprecated();
    expect(removed, 2);
    expect(repo.getAll().length, 1);
    expect(repo.getById('openai:gpt-4o'), isNotNull);
  });

  test('removeDeprecated 无已下线模型时返回 0', () async {
    await repo.upsertAll([_m('openai', 'gpt-4o')]);
    expect(await repo.removeDeprecated(), 0);
  });
}
