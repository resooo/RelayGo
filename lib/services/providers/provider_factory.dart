import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/services/providers/base_provider.dart';
import 'package:relaygo/services/providers/openai_provider.dart';
import 'package:relaygo/services/providers/anthropic_provider.dart';
import 'package:relaygo/services/providers/google_provider.dart';
import 'package:relaygo/services/providers/azure_provider.dart';
import 'package:relaygo/services/providers/custom_provider.dart';

/// 提供商工厂：根据类型返回对应适配器实例
///
/// 每次返回新实例（适配器可能按 key 缓存 metadata 定制项），
/// 上游连接池由 [BaseHttpProvider.client] 全局共享，因此不影响性能。
BaseProvider providerFor(ProviderType type) {
  switch (type) {
    case ProviderType.openai:
      return OpenAIProvider();
    case ProviderType.anthropic:
      return AnthropicProvider();
    case ProviderType.google:
      return GoogleProvider();
    case ProviderType.azure:
      return AzureProvider();
    case ProviderType.custom:
      return CustomProvider();
  }
}

/// 按提供商名（'openai' / 'anthropic' / ...）获取适配器
BaseProvider providerForName(String name) =>
    providerFor(ProviderTypeX.fromString(name));
