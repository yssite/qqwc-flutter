# 更新记录

版本号与 Release 一致，APK 见 [Releases](https://github.com/yssite/qqwc-flutter/releases)。

## v1.2.4

- 修复运营商一直显示错误的根因：`AppSettings.fromJson` 漏读 `schema`，构造函数默认值又是 2，
  导致 v1.2.3 的迁移从未执行；现 `schema = 3`，任何旧版本升级都会清理一次误存的运营商
- 广电 SIM（46015）按移动口径展示与匹配节点；出口 IP 识别出的广电宽带仍归「广电网」
- 新增 `test/settings_test.dart`（迁移执行 / 幂等 / 运营商口径 / schema 往返）

## v1.2.3

- 小区归属：主 PLMN → `additionalPlmns` → 共建共享对（46001↔46011、46000↔46015/46020）；
  匹配不到时只显示制式，不再冒用另一张卡的小区
- `TelephonyCallback` 改为授权后重试注册（此前启动即失败，`PhysicalChannelConfig` / `DisplayInfo` 恒为 0，
  4G·5G 频宽拿不到）
- 运营商口径：蜂窝优先数据卡 SIM，Wi-Fi / 有线才用出口 IP；结果卡记录 `TestRecord.oper`
- 切卡后自动重探出口 IP / 归属地 / 运营商；诊断页运营商带卡槽位
- 键盘弹出时隐藏悬浮导航栏，输入框随键盘抬升
- 开屏与 `NormalTheme` 底色改为 `#0A0C11`（原先还是模板的蓝色渐变）

## v1.2.2

- 双卡定位改三层判断：活动网络 `NetCapabilities.getSubscriptionIds()` → 默认数据卡（需真正连着数据）→ 遍历活动卡
- 新增诊断日志：3000 行环形缓冲 + 详细模式落盘，设置页可一键导出（含原生双卡快照）
- 新增 `test/app_log_test.dart`

## v1.2.1

- 第三版图标（深紫底 + 紫粉渐变弧），重新生成自适应前景与各密度 mipmap
- 蜂窝信息绑定「当前数据卡」，切换 SIM 后显示新卡的制式 / 频段 / 信号
- 用 `PhysicalChannelConfig` 读取下行带宽，补上 4G 与 Wi-Fi 频宽；Wi-Fi 增加 `ScanResult.channelWidth` 兜底
- 移除浅色主题，全局固定深色
- 新增 `test/link_test.dart`（链路文案 / 权限 / 版本 / 省级边界）

## v1.2.0

- 新图标；首页右上角改为链路标识（`移动 · 5G n41`），移除重复的历史入口
- 新增定位 / 电话状态权限申请与说明面板；定位优先匹配省份（运营商仍按出口 IP）
- 诊断页新增「连接类型 / 连接情况」；结果卡与记录详情加入网络标签
- 仪表盘去掉刻度短线，数值放大贴合外环
- 底部导航改悬浮半透明 + 由下往上渐隐遮罩，内容从胶囊下方透出
- 首页改 `SingleChildScrollView + spaceBetween`，小屏 / 高 DPI 可正常下滑
- 历史列表只保留上下行，修复右侧溢出；设置页底部显示 APK 版本号

## v1.1.0

- 首个完整发布：五个页面视觉统一、结果长图分享、CSV 导出、节点批量测延迟、网络诊断
- 启动图标、包名、应用名收口；四架构 APK
- 端到端验收记录见 `docs/设计与实施计划.md`

## v1.0.0

- 还原 CAICT「全球网测」Android 4.4.8 的公开协议：token 会话、裸 socket 多线程上下行、
  DES/ECB 节点表、596 个内置节点
- 测速引擎跑在独立 isolate；采样口径与桌面版一致（500ms 采样、真实时间戳 1s 滑动窗、预热剔除）
