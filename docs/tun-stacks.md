# TUN 协议栈

bowel 使用 mihomo 的 TUN 实现。当前固定的 mihomo v1.19.33 已通过
sing-tun v0.4.28 集成 MetaCubeX/mipstack，选择 `mips` 即使用 MIPS
（mihomo IP stack），无需另装内核或插件。

## 桌面端

在「设置 → TUN → 协议栈」选择 `mips`。也可以通过命令行修改正在运行的应用：

```text
bowel settings set tunStack mips
```

可选项为 `mixed`、`system`、`gvisor`、`mips`。默认仍为 `mixed`，已有设置保持原值。
主页 TUN 详情会显示实际选择的协议栈。首次开启 TUN 的系统授权流程保持不变。

## Android

在「设置 → 内核选项 → TUN → 协议栈」选择 `MIPS`；需要时可切回 `gVisor`。
默认保持 gVisor，之前继承到设置文件中的桌面端 `mixed` 值仍按原来的 gVisor 执行和显示。

选择会保存到内核设置的 `tunStack` 字段。VPN 已开启时，沿用现有配置重载流程，
保留 VPN 文件描述符与手机端的路由、MTU 设置；内核拒绝配置时恢复原设置。
iOS 扩展继续使用原来的 gVisor，本次没有增加 iOS 的切换入口。

MIPS 使用 MetaCubeX/mipstack 的用户态协议栈实现。本次没有更改默认协议栈，
也没有对不同协议栈的性能作比较。
