# Display Handoff

[简体中文](README.zh-CN.md)

Keep a Windows-only monitor and give a second monitor to whichever computer needs it. Two desktop buttons handle the input switch and the Windows display layout together.

| Button | What happens |
| --- | --- |
| **Switch to Mac** | Mac wakes its display output. The shared monitor switches to the Mac input. Windows makes its remaining monitor the sole desktop. The optional Deskflow client starts hidden. |
| **Return to Windows** | Windows restores its saved dual-display layout. Mac switches the shared monitor back to Windows and exits Deskflow if enabled. The Mac button runs as a Finder app. |

The layout snapshot preserves the original primary display, position, resolution, and refresh rate. The two computers exchange small requests through a Mac SMB share. No separate network service or hardware KVM is required.

## Requirements

- A Windows 11 PC with two extended displays, and an Apple silicon Mac running macOS 12 or later. The shared monitor is the Windows primary display in the dual-display layout.
- Both computers connect to separate inputs on the shared monitor. The monitor and both connections must support DDC/CI input readback and switching. The original setup used DisplayPort on Windows and USB-C to DisplayPort on Mac. Other monitors, docks, and adapters may behave differently.
- [m1ddc](https://github.com/waydabber/m1ddc) 1.3.3 or newer on the Mac. Install it with `brew install m1ddc` if you use [Homebrew](https://formulae.brew.sh/formula/m1ddc).
- The two computers can reach each other by authenticated SMB on a trusted LAN. Keep the Mac logged in and reachable. For closed-lid use, keep it on power and enable the option to prevent automatic sleep when its display is off. A Mac in full system sleep may need a keyboard wake before a handoff. [Apple sleep settings](https://support.apple.com/guide/mac-help/mchle41a6ccd/mac)
- Optional [Deskflow](https://github.com/deskflow/deskflow), with the Windows server and Mac client already paired. Verify keyboard and mouse sharing once, then quit the Mac client before running the installer with `--deskflow`. The installer enables Deskflow’s hide-on-startup preference. The Windows server stays available for reconnecting.

## Install

Clone this repository or download its source on both computers. Run the commands from the repository folder.

### macOS

1. Switch the shared monitor to the Mac input using its menu. Run `m1ddc display list detailed` and copy the **System UUID** of the shared monitor.
2. Run the installer with that UUID. Keep `--deskflow` to enable the optional integration, or omit it for display switching only.

   ```bash
   bash macos/install.sh --display YOUR-MONITOR-UUID --windows-input 15 --mac-input 16 --deskflow
   ```

   Use decimal DDC input codes. DisplayPort 1 and 2 commonly use `15` and `16`. HDMI 1 and 2 commonly use `17` and `18`. Match your monitor’s actual codes and pass the same pair on both computers. Add `--check-only` to verify Mac input readback before installing. [m1ddc input codes](https://github.com/waydabber/m1ddc#available-commands)
3. In macOS File Sharing, share only `~/Library/Application Support/DisplayHandoff/mailbox`. Give the account Windows will use read and write access. Use authenticated SMB and keep guest access off for this share. The mailbox contains the event log and temporary requests, and the executable and settings remain outside it. [Apple SMB setup](https://support.apple.com/guide/mac-help/share-mac-files-with-windows-users-mchlp1657/mac)

   The installer creates **Return to Windows.app** on the desktop and a background agent for the logged-in Mac user.

### Windows

1. Manually switch the shared monitor back to its Windows input. In Windows display settings, choose **Extend these displays** and make the shared monitor primary. Arrange the monitors as you want them restored after a handoff.
2. Open the shared mailbox in File Explorer and authenticate. Replace the example below with the UNC path where you can see `events.log`. The path points to the mailbox itself.

   ```powershell
   powershell.exe -NoProfile -File .\windows\Install.ps1 -MacShare '\\macbook.local\mailbox' -WindowsInput 15 -MacInput 16
   ```

   Add `-CheckOnly` to verify the Windows display paths, DDC readback, and SMB access without creating shortcuts or starting the listener. If PowerShell blocks scripts downloaded in a ZIP, review the source and unblock just the extracted project scripts before installing.
3. Double-click **Switch to Mac** on the Windows desktop. Then double-click **Return to Windows** on the Mac desktop. The Windows desktop also has **Restore Windows displays**, and the listener starts at Windows sign-in.

## Troubleshooting

- **Mac doesn’t acknowledge the handoff.** Confirm that both users are logged in, Windows can read and write the mailbox, and both system clocks are synchronized. Check that the Mac can still respond with the lid closed. If it is asleep, wake it with an external keyboard.
- **The monitor stays on the wrong input.** Enable DDC/CI in the monitor menu and verify the two configured codes. If the monitor rejects the switch, select Windows manually from its input menu and use **Restore Windows displays** to restore the layout.
- **Changed the cable, displays, or primary display.** Restore the Windows dual-display layout and rerun the relevant installer. A different Mac connector can change the display UUID, and Windows can assign a different device path when you move a cable.
- **Deskflow doesn’t connect.** Confirm that the Windows server is running and the Mac client connects when opened by hand. Keep Deskflow’s **Start Core with GUI** enabled. Display switching works independently of Deskflow.
- **Inspect a failed attempt.** Windows writes `%LOCALAPPDATA%\DisplayHandoff\switch.log`. Mac writes `~/Library/Application Support/DisplayHandoff/agent.log` and `mailbox/events.log`. Review logs for local details before sharing them.

## Uninstall

Return to Windows first. From the source directory run `powershell.exe -NoProfile -File .\windows\Uninstall.ps1` on Windows and `bash macos/uninstall.sh` on Mac. These stop the background helpers and remove the desktop launchers. Local configuration and logs remain available for troubleshooting. Remove the mailbox from Mac File Sharing. If you want Deskflow visible at launch again, turn off its hide-on-startup preference.

## Validation and license

The original workflow was tested with Windows 11, an Apple silicon Mac, a Windows-only monitor, and a shared monitor using two DisplayPort inputs. The portable installers and automated checks are part of this repository. Display timing and DDC support depend on the monitor and connection.

[MIT](LICENSE). Deskflow and m1ddc are installed separately and retain their own licenses.
