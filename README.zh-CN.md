<p align="center">
  <img src="docs/icon.png" width="112" height="112" alt="">
</p>

<h1 align="center">ccid</h1>

<p align="center">
  一个快捷键，找到任何 Claude Code 会话的 ID。
  <br>
  <a href="README.md">English</a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/panel-zh-dark.webp">
  <img src="docs/panel-zh-light.webp" width="848" alt="ccid 面板：搜索框下面是 Claude Code 会话列表，每行有标题、文件夹、最后说的话和短 ID">
</picture>

每个 Claude Code 会话都有一个 ID：`claude --resume` 要用，脚本要用，让一个会话去看另一个会话也要用。Claude 应用里看不到它，ccid 能。

在任何地方按 <kbd>⌃</kbd><kbd>⌘</kbd><kbd>I</kbd>，敲几个标题里的字，回车。ID 已经在剪贴板里，面板也收起来了。

## 能做什么

- **凭印象找会话**：标题、文件夹、说过的话都行。拼音也行，`zmt` 能找到“自媒体”，`cg` 能找到“重构”。
- **翻遍全部记录**：<kbd>⌘</kbd><kbd>↩</kbd> 在所有会话里找一句原话，还告诉你是你说的还是 Claude 说的。
- **应用和终端都认**：Claude 应用、终端里的 `claude`、编辑器里开的会话都在。分叉的会话有标记，归档的不占地方。
- **不打扰**：住在菜单栏，不抢你当前应用的焦点，复制完直接粘贴。
- **带命令行工具**，写脚本用：`claude --resume "$(ccid -1 登录)"`。
- **只读**：不联网，不统计，不用授权任何权限。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/pinyin-zh-dark.webp">
  <img src="docs/pinyin-zh-light.webp" width="848" alt="输入拼音首字母 xs，找到“新手引导打磨”等会话">
</picture>

## 安装

需要 macOS 14 或更新版本，在 macOS 26 上是液态玻璃外观。目前还没有签名的安装包，要从源码构建。装有 Xcode 16 或更新版本的话（液态玻璃要 Xcode 26），大约一分钟：

```bash
git clone https://github.com/AppApp777/ccid.git
cd ccid
scripts/build-app.sh
cp -R dist/ccid.app /Applications/
open /Applications/ccid.app
```

想在终端里用 `ccid`，在它的菜单里选“安装命令行工具…”。

## 按键

| | |
|---|---|
| <kbd>⌃</kbd><kbd>⌘</kbd><kbd>I</kbd> | 打开或关闭面板（可在菜单里换） |
| <kbd>↑</kbd> <kbd>↓</kbd> | 上下选（<kbd>⌃</kbd><kbd>N</kbd> <kbd>⌃</kbd><kbd>P</kbd> 也行） |
| <kbd>↩</kbd> | 复制 ID 并关闭 |
| <kbd>⌘</kbd><kbd>↩</kbd> | 在全部记录里找你输入的话 |
| <kbd>esc</kbd> | 退一步：先退出全文结果，再清空输入，最后关闭面板 |

右键某个会话，可以复制“回到它所在文件夹并恢复”的命令，或在访达里显示它的记录文件。点菜单栏图标打开面板，右键图标是设置。

## 命令行

```bash
ccid                       # 最近的会话
ccid 登录                  # 按标题、文件夹、拼音或说过的话筛
ccid -g "进度条"           # 记录里说过这句话的会话
ccid -1 登录               # 只要最匹配那个的 ID
ccid -c 登录               # 直接复制
eval "$(ccid -r 登录)"     # 进到它的文件夹并恢复会话
ccid --json                # 同样的列表，JSON 格式
```

`ccid --help` 列出全部选项。在哪个会话里运行，哪个会话前面就有 ●。

## 原理

Claude 应用给每个会话存一个小文件，在 `~/Library/Application Support/Claude/claude-code-sessions`，里面有标题、文件夹、是否归档、从哪个会话分叉。Claude Code 把每段对话写进 `~/.claude/projects/<文件夹>/<ID>.jsonl`（设了 `CLAUDE_CONFIG_DIR` 就在那下面），文件名就是 ID。

ccid 把两边对上。在终端里开的会话，用 `/rename` 起的名字或第一句话当标题。“最近活动”取应用记录的时间和记录文件修改时间里较新的那个。记录文件从末尾一点点往前读，再长也快。

## 常见问题

**会话的 ID 怎么变了？** 分叉会生成一个新会话，ID 也是新的。ccid 用 ⑂ 标出分叉，鼠标停在上面能看到它从哪来。

**快捷键没反应。** 多半被别的应用占了，在菜单里换一个。

**想试用又不想露出自己的会话？** 先退出 ccid，再用演示数据打开：`open --env CCID_DEMO=1 /Applications/ccid.app`。

## 开发

```bash
swift test               # 核心逻辑的测试（Sources/CCIDCore）
swift run ccid           # 从源码跑命令行工具
scripts/build-app.sh     # 生成 dist/ccid.app；UNIVERSAL=1 同时构建 Apple 芯片和 Intel 版
```

`CCID_CLASSIC=1` 可以在 macOS 26 上看旧系统的外观。`scripts/make-icon.sh` 重画图标。

## 许可

[MIT](LICENSE)。ccid 是独立项目，与 Anthropic 无关联，也未获其背书。Claude 和 Claude Code 是 Anthropic, PBC 的商标。
