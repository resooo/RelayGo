package com.relaygo.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 开机自启接收器。
 *
 * 监听开机广播（含快速开机 / 锁屏后开机），自动：
 *  1. 启动保活前台服务 [KeepAliveService]；
 *  2. 拉起 [MainActivity] 初始化 Flutter 引擎，使代理服务恢复运行。
 *
 * 是否真正自启由 Flutter 层「开机自启」设置项控制：MainActivity 启动后
 * 会读取设置，仅在开启时自动启动代理服务。
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON" -> {
                // 先启动前台保活服务，保证进程不被系统立即回收
                KeepAliveService.start(context)
                // 拉起主界面，让 Flutter 引擎初始化并（按设置）自动启动代理
                val launch = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(launch)
            }
        }
    }
}
