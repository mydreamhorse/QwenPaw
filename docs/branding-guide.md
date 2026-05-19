# QwenPaw 品牌变更指南（一键改 Logo/名称）

## 图标文件（改 Logo 时更新这些）

| 文件 | 用途 | 格式要求 |
|------|------|---------|
| `scripts/pack/assets/icon.svg` | 源文件 | SVG 1024x1024 |
| `scripts/pack/assets/icon.ico` | Windows 安装包/快捷方式/窗口图标 | ICO 多尺寸 (256/128/64/48/32/16) |
| `scripts/pack/assets/icon.icns` | macOS 安装包 | ICNS |
| `console/public/logo-mark.svg` | 前端 console 品牌标识 | SVG |
| `website/public/logo.png` | 官网 logo | PNG |

### 从 SVG 生成 ICO 的命令

```powershell
# 需要 Node.js (sharp) + Python (Pillow)
cd D:\lab\QwenPaw
npm install sharp --no-save
node -e "
const sharp = require('sharp');
const fs = require('fs');
const svg = fs.readFileSync('scripts/pack/assets/icon.svg');
(async () => {
  for (const s of [256,128,64,48,32,16]) {
    await sharp(svg).resize(s,s).png().toFile('scripts/pack/assets/icon_'+s+'.png');
  }
})();
"
python -c "
from PIL import Image; import os
base = 'scripts/pack/assets'
sizes = [256,128,64,48,32,16]
imgs = [Image.open(os.path.join(base,f'icon_{s}.png')).convert('RGBA') for s in sizes]
imgs[0].save(os.path.join(base,'icon.ico'), format='ICO', sizes=[(s,s) for s in sizes], append_images=imgs[1:])
for s in sizes: os.remove(os.path.join(base,f'icon_{s}.png'))
print('Done')
"
```

## 名称配置（改名时修改这些）

### 1. 安装目录名 (`APP_NAME`) — 默认 "Luobotou"
- `scripts/pack/build_win.ps1` L16: `$AppName` 默认值
- `scripts/custom/build-win-installer.ps1` L9: `$env:APP_NAME`
- `scripts/custom/build-macos-installer.sh` L7: `APP_NAME`
- 影响: 安装路径 `$LOCALAPPDATA\{APP_NAME}`、注册表 `HKCU\Software\{APP_NAME}`、进程匹配

### 2. 显示名称 (`APP_DISPLAY_NAME`) — 默认 "AI工作台"
- `scripts/pack/build_win.ps1` L17: `$AppDisplayName` 默认值
- `scripts/custom/build-win-installer.ps1` L10: `$env:APP_DISPLAY_NAME`
- `scripts/custom/build-macos-installer.sh` L8: `APP_DISPLAY_NAME`
- 影响: NSIS 安装器标题、桌面/开始菜单快捷方式名、BAT/VBS 启动器文件名

### 3. 窗口标题 (`QWENPAW_DESKTOP_TITLE`) — 默认跟随 APP_DISPLAY_NAME
- `src/qwenpaw/cli/desktop_cmd.py` L27: `DEFAULT_DESKTOP_TITLE` Python 硬编码默认值
- `scripts/pack/build_win.ps1` L18: `$DesktopTitle` → 写入 BAT 启动器的环境变量
- 影响: pywebview 窗口标题栏

### 4. 窗口/任务栏图标
- `src/qwenpaw/cli/desktop_cmd.py` ~L231: `webview.create_window(..., icon=icon.ico路径)`
- `scripts/pack/build_win.ps1` L345-351: 复制 `icon.ico` 到打包环境根目录
- `scripts/pack/desktop.nsi` L8-9: `MUI_ICON` / `MUI_UNICON` 安装器图标
- `scripts/pack/desktop.nsi` L60-64: `CreateShortcut` 快捷方式图标

### 5. 前端页面标题
- `console/index.html` L7: `<title>` 标签

## 快速改名检查清单

改名时 grep 以下关键词确认无遗漏:
```
grep -rn "QwenPaw Desktop" src/ scripts/ console/index.html
grep -rn "APP_NAME" scripts/pack/
```
