# Display Handoff

[English](README.md)

一台屏幕专供 Windows，另一台屏幕由 Windows 和 Mac 共用。两边各有一个桌面按钮，一次点击会把显示器输入源和 Windows 的桌面布局一起切好。

| 按钮 | 行为 |
| --- | --- |
| Windows 的 **Switch to Mac** | 激活 Mac 的视频输出，把共享屏切给 Mac，Windows 只使用专用屏。启用 Deskflow 联动时，Mac 客户端在后台启动。 |
| Mac 的 **Return to Windows** | 先恢复 Windows 的双屏布局，再切回共享屏。启用联动时，Mac 客户端自动退出。按钮会作为 Finder 应用运行。 |

切回后会恢复共享屏为主屏，并还原原有的摆放位置、分辨率和刷新率。两端使用 Mac 的 SMB 文件共享传递指令。Windows 的 Deskflow 服务端保持待命。

## 安装

需要一台 Windows 11 电脑、一台 macOS 12 或以上的 Apple 芯片 Mac，以及两根分别接入共享屏的线。显示器和接线都需要支持 DDC/CI 切源和读回。建议先用两根直连的 DP 或 USB-C 转 DP 线验证。Mac 合盖使用时保持供电和登录，并在电池选项里开启接入电源、显示器关闭时防止自动睡眠。[Apple 睡眠设置](https://support.apple.com/zh-cn/guide/mac-help/mchle41a6ccd/mac)

在两台电脑下载或克隆本仓库，在仓库目录中运行命令。

1. **Mac**。安装 [m1ddc](https://github.com/waydabber/m1ddc) 1.3.3 或以上版本，例如 `brew install m1ddc`。用显示器菜单选中 Mac 输入，运行 `m1ddc display list detailed`，记下共享屏的 **System UUID**。如果使用 Deskflow，先确认 Windows 服务端和 Mac 客户端能连接，并退出 Mac 客户端。

   ```bash
   bash macos/install.sh --display YOUR-MONITOR-UUID --windows-input 15 --mac-input 16 --deskflow
   ```

   省略 `--deskflow` 就只切显示器。输入源用十进制，DP 1 和 DP 2 常用 `15` 和 `16`，请以自己显示器的读数为准。两端使用相同的编号。可以加 `--check-only` 先检查 Mac 能否读回输入源。
2. **设置 SMB**。在 Mac「文件共享」里单独共享 `~/Library/Application Support/DisplayHandoff/mailbox`，给 Windows 使用的账号读写权限。使用有账号的 SMB 访问，关闭此共享的访客访问。用 Windows 文件资源管理器打开共享目录，能看到 `events.log` 就找对了。[Apple 的 SMB 设置说明](https://support.apple.com/zh-cn/guide/mac-help/mchlp1657/mac)
3. **Windows**。先用显示器菜单切回 Windows，在显示设置里选择扩展桌面，把共享屏设为主屏，并按日常用法排好位置。把示例中的 SMB 路径换成刚才打开的共享路径。

   ```powershell
   powershell.exe -NoProfile -File .\windows\Install.ps1 -MacShare '\\macbook.local\mailbox' -WindowsInput 15 -MacInput 16
   ```

   可以加 `-CheckOnly` 先验证显示器和 SMB。安装后双击 Windows 桌面的 **Switch to Mac**，再用 Mac 桌面的 **Return to Windows** 切回。

## 排查与卸载

- Mac 无响应时，确认它已经登录、文件共享可访问，两台电脑时间已同步。如果 Mac 已进入整机睡眠，先用外接键盘唤醒。
- 输入源切换失败时，可用显示器菜单选回 Windows，再双击 Windows 桌面的 **Restore Windows displays** 恢复布局。
- 如果换了显示器、端口或主屏，先恢复目标双屏布局，再重新安装。Mac 的显示器 UUID 和 Windows 设备路径可能随接线变化。
- 卸载前先切回 Windows。Windows 运行 `powershell.exe -NoProfile -File .\windows\Uninstall.ps1`，Mac 运行 `bash macos/uninstall.sh`，随后在 Mac 的文件共享中移除邮箱目录。脚本会保留配置和日志方便排查。

原型已在 Windows 11 和 Apple 芯片 Mac 的双 DP 共屏环境用真机验证。各显示器和转接器的兼容性会有差别。详细步骤和排查路径见[英文说明](README.md)。项目采用 [MIT 许可证](LICENSE)。
