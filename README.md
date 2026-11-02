# 大肥鱼桌宠

独立运行的 macOS 桌宠（AppKit + SpriteKit + SwiftUI），当前版本 0.1.22。

她会站在屏幕底部或窗口顶上陪着你：视线跟随鼠标（32 个方向），可以拖着跑、抢饭盆、挂在窗口边上、坐在窗沿晃腿、趴着睡，也会自己走动、爬窗、看程序坞图标。饭盆里的米量显示 Codex 或 Claude 的剩余额度。

## 构建

需要 macOS 14 以上和 Xcode 命令行工具（Swift 6）。

```bash
bash Scripts/build.sh
```

应用会打包到临时目录，路径写在 `dist/run-app-path.txt`，安装包在 `dist/大肥鱼-<版本>.zip`。把 `大肥鱼.app` 复制到 `~/Applications` 即可使用。

签名：如果登录钥匙串里有名为 “Dafeiyu Local Signing” 的代码签名证书，就用它签名，这样换版本后系统设置里的辅助功能权限不会丢；没有这张证书时退回临时签名（ad-hoc）。

## 测试

```bash
bash Scripts/test.sh
```

共 83 项。有几项是按时间采样的动画测试，系统负载很高时偶尔会失败，重跑即可。

## 额度

- Codex：调用本机 Codex 的 `app-server` 账号额度接口，认证由 Codex 管理。
- Claude：从系统钥匙串读取现有 Claude Code 登录，在内存中查询额度接口。

大肥鱼不保存、不上传、不改写任何登录令牌，也不发起模型对话。

## 素材

`Sources/Dafeiyu/Resources/Assets` 是已经准备好的运行素材。原画和生成素材的脚本不在这个仓库里，所以这里的构建直接使用这些素材，不会重新生成。
