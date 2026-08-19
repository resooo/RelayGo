// P0/P1：能力分层归一化 + smart 健康分单元测试
import 'package:flutter_test/flutter_test.dart';
import 'package:relaygo/config/standard_models.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/services/load_balancer.dart';
import 'package:relaygo/services/model_normalizer.dart';

void main() {
  group('canonicalize 归一化', () {
    test('去版本/日期后缀', () {
      expect(ModelNormalizer.canonicalize('gpt-4o-2024-05-13'), 'gpt-4o');
      expect(ModelNormalizer.canonicalize('claude-3-5-sonnet-20241022'),
          'claude-3-5-sonnet');
      expect(ModelNormalizer.canonicalize('gpt-4-turbo-preview'), 'gpt-4-turbo');
      expect(ModelNormalizer.canonicalize('gemini-1.5-pro-latest'),
          'gemini-1.5-pro');
    });

    test('大小写 / 分隔符 / google 前缀归一', () {
      expect(ModelNormalizer.canonicalize('CLAUDE-3-5-Sonnet'),
          'claude-3-5-sonnet');
      expect(ModelNormalizer.canonicalize('models/gemini-1.5-pro'),
          'gemini-1.5-pro');
      expect(ModelNormalizer.canonicalize('text_embedding_3_small'),
          'text-embedding-3-small');
    });

    test('不误伤参数后缀（-8b / -405b / -16k / -128k）', () {
      expect(ModelNormalizer.canonicalize('llama-3.1-8b'), 'llama-3.1-8b');
      expect(ModelNormalizer.canonicalize('llama-3.1-405b-instruct'),
          'llama-3.1-405b-instruct');
      expect(ModelNormalizer.canonicalize('gpt-3.5-turbo-16k'),
          'gpt-3.5-turbo-16k');
    });
  });

  group('assignVirtualId 归类', () {
    test('已知名 canonical 归到档位', () {
      expect(ModelNormalizer.assignVirtualId('gpt-4o'), 'chat-premium');
      expect(ModelNormalizer.assignVirtualId('claude-3-5-sonnet'),
          'chat-advanced');
      expect(ModelNormalizer.assignVirtualId('gemini-2.5-pro'), 'chat-premium');
      expect(ModelNormalizer.assignVirtualId('text-embedding-3-small'),
          'embedding');
      expect(ModelNormalizer.assignVirtualId('gpt-4o-mini'), 'chat-basic');
    });

    test('未知模型返回 null（不强归）', () {
      expect(ModelNormalizer.assignVirtualId('custom-foo-bar-xyz'), isNull);
      expect(ModelNormalizer.assignVirtualId('provider-2024-private'),
          isNull);
    });
  });

  group('assignByCapabilities 能力兜底', () {
    test('按能力标签归到最贴近档位', () {
      expect(ModelNormalizer.assignByCapabilities(['embedding']), 'embedding');
      expect(ModelNormalizer.assignByCapabilities(['image_generation']),
          'image');
      expect(ModelNormalizer.assignByCapabilities(['text_to_speech']),
          'audio-tts');
      expect(ModelNormalizer.assignByCapabilities(['audio_transcription']),
          'audio-transcribe');
      expect(ModelNormalizer.assignByCapabilities(['rerank']), 'rerank');
      expect(ModelNormalizer.assignByCapabilities(['moderation']),
          'moderation');
      expect(ModelNormalizer.assignByCapabilities(['chat']), 'chat-basic');
      expect(ModelNormalizer.assignByCapabilities(['completion']),
          'chat-basic');
    });

    test('无能力标签返回 null', () {
      expect(ModelNormalizer.assignByCapabilities([]), isNull);
    });
  });

  group('assignByModelName 名称兜底分档', () {
    test('对话模型按名称关键词区分档位（不塌缩成 chat-basic）', () {
      expect(ModelNormalizer.assignByModelName('gpt-4o-2024-11-20'),
          'chat-premium');
      expect(ModelNormalizer.assignByModelName('claude-3-5-sonnet'),
          'chat-advanced');
      expect(ModelNormalizer.assignByModelName('gemini-2.5-flash'),
          'chat-advanced');
      expect(ModelNormalizer.assignByModelName('deepseek-chat'),
          'chat-basic');
      expect(ModelNormalizer.assignByModelName('llama-3.1-70b-instruct'),
          'chat-advanced');
      expect(ModelNormalizer.assignByModelName('qwen2.5-7b-instruct'),
          'chat-basic');
    });

    test('非对话能力按名称识别', () {
      expect(ModelNormalizer.assignByModelName('text-embedding-3-small'),
          'embedding');
      expect(ModelNormalizer.assignByModelName('dall-e-3'), 'image');
      expect(ModelNormalizer.assignByModelName('whisper-1'),
          'audio-transcribe');
      expect(ModelNormalizer.assignByModelName('tts-1-hd'), 'audio-tts');
      expect(ModelNormalizer.assignByModelName('text-moderation-latest'),
          'moderation');
    });

    test('完全未知名称返回 null', () {
      expect(ModelNormalizer.assignByModelName('proprietary-special-42'),
          isNull);
    });
  });

  group('resolveRequestModel 请求解析', () {
    test('虚拟模型 id / 品牌别名 / 带后缀型号均可解析', () {
      expect(ModelNormalizer.resolveRequestModel('chat-premium'),
          'chat-premium');
      expect(ModelNormalizer.resolveRequestModel('gpt4'), 'chat-premium');
      expect(ModelNormalizer.resolveRequestModel('gpt-4o'), 'chat-premium');
      expect(ModelNormalizer.resolveRequestModel('claude-3-5-sonnet'),
          'chat-advanced');
      expect(ModelNormalizer.resolveRequestModel('gpt-4o-2024-05-13'),
          'chat-premium');
    });

    test('空串 / 未知返回 null', () {
      expect(ModelNormalizer.resolveRequestModel(''), isNull);
      expect(ModelNormalizer.resolveRequestModel('totally-unknown-model'),
          isNull);
    });
  });

  group('ModelNormalizer.normalize 落库前归一', () {
    test('给已知模型赋 virtualId 与 contextWindow', () {
      final m = ModelNormalizer.normalize(ModelInfo.unified(
          provider: 'openai', name: 'gpt-4o-2024-05-13', lastSynced: 1));
      expect(m.virtualId, 'chat-premium');
      expect(m.contextWindow, isNotNull);
    });

    test('未知模型且无能力标签保持 virtualId null', () {
      final m = ModelNormalizer.normalize(ModelInfo.unified(
          provider: 'openai',
          name: 'proprietary-special-42',
          lastSynced: 1));
      expect(m.virtualId, isNull);
    });

    test('未知模型但有 chat 能力：能力兜底归 chat-basic', () {
      final m = ModelNormalizer.normalize(ModelInfo.unified(
          provider: 'custom',
          name: 'my-custom-chat-model',
          capabilities: const ['chat', 'function_calling'],
          lastSynced: 1));
      expect(m.virtualId, 'chat-basic');
    });
  });

  group('标准虚拟模型注册表', () {
    test('内置档位数适中（客户端拉取不会上百条）', () {
      expect(StandardModelRegistry.all.length, inInclusiveRange(6, 12));
      expect(StandardModelRegistry.aliases.length, greaterThan(40));
    });
  });

  group('P1：smart 健康分', () {
    ApiKey make(String id, {int priority = 100, int failure = 0}) => ApiKey(
        id: id,
        provider: 'openai',
        encryptedKey: 'x',
        name: id,
        createdAt: 1,
        priority: priority,
        failureCount: failure,
        status: KeyStatus.active);

    test('样本不足时回退到优先级排序（不回退为随机）', () {
      final lb = LoadBalancer();
      final low = make('low', priority: 90);
      final high = make('high', priority: 100);
      // 没有足够样本，仍应选优先级高者
      final picked = lb.pick([low, high], 'smart');
      expect(picked?.id, 'high');
    });

    test('样本充足时按成功率优先（高成功率胜过低优先级）', () {
      final lb = LoadBalancer();
      final stable = make('stable', priority: 80);
      final flaky = make('flaky', priority: 100);
      // stable：10 次全成功；flaky：10 次全失败
      for (var i = 0; i < 10; i++) {
        lb.recordSuccess(stable, latencyMs: 100);
        lb.recordFailure(flaky);
      }
      final picked = lb.pick([flaky, stable], 'smart');
      expect(picked?.id, 'stable');

      final ranked = lb.rank([flaky, stable], 'smart');
      expect(ranked.first.id, 'stable');
    });

    test('延迟 EMA 参与排序：同成功率下低延迟者优先', () {
      final lb = LoadBalancer();
      final fast = make('fast', priority: 90);
      final slow = make('slow', priority: 100);
      for (var i = 0; i < 10; i++) {
        lb.recordSuccess(fast, latencyMs: 100); // 快
        lb.recordSuccess(slow, latencyMs: 5000); // 慢
      }
      final picked = lb.pick([slow, fast], 'smart');
      expect(picked?.id, 'fast');
    });

    test('混战：稳定性权重 0.6，延迟 0.4 综合', () {
      final lb = LoadBalancer();
      final a = make('a');
      final b = make('b');
      for (var i = 0; i < 10; i++) {
        lb.recordSuccess(a, latencyMs: 50); // 全成功、极快
        // b：一半成功、非常慢
        if (i.isEven) {
          lb.recordSuccess(b, latencyMs: 10);
        } else {
          lb.recordFailure(b);
        }
      }
      final picked = lb.pick([b, a], 'smart');
      expect(picked?.id, 'a');
    });
  });
}