import 'dart:io';

/// 网络相关工具
class NetworkUtil {
  /// 获取本机局域网 IPv4 地址（供第三方应用连接中转站使用）
  ///
  /// 优先返回非回环、非虚拟网卡的 IPv4 地址；找不到时返回 null。
  static Future<String?> localIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        // 跳过常见虚拟网卡
        final name = iface.name.toLowerCase();
        if (name.contains('docker') ||
            name.contains('vmnet') ||
            name.contains('vbox') ||
            name.contains('tailscale') ||
            name.contains('utun') ||
            name.contains('tun')) {
          continue;
        }
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.isEmpty || ip == '0.0.0.0') continue;
          // 跳过链路本地地址
          if (ip.startsWith('169.254.')) continue;
          return ip;
        }
      }
    } catch (_) {
      // 平台不支持时静默返回 null
    }
    return null;
  }

  /// 展示用监听地址：
  /// - host 为 0.0.0.0 时返回本机局域网 IP（找不到则回退 0.0.0.0）
  /// - 否则原样返回 host
  static Future<String> displayHost(String host) async {
    if (host == '0.0.0.0' || host.isEmpty) {
      return await localIpv4() ?? '0.0.0.0';
    }
    return host;
  }
}
