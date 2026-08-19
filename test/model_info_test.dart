// REQ-003：统一模型格式与各服务商响应解析
import 'package:flutter_test/flutter_test.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/services/providers/base_provider.dart';

void main() {
  group('统一模型格式 ModelInfo', () {
    test('unified 工厂自动生成 provider:name 统一 ID', () {
      final m = ModelInfo.unified(
        provider: 'openai',
        name: 'gpt-4o-mini',
        lastSynced: 1000,
      );
      expect(m.id, 'openai:gpt-4o-mini');
      expect(ModelInfo.unifiedId('anthropic', 'claude-3-opus'),
          'anthropic:claude-3-opus');
      // displayName 缺省时回落到 name
      expect(m.displayName, 'gpt-4o-mini');
      expect(m.status, 'active');
      expect(m.isEnabled, isTrue);
    });

    test('不同服务商同名模型不会互相覆盖', () {
      final a = ModelInfo.unified(
          provider: 'openai', name: 'gpt-4o', lastSynced: 1);
      final b = ModelInfo.unified(
          provider: 'azure', name: 'gpt-4o', lastSynced: 1);
      expect(a.id == b.id, isFalse);
    });

    test('toJson / fromJson 往返保持字段一致', () {
      final m = ModelInfo.unified(
        provider: 'google',
        name: 'gemini-1.5-pro',
        displayName: 'Gemini 1.5 Pro',
        ownedBy: 'google',
        capabilities: const ['chat', 'vision'],
        status: 'deprecated',
        isEnabled: false,
        createdAt: 1700000000000,
        lastSynced: 1700000001000,
        rawData: const {'name': 'models/gemini-1.5-pro'},
      );
      final back = ModelInfo.fromJson(m.toJson());
      expect(back.id, m.id);
      expect(back.provider, 'google');
      expect(back.name, 'gemini-1.5-pro');
      expect(back.displayName, 'Gemini 1.5 Pro');
      expect(back.ownedBy, 'google');
      expect(back.capabilities, ['chat', 'vision']);
      expect(back.status, 'deprecated');
      expect(back.isEnabled, isFalse);
      expect(back.createdAt, 1700000000000);
      expect(back.lastSynced, 1700000001000);
      expect(back.rawData['name'], 'models/gemini-1.5-pro');
    });

    test('toOpenAIFormat 返回上游可识别的原始模型名（而非 provider:name）', () {
      final m = ModelInfo.unified(
        provider: 'anthropic',
        name: 'claude-3-5-sonnet-20241022',
        capabilities: const ['chat'],
        createdAt: 1700000000000,
        lastSynced: 1700000001000,
      );
      final json = m.toOpenAIFormat();
      // 关键：id 必须是上游能直接使用的模型名，避免 AI 应用把 provider: 前缀透传上游
      expect(json['id'], 'claude-3-5-sonnet-20241022');
      expect(json['object'], 'model');
      expect(json['created'], 1700000000); // 毫秒 → 秒
      expect(json['owned_by'], 'anthropic'); // ownedBy 缺省回落 provider
      // 中转站扩展字段
      expect(json['provider'], 'anthropic');
      expect(json['capabilities'], ['chat']);
      expect(json['status'], 'active');
      expect(json['enabled'], isTrue);
    });

    test('toAnthropicFormat 输出 ISO 时间与原始模型名', () {
      final m = ModelInfo.unified(
        provider: 'anthropic',
        name: 'claude-3-haiku',
        lastSynced: 1700000000000,
      );
      final json = m.toAnthropicFormat();
      expect(json['type'], 'model');
      expect(json['id'], 'claude-3-haiku');
      expect(json['created_at'], contains('T'));
    });

    test('copyWith 仅覆盖指定字段', () {
      final m = ModelInfo.unified(
          provider: 'openai', name: 'gpt-4o', lastSynced: 5);
      final off = m.copyWith(isEnabled: false, status: 'deprecated');
      expect(off.id, m.id);
      expect(off.name, m.name);
      expect(off.isEnabled, isFalse);
      expect(off.status, 'deprecated');
      expect(m.isEnabled, isTrue); // 原对象不变（不可变模型）
    });
  });

  group('能力推断 inferCapabilities', () {
    test('对话类模型识别 chat / function_calling', () {
      for (final id in [
        'gpt-4o-mini',
        'gpt-3.5-turbo',
        'gpt-35-turbo', // Azure 命名
        'claude-3-5-sonnet',
        'gemini-1.5-flash',
        'deepseek-chat',
        'qwen-max',
        'llama-3.1-70b',
      ]) {
        final caps = ModelInfo.inferCapabilities(id);
        expect(caps, contains('chat'), reason: id);
        expect(caps, contains('function_calling'), reason: id);
      }
    });

    test('专用模型识别对应能力', () {
      expect(ModelInfo.inferCapabilities('text-embedding-3-small'),
          contains('embedding'));
      expect(ModelInfo.inferCapabilities('dall-e-3'),
          contains('image_generation'));
      expect(ModelInfo.inferCapabilities('gpt-4-vision-preview'),
          contains('vision'));
      expect(ModelInfo.inferCapabilities('whisper-1'),
          contains('audio_transcription'));
      expect(ModelInfo.inferCapabilities('tts-1-hd'),
          contains('text_to_speech'));
      expect(ModelInfo.inferCapabilities('text-moderation-latest'),
          contains('moderation'));
    });

    test('未知模型回落到 completion 且不为空', () {
      final caps = ModelInfo.inferCapabilities('some-unknown-model-v9');
      expect(caps, ['completion']);
    });
  });

  group('服务商响应解析', () {
    test('OpenAI 兼容格式 {data:[...]}', () {
      final models = BaseHttpProvider.parseModelsOpenAI({
        'object': 'list',
        'data': [
          {'id': 'gpt-4o', 'owned_by': 'openai', 'created': 1700000000},
          {'id': 'text-embedding-3-small', 'owned_by': 'openai-internal'},
        ],
      }, 'openai', 999);
      expect(models.length, 2);
      expect(models.first.id, 'openai:gpt-4o');
      expect(models.first.ownedBy, 'openai');
      expect(models.first.createdAt, 1700000000000); // 秒 → 毫秒
      expect(models.first.lastSynced, 999);
      expect(models.last.capabilities, contains('embedding'));
      expect(models.last.createdAt, isNull);
      expect(models.first.rawData['id'], 'gpt-4o');
    });

    test('Anthropic 格式 {models:[...]} 带 display_name', () {
      final models = BaseHttpProvider.parseModelsAnthropic({
        'models': [
          {
            'id': 'claude-3-5-sonnet-20241022',
            'display_name': 'Claude 3.5 Sonnet',
            'created_at': '2024-10-22T00:00:00Z',
          },
        ],
      }, 'anthropic', 111);
      expect(models.length, 1);
      expect(models.first.id, 'anthropic:claude-3-5-sonnet-20241022');
      expect(models.first.displayName, 'Claude 3.5 Sonnet');
      expect(models.first.createdAt, isNotNull);
      expect(models.first.capabilities, contains('chat'));
    });

    test('Google 格式剥离 models/ 前缀', () {
      final models = BaseHttpProvider.parseModelsGoogle({
        'models': [
          {
            'name': 'models/gemini-1.5-pro',
            'displayName': 'Gemini 1.5 Pro',
          },
        ],
      }, 'google', 222);
      expect(models.first.name, 'gemini-1.5-pro');
      expect(models.first.id, 'google:gemini-1.5-pro');
      expect(models.first.displayName, 'Gemini 1.5 Pro');
    });

    test('响应缺少列表字段时安全返回空列表', () {
      expect(BaseHttpProvider.parseModelsOpenAI({}, 'openai', 1), isEmpty);
      expect(
          BaseHttpProvider.parseModelsAnthropic(
              {'models': 'oops'}, 'anthropic', 1),
          isEmpty);
      expect(BaseHttpProvider.parseModelsGoogle({}, 'google', 1), isEmpty);
    });

    test('parseCreated 兼容秒级整数与 ISO 字符串', () {
      expect(BaseHttpProvider.parseCreated(1700000000), 1700000000000);
      expect(BaseHttpProvider.parseCreated('2024-01-01T00:00:00Z'), isNotNull);
      expect(BaseHttpProvider.parseCreated('not-a-date'), isNull);
      expect(BaseHttpProvider.parseCreated(null), isNull);
    });
  });
}
