---
name: chatgpt-image-gen
description: >
  驱动用户已登录的真实 Chrome(经 claude-in-chrome)打开 chatgpt.com,用 ChatGPT 原生的
  "Create an image" 生图能力生成图片,点击图片自带的下载按钮把文件存到调用者指定的本地目录,
  并报告最终绝对路径。触发词:"用 chatgpt 生成/画一张图"、"chatgpt 生图"、"chatgpt.com 画图"、
  "帮我用 ChatGPT 出一张图存到 xxx"。这是操作网页版 UI,不是调用 OpenAI API/SDK;若用户要走 API
  或火山方舟/豆包生图(arkcli +gen),不要用本 skill。
---

# ChatGPT 网页版生图(claude-in-chrome 驱动 + 自动落盘)

## Overview

用 claude-in-chrome 操作用户当前已登录的真实 Chrome,在 chatgpt.com 用原生 "Create an image"
能力生成图片,再点击图片自带的下载按钮把文件存到本地,最终把绝对路径报告给用户。全程不需要新建
浏览器 profile、不需要重新登录、不需要任何自定义 MCP server。

这是一次全局能力,不绑定任何具体项目的品牌规范。

## When to use / When NOT to use

- 用:用户想要"用 ChatGPT 生成一张图并存到本地某个目录"。
- 不用:用户要走 OpenAI API/SDK 编程调用 —— 那是纯代码集成,不需要操作浏览器。
- 不用:用户要火山方舟/豆包生图 —— 用 `arkcli +gen`。
- 不用:用户要 Sora 视频 —— 那是 sora.chatgpt.com,不是本 skill 覆盖的范围。

## Prerequisites

- 用户 Chrome 已装 claude-in-chrome 扩展,且**已经在该浏览器里登录了 ChatGPT 账号**(不是随便哪个
  设备/窗口登录,必须是被 claude-in-chrome 实际驱动的那个 Chrome)。Claude 绝不自动填账号密码——
  发现未登录时终止,提示用户手动登录后重试。
- 若 `list_connected_browsers` 发现连了不止一个 Chrome,必须先用 `AskUserQuestion` 把每个已连接
  浏览器列出来让用户选(工具自身规则要求,不能自己代选)。
- 用户 Chrome 的下载设置里"下载前询问每个文件的保存位置"应为**关闭**状态,否则原生下载会弹一个
  claude-in-chrome 看不到的 OS 对话框,导致下载流程卡住。如果怀疑这个开关是开着的,提醒用户去
  `chrome://settings/downloads` 关掉。

## Parameters

| 参数 | 必填 | 说明 |
|---|---|---|
| `prompt` | 是 | 生图的自然语言描述,原样输入到 ChatGPT 的 "Create image" 组合框里 |
| `save_dir` | 是 | 保存目录(绝对路径),不存在则自动创建 |
| `filename` | 否 | 不给则用 ChatGPT 默认下载文件名(`ChatGPT Image <Mon> <D>, <YYYY>, <hh>_<mm>_<ss> <AM/PM>.png`) |
| `new_conversation` | 否,默认 true | true 则新建标签页开新对话;false 则复用用户已打开的 chatgpt 标签页(需用户明确要求) |
| `max_wait_seconds` | 否,默认 180 | 生成超时阈值(实测一次生成约 63 秒,180 秒留足余量) |
| `keep_tab_open` | 否,默认 true | 完成后是否关闭本次新建的标签页 |
| `reference_image_path` | 否 | 本地参考图路径,走 "Upload a photo" 做图生图——**具体上传交互未实测**,遇到时先按 `find` 探索,不要凭猜测硬编码步骤 |
| `count` / `aspect_ratio` | 否 | ChatGPT 网页版当前**没有发现**专门的数量/宽高比 UI 控件,只能在 prompt 文字里附加要求,不保证生效 |

参数细节和已知选择器全部以 `reference/dom-recon.md` 为准,那份文档记录了实测日期,选择器失效时先去
更新那份文档,不要直接改这里的表格。

## Workflow

1. **加载工具**:一次性 `ToolSearch` 批量加载 `tabs_context_mcp,navigate,computer,read_page,find,javascript_tool,tabs_create_mcp,tabs_close_mcp`(需要参考图再加 `file_upload`)。不要一个个单独加载。
2. **确认浏览器**:`list_connected_browsers`。只有一个且 `isLocal:true` 时也建议用 `AskUserQuestion`
   走一遍确认(工具自身的强制规则),避免误操作别人的浏览器。
3. **建标签页**:`tabs_context_mcp({createIfEmpty:true})` → `tabs_create_mcp()`(除非用户要求复用
   已开的标签页)。
4. **打开首页判定登录态**:`navigate` 到 `https://chatgpt.com`,等待 2-3 秒,`computer(screenshot)`
   看一眼。右上角出现 `Log in`/`Sign up for free` = 未登录,终止并提示用户手动登录;没有则视为已
   登录,继续。
5. **进入 Create image 模式**:`find("Create an image button")` 或直接点击首页 composer 下方的
   `Create an image` 快捷按钮;点击后 composer 内出现不可删除的 `Create image` 标签。
6. **输入描述并提交**:点击标签后的光标位置,`computer(type, text=prompt)`,再点发送箭头
   (或 `find("send button")`)。
7. **轮询生成状态**(每 3-5 秒一次,直到 `max_wait_seconds`):
   ```js
   // javascript_tool text 参数
   (() => {
     const main = document.querySelector('main');
     const stopBtn = document.querySelector('[data-testid="stop-button"]');
     const imgs = main.querySelectorAll('img[alt^="Generated image"]');
     return JSON.stringify({ generating: !!stopBtn, imgCount: imgs.length });
   })()
   ```
   - `generating:true` → 继续等待。
   - `generating:false, imgCount:0` → 没有产出图片:读最后一条 assistant turn
     (`section[data-turn="assistant"]`)的纯文本内容作为原因,转述给用户,终止(可能是内容策略
     拒绝,也可能是别的未知阻断——如实转述,不要编造"额度耗尽"之类没观察到的原因)。
   - `generating:false, imgCount>0` → 生成成功,进入下载步骤。
   - 超过 `max_wait_seconds` 仍 `generating:true` → 判定卡住,终止并告知用户已放弃(可选:换新
     对话重试 1 次)。
8. **下载**(核心步骤,只用下面这一条路径,不要尝试其他方式——原因见"Common mistakes"):
   1. Bash/PowerShell 执行 `scripts/snapshot-downloads.ps1`,记下它打印出的 Downloads 路径。
   2. `find("Share this image button")` 定位生成图片的分享/导出图标(hover 工具条右下角),
      `computer(left_click, ref=...)` 点击。
   3. 用 `javascript_tool` 执行 `document.querySelectorAll('[role="dialog"]').length` 确认弹层已
      打开(**不要靠截图判断**,弹层经常拍不出来或让截图工具卡住,详见 Common mistakes)。
   4. `find("Download button in image dialog")` 定位 Download 按钮,`computer(left_click, ref=...)`
      点击。
   5. Bash/PowerShell 执行 `scripts/capture-download.ps1 -SnapshotPath <上一步路径> -DestDir <save_dir> [-DestFileName <filename>]`,
      拿到脚本打印出的最终绝对路径。
9. **校验并报告**:确认返回路径的文件存在、大小非 0(脚本内部已做这个校验,拿到路径基本等于校验
   通过),把绝对路径告诉用户。
10. **收尾**:按 `keep_tab_open` 决定是否 `tabs_close_mcp` 关闭本次新建的标签页。

## Boundary cases

| 情况 | 处理 |
|---|---|
| 未登录 | 终止,提示手动登录,绝不自动填账号密码 |
| 内容策略拒绝/未产出图片 | 读取 assistant turn 文本转述原因,不擅自换措辞重试规避审核 |
| 边界请求被"软改写"(比如影射真实人物但没点名) | ChatGPT 通常不会硬拒绝,而是自己换成虚构版本继续生成——按正常"生成成功"流程处理,不用特殊拦截 |
| 生成卡住(超过 max_wait_seconds) | 终止并告知已放弃,可选换新对话重试 1 次 |
| 连了多个浏览器 | 遵循 `list_connected_browsers` 自带规则,`AskUserQuestion` 问用户选哪个 |
| 撞验证码/人机挑战 | 立即停,告知用户,不自动重试硬闯 |
| CDP 截图连续超时("renderer frozen") | 重试 1-2 次;仍不行就 `tabs_create_mcp` 开新标签页 `navigate` 回同一对话 URL(`https://chatgpt.com/c/<uuid>`),关掉旧标签页,不要死等 |
| `find`/选择器连续两次定位失败 | 停下来提示用户"ChatGPT 页面结构可能已变化,需要重新做一次 DOM 侦察",不要无限重试或瞎猜新选择器 |
| 下载前"询问保存位置"开关是开的 | 会弹出 claude-in-chrome 看不到的 OS 对话框卡住流程;提示用户去 `chrome://settings/downloads` 关闭该开关 |
| 同一 `save_dir` 连续调用文件名撞车 | `capture-download.ps1` 已内置:目标文件名已存在时自动加数字后缀,不会覆盖 |

## Common mistakes

- **不要**尝试脱离浏览器直接用 `Invoke-WebRequest`/curl 下载图片 URL——那是 ChatGPT 自家需要
  session cookie 的接口,没有 cookie 会 403。
- **不要**尝试自动化"右键 → 复制图片"——原生上下文菜单是 OS 级渲染,claude-in-chrome 的
  `find`/`read_page` 看不到菜单项,点不到。
- **不要**试图把图片 URL(哪怕转成 base64)通过 `javascript_tool` 的返回值传出来——原文会被拦成
  `[BLOCKED: Cookie/query string data]`,base64 之后依然被拦成 `[BLOCKED: Base64 encoded data]`。
  这条路完全走不通,别浪费时间重试。
- **不要**用固定像素坐标点击分享图标/下载按钮——坐标随对话长度、窗口大小变化,一律用 `find` +
  `ref` 点击。
- **不要**靠 `computer(screenshot)` 判断图片查看器弹层是否打开——弹层经常截不出来或让截图工具
  超时卡住,改用 `javascript_tool` 查 `[role="dialog"]` 数量,或直接用 `find`。
- **不要**用"点击下载后有没有新的网络请求"来判断下载是否成功——这次下载是纯前端 blob 操作,
  `read_network_requests` 全程看不到任何痕迹。唯一可靠方法是点击前后对 Downloads 目录做文件名
  快照 diff(`scripts/snapshot-downloads.ps1` + `scripts/capture-download.ps1` 已经封装好)。
- **不要**用泛化的 `main img` 计数判断是否生成了新图——同一张图会因为渐进加载渲染出 2-3 个物理
  `<img>` 标签,必须用 `img[alt^="Generated image"]` 这个更精确的选择器。
- 登录态不确定时**不要猜**——直接截图人工确认或询问用户,不要自动尝试登录。
- 遇到验证码/人机挑战**立即停**,不自动重试硬闯。

## 故障速查

| 报错/现象 | 原因 | 处理 |
|---|---|---|
| `CDP sendCommand "Page.captureScreenshot" timed out" / "renderer may be frozen"` | 常见于刚点开图片查看器弹层之后立刻截图 | 重试 1-2 次通常恢复;连续 3 次以上就换新标签页 `navigate` 回同一对话 URL |
| `javascript_tool` 返回 `[BLOCKED: Cookie/query string data]` 或 `[BLOCKED: Base64 encoded data]` | 试图把敏感/高熵字符串(URL、base64)通过返回值传出浏览器 | 别传这类数据出来,本 skill 的下载流程完全不需要这么做 |
| `capture-download.ps1` 报错 "No new stable download detected" | 下载按钮没点中(ref 过期/弹层没真的打开),或用户 Chrome 开着"下载前询问保存位置" | 用 `javascript_tool` 确认 `[role="dialog"]` 确实存在再重新 `find` 按钮点击一次;检查 Chrome 下载设置 |
| 生图请求发出去后一直卡在 "Thinking"，超过 3 分钟没反应 | 极少数情况下 ChatGPT 后端卡住 | 换新对话重试一次,仍不行就终止告知用户 |
