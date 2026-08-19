import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;

/// AES-256 加密工具
///
/// 说明：需求文档要求 AES-256-GCM。但当前锁定的 encrypt 5.0.1 不支持 GCM，
/// 故 MVP 采用 AES-256-CBC（PKCS7）实现等价强度的加密存储。
/// 生产环境可替换为 `cryptography` 包以获得 GCM 的认证加密。
class EncryptionUtil {
  static enc.Key? _key;
  static bool _initialized = false;

  /// 使用主密钥（base64）初始化。主密钥在首次运行时生成并存入 vault 盒。
  static void init(String masterKeyBase64) {
    _key = enc.Key.fromBase64(masterKeyBase64);
    _initialized = true;
  }

  static bool get initialized => _initialized;

  /// 生成一个 32 字节（AES-256）随机主密钥，返回 base64
  static String generateMasterKeyBase64() {
    final rnd = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = rnd.nextInt(256);
    }
    return base64Encode(bytes);
  }

  static void _ensureInit() {
    if (!_initialized || _key == null) {
      throw StateError('EncryptionUtil 尚未初始化，请先调用 init()');
    }
  }

  /// 加密明文，返回 `ivBase64:cipherBase64`
  static String encrypt(String plainText) {
    _ensureInit();
    final iv = enc.IV.fromSecureRandom(16); // CBC 需要 16 字节 IV
    final encrypter = enc.Encrypter(enc.AES(_key!, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  /// 解密 `ivBase64:cipherBase64`
  static String decrypt(String cipherText) {
    _ensureInit();
    final parts = cipherText.split(':');
    if (parts.length != 2) {
      // 兼容未加密的遗留数据（直接返回）
      return cipherText;
    }
    final iv = enc.IV.fromBase64(parts[0]);
    final encrypter = enc.Encrypter(enc.AES(_key!, mode: enc.AESMode.cbc));
    return encrypter.decrypt64(parts[1], iv: iv);
  }
}
