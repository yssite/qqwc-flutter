# 更新记录

版本号与 Release 一致，APK 见 [Releases](https://github.com/yssite/qqwc-flutter/releases)。

## v1.3.2

- 更新说明按 Markdown 渲染（标题 / 列表 / 粗体 / 行内代码 / 引用 / 分隔线 / 代码块），不再显示原始符号
- 取消安装后再次点「更新」复用已下载的安装包，不再重复下载；按钮在下载完成后变为「安装」
- 记录列表更紧凑：节点名已含运营商时不再重复显示运营商胶囊，卡片内边距与字号收紧
- 新增 `test/markdown_test.dart`

## v1.3.1

- 记录列表每行加上链路胶囊（运营商 + 制式频段，如 `移动` `5G n41`），不用进详情也能看出当时走的什么网
- 列表时间改为 `MM-DD HH:mm` 紧凑格式，完整时间仍在详情页
- 新增 `TestRecord.shortTimeText`

## v1.3.0

- **应用内更新**：设置页「检查更新」查询 GitHub Release，按 ABI 选包，多线程分段下载后拉起系统安装器
- 启动时自动检查更新（可在设置里关闭；6 小时内不重复请求），发现新版本显示「检测到新版本：x.y.z   详情 / 更新」提示条
- 更新详情弹层：版本、更新说明、下载进度、在浏览器打开
- 「关于」新增 GitHub 仓库与发布页入口
- 修复：主按钮 / 结果页「再测一次」/ 失败重试都会重新匹配节点（此前会沿用上一次的节点，
  切卡或切 WiFi 后仍在测旧运营商的服务器）
- 新增 	est/updater_test.dart（版本比较、ABI 选包、取消识别）

## v1.2.5

- 链路变化改为**事件驱动**：原生 ConnectivityManager.registerDefaultNetworkCallback 与
  TelephonyCallback（DisplayInfo / PhysicalChannelConfig）直接 push 给 Dart，Wi-Fi ↔ 蜂窝、切卡后界面立即更新
- 12 秒轮询保留为兜底（回调漏发或 ROM 限制时仍能纠正）
- 运营商变化也会触发重新探测出口 IP / 归属地
- 新增 	est/link_events_test.dart（事件通道 → 变化流）
- README 精简：三图并排 + 亮点说明，更新记录独立到本文件

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
