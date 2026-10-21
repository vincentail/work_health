# WorkHealth 健康提醒

macOS 菜单栏小工具：久坐提醒起身活动、定时提醒喝水。原生 Swift 编写，无第三方依赖。

## 构建 / 安装

```bash
./build.sh            # 构建到 build/WorkHealth.app
./build.sh install    # 构建并安装到 ~/Applications，然后启动
```

需要 macOS 13+ 和 Xcode Command Line Tools（`xcode-select --install`）。

## 功能

- **久坐提醒**：连续使用电脑达到设定时长（默认 45 分钟）弹窗提醒，可「开始活动」（倒计时 5 分钟）、「稍后提醒」或「跳过」
- **喝水提醒**：默认每 30 分钟提醒一次，记录当天喝水杯数（目标 8 杯）
- **智能识别离开**：键鼠无操作超过 5 分钟、锁屏或合盖休眠，自动视为已休息并重新计时；不在电脑前时不弹喝水提醒，回来后再提醒
- **菜单栏**：实时显示已坐分钟数 / 活动倒计时；支持暂停提醒（30 分钟 / 1 小时 / 2 小时 / 手动恢复）
- **设置**：所有时长可在菜单「设置」中调整，提示音可选系统声音或自定义音频文件（mp3/m4a/wav 等，选中即试听），支持开机自动启动

开机自动启动通过 `~/Library/LaunchAgents/com.workhealth.healthreminder.plist` 实现，记录的是当前 App 路径；移动 App 后需重新勾选一次。

## 自动构建

推送到 `main` 或提 PR 时，GitHub Actions 会自动构建，产物 `WorkHealth.zip` 可在 Actions 运行页面下载。推送 `v*` 标签（如 `git tag v1.0 && git push origin v1.0`）会自动创建 Release 并附带安装包。

未签名公证的 App 首次打开会被 Gatekeeper 拦截，解压后执行 `xattr -cr WorkHealth.app` 或右键「打开」即可。
