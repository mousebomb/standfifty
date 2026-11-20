# StandFifty

每小时第 50 分钟（可配）弹全屏遮罩，强制离开键盘 60 秒的 macOS 菜单栏小工具。

为替代 Apple Watch 的站立提醒而生：Apple Watch 只在手腕上震一下，盯着屏幕时经常注意不到；而 HealthTick 只能从「开始工作 / 解锁」起算倒计时，做不到「每小时固定第 50 分」。

## 行为

```
每小时第 50 分
  ├ 本小时已离开（屏保/锁屏/显示器睡眠）累计 ≥ 60 秒  → 静默跳过，不计数
  ├ 正在屏保 / 锁屏 / 显示器睡眠                      → 不弹，等回到电脑再判定
  └ 否则                                            → 全屏遮罩
        ├ 离开键盘凑满 60 秒  → 自动关闭 + 响铃（计「完成」）
        ├ 点「我已起来活动」  → 关闭（计「完成」）
        ├ 点「1 分钟后再提醒」→ 60 秒后重弹，锚点序列不动
        └ 点「本小时已活动过」→ 关闭（计「跳过」）
```

关键约束：**无论怎么点，下一次提醒永远落在下一小时的锚点上，绝不漂移**。

唤醒 / 解锁后，若距本小时锚点不超过 15 分钟且本小时还没处理过，立即补弹一次；超过则跳到下一个锚点，避免一开机就被遮罩怼脸。

## 安装

```bash
./build.sh                       # 跑测试 → Release 编译 → 打 .app → ad-hoc 签名
cp -R dist/StandFifty.app /Applications/
open /Applications/StandFifty.app
```

开机自启在菜单栏下拉里勾选（走 `SMAppService`，要求 app 在 `/Applications`）。

## 菜单栏

- 左侧倒计时：剩余分钟数、`延后 12s`、`起来！`
- 下拉：下次提醒时刻、本小时已离开时长、今日 提醒/完成/跳过、立即测试、设置、开机自启、退出

## 设置项

| 项 | 默认 | 说明 |
|---|---|---|
| 锚点分钟 | 50 | 每小时第几分钟 |
| 补提醒窗口 | 15 分钟 | 唤醒后距锚点多久以内还补弹 |
| 活动门槛 | 60 秒 | 本小时累计离开多久算已活动 |
| 遮罩解锁 | 60 秒 | 连续离开键盘多久自动关闭 |
| 延后 | 60 秒 | 点「延后」后的等待时间 |
| 工作时段 | 07:00–22:00 | 时段外完全不提醒，起止相同=全天 |

## 结构

```
Sources/StandFiftyCore/      纯逻辑，可单测
  Anchor.swift               每小时第 N 分钟的锚点计算
  Schedule.swift             锚点 + 工作时段过滤
  AwayTracker.swift          按自然小时分账的离开时长统计
  AppConfig.swift            配置与 UserDefaults 持久化
  Stats.swift                今日三项计数
  IdleMonitor.swift          键鼠空闲时长采样

Sources/StandFifty/          AppKit 外壳
  main.swift                 装配 + 屏保/锁屏/睡眠通知订阅
  Scheduler.swift            两态状态机（等待 / 提醒中）
  OverlayWindow.swift        屏保级全屏遮罩
  StatusBar.swift            菜单栏
  SettingsWindow.swift       SwiftUI 设置面板
  OverlaySnapshot.swift      调试：离屏渲染遮罩 PNG
```

## 调试

```bash
swift test                                                   # 22 个用例
./.build/debug/StandFifty --ring-now                          # 启动即弹遮罩
./.build/debug/StandFifty --dump-overlay /tmp/overlay.png     # 离屏渲染遮罩（不弹窗）
./.build/debug/StandFifty --status                            # 打印当前排期与离开统计
```

`--dump-overlay` 用于没有「屏幕录制」权限时检查版式——屏保级窗口本来也不会被 `screencapture` 捕获。

## 已知边界

- **不检测「站起来」**：macOS 没有可靠的起身信号（HealthKit 在 iOS 侧、笔记本加速度计无公开 API）。方案改成「强制离开键盘」，零误判。
- 屏保 3 分钟才启动，所以「起身接杯水 40 秒」检测不到，第 50 分仍会弹，此时点「本小时已活动过」即可。
- 跨整点的离开按重叠秒数分账：09:49→10:05 记 09 点 11 分钟、10 点 5 分钟。
- 遮罩不抢键盘焦点（`.nonactivatingPanel`），打字不会被打断，但遮罩盖住后确实看不到内容，这是设计目的。

## 图标

- 原始素材：`docs/ref/matting_00179_.png`（透明底），`docs/ref/qwen_aio_00069_.png` 是不透明版本，不能用——`.icns` 需要 alpha，否则蓝色圆盘后面会露白方块。
- 生成：`swift scripts/make-icon.swift docs/ref/matting_00179_.png build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns`
- 脚本会自动找出实心图案的包围盒，按 macOS 规范把图案缩到画布 80%（824/1024），再输出 10 个尺寸。
