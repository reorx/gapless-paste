// DEBUG 菜单/徽标验收：fixture <状态> | dump <文件> | export <目录> | details
// open-menu | appearance <light|dark|system> | reduce-motion <on|off|system>
// key <down|return|escape> 向 app 自己的事件队列投递按键，供原生菜单导航验收。
// windows <settings|preview|close> | retry；完整说明见 kb/docs/ui-acceptance.md。
// action <upload|quick|push|pull|drop|image-exit|image-throw> <ssh别名> <远端目录> [本地文件…]
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("usage: swift scripts/transfer_debug.swift <command> [arguments…]\n", stderr)
    exit(1)
}
let data = try JSONEncoder().encode(Array(CommandLine.arguments.dropFirst()))
DistributedNotificationCenter.default().postNotificationName(
    .init("com.reorx.gaplesspaste.debug.transfer"), object: String(decoding: data, as: UTF8.self),
    userInfo: nil, deliverImmediately: true
)
Thread.sleep(forTimeInterval: 0.2)
