# 媒体下载器（Flutter macOS / iPhone）

查看 [X](https://x.com/) 热点与关注动态，下载 X 视频。

国内访问需要先开启 **Clash / VPN**。本应用不内置 VPN。

## 运行

```bash
cd ~/Desktop/myProject/media_downloader

# Mac
fvm flutter run -d macos

# iPhone（需用数据线连接，并在手机上信任此电脑）
# 新系统上 Debug/JIT 会崩溃，请用 profile 或 release
fvm flutter run --profile -d ios
```

## 使用前准备

### Mac

1. 打开 Clash Verge 或其他系统代理，确认混合端口（常见 `7890` 或 `7897`）。
2. 若要用「仅音频」，安装 ffmpeg（本机已有可跳过）：

```bash
brew install ffmpeg
```

3. 启动应用后先到「设置与代理」核对代理端口，点「检查环境」。

文件默认保存到 `~/Downloads/MediaDownloader`。

### iPhone

1. 先打开系统 VPN（小火箭 / Stash 等），再打开本应用。一般**不用**填 `127.0.0.1` 本地代理。
2. 下载文件在「文件」App → 我的 iPhone → 媒体下载器；完成后也可点「分享」。

## 功能

- X 热点：全球及地区实时热搜，点击用浏览器打开搜索
- X 关注：添加想跟踪的账号，查看资料并下载帖子视频
- X 视频：粘贴状态链接，走直链下载
- 下载列表：完成后可直接播放

## 使用边界

- X：只下载你拥有权利或已被授权的内容，不要未授权传播
- 本应用不会绕过付费墙或 DRM
