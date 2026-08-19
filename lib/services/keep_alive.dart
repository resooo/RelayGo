import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 保活服务封装（Android 前台服务 + 电池优化白名单）
///
/// 通过 MethodChannel 与原生层通信：
///  - [start] / [stop]：启动 / 停止前台保活服务（常驻通知提升进程优先级）
///  - [isIgnoringBatteryOptimizations] / [requestIgnoreBatteryOptimizations]：
///    查询 / 请求加入电池优化白名单（避免 Doze 模式被杀）
///
/// 非 Android 平台（桌面 / iOS / Web）直接返回安全默认值，不抛异常。
///
/// 注意：命名为 [KeepAliveHelper] 以避开 Flutter 内置的 [KeepAlive] widget。
class KeepAliveHelper {
  static const MethodChannel _channel = MethodChannel('relaygo/keep_alive');

  /// 当前平台是否支持保活（仅 Android 原生实现）
  static bool get isSupported =>
      !kIsWeb && Platform.isAndroid;

  /// 启动前台保活服务
  static Future<bool> start() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('startKeepAlive') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 停止前台保活服务
  static Future<bool> stop() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('stopKeepAlive') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 是否已加入电池优化白名单（非 Android 视为已忽略）
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!isSupported) return true;
    try {
      return await _channel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          true;
    } catch (_) {
      return true;
    }
  }

  /// 请求加入电池优化白名单（弹出系统授权对话框）
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!isSupported) return false;
    try {
      return await _channel
              .invokeMethod<bool>('requestIgnoreBatteryOptimizations') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
