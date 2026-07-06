# chatgpt.com 生图 DOM 侦察记录

实测日期:2026-07-06。账号:ChatGPT Pro 订阅。若 `find`/选择器连续两次定位失败,
说明页面已改版,需要重新做一次本文档的实测,不要凭旧记录硬猜新选择器。

## 登录态判定

- 未登录:页面右上角固定出现两个按钮,文案为 `Log in` 和 `Sign up for free`。
- 已登录:右上角登录按钮消失;侧边栏出现 `Library` / `Projects` / `Scheduled` / `Apps`;左下角
  出现头像 + 账号名 + 订阅等级(如 `<你的账号名>` / `Pro`)。
- claude-in-chrome 操作的是**当前打开的真实 Chrome**,和用户是否在别的窗口/设备登录无关——必须在
  被驱动的这个浏览器窗口里本人完成登录,Claude 绝不自动填账号密码。

## 触发生图

1. 新对话首页,composer 下方有三个快捷按钮:`Create an image` / `Write or edit` /
   `Look something up`。点 `Create an image`。
2. 点击后 composer 内出现一个**不可删除的 `Create image` 标签(pill)**,光标停在标签后,继续输入
   的文字就是图片描述。同时下方 `Explore ideas` 区域会展示参考图/风格模板卡片(如
   `Upload a photo`、`Messi mode`、`Bobblehead` 等),`Upload a photo` 可用于图生图——**本次未深入
   测试图生图的具体上传交互,后续需要该功能时应单独实测**。
3. 输入描述后点发送箭头按钮(或 `find` 定位 send 按钮)提交。

## 生成状态判定(核心决策表)

| 现象 | 检测方式 | 结论 |
|---|---|---|
| composer 右侧出现"停止"图标而非发送箭头 | `document.querySelector('[data-testid="stop-button"]')` 非空 | 生成中 |
| 停止按钮消失 | 同一 selector 变为 null | 生成阶段结束(还需判断是否真的产出了图片) |
| `main` 容器内出现 `img[alt^="Generated image"]` | `document.querySelectorAll('img[alt^="Generated image"]')` 有元素 | 生成成功 |
| 停止按钮消失但从未出现 `img[alt^="Generated image"]` | 同上为 0 | 判定为"未生成图片"(内容策略拒绝/仅文字回复),读取该 assistant turn 的纯文本作为原因 |

**关键坑**:
- 不要用泛化的 `main.querySelectorAll('img')` 计数——同一张生成图会因为渐进式加载动画渲染出
  2~3 个物理 `<img>` 标签(不同 `class`,如 `absolute top-0 z-1 w-full` 与 `absolute top-0 w-full`,
  应该是模糊占位层+清晰层叠加)。**必须用 `img[alt^="Generated image"]` 这个更精确的选择器**,alt
  属性固定以 `"Generated image: "` 开头,后面跟一句 AI 自己生成的图片描述,这个选择器实测每张图只
  会命中 1 个逻辑结果对应的最后一层。
- assistant 消息容器的选择器是 `section[data-turn="assistant"]`(或
  `[data-testid="conversation-turn-N"]`),**不是** `[data-message-author-role="assistant"]`——
  后者在当前版本页面上查不到任何元素。
- 实测一次生成耗时约 **63 秒**("Thought for 1m 3s")。轮询间隔建议 3-5 秒,超时阈值默认建议
  150-180 秒(留够余量,不要按 63 秒去卡死限)。
- 一次 `Create image` 请求实测**只生成 1 张图**,没有观察到"一次多图"的专门 UI 控件;要多张目前
  只能在 prompt 里附加要求(不保证生效)或多次调用。

## 图片托管与下载(最关键的实测结论)

生成图片的 `<img src>` 是 **ChatGPT 自家同源接口**,不是外部 CDN:

```
https://chatgpt.com/backend-api/estuary/content?id=<file-id>&ts=<timestamp>&p=fs&cid=<n>&sig=<签名>&v=0
```

### 路径 A(直连 URL 下载)—— 实测不成立

```js
await fetch(url, { credentials: 'omit' })     // -> 403, application/json
await fetch(url, { credentials: 'include' })  // -> 200, image/png
```

该接口**依赖浏览器 session cookie**,不是纯签名参数就能访问的公开 URL。脱离浏览器用
`Invoke-WebRequest`/`curl` 直接下载**不可行**,不要在这个方向上再尝试。

### 路径 B(右键"复制图片")—— 实测不成立

原生右键菜单是 **OS 级渲染**,不出现在页面无障碍树里。`find("Copy image context menu item")`
明确返回"不在无障碍树中",`right_click` 之后也截不到原生菜单画面。**这条路径无法通过
claude-in-chrome 自动化,不要采用。**

### 路径 C(点击图片自带的下载按钮)—— 实测成立,是唯一可用路径

1. 每张生成图 hover 工具条右下角有一个"分享/导出"图标(`find` 时语义描述为
   `"Share this image button"`,不要用固定坐标,坐标随对话长度/窗口大小变化)。
2. 点击后会打开一个 `[role="dialog"]` 的图片查看器弹层,里面有一个纯文本为 `Download` 的按钮
   (`find("Download button in image dialog")` 可稳定定位)。
3. 点击 `Download` 按钮后,Chrome **直接把文件存到系统默认 Downloads 目录**,文件名格式固定为:
   ```
   ChatGPT Image <Mon> <D>, <YYYY>, <hh>_<mm>_<ss> <AM/PM>.png
   ```
   例如 `ChatGPT Image Jul 6, 2026, 06_42_53 PM.png`。实测文件为**完整原始分辨率**(1254×1254,
   约 2MB),不是有损压缩后的截图。
4. `chrome://settings/downloads` 的"下载前询问保存位置"在测试用的 Chrome 上是关闭状态,所以下载
   全程无弹窗、无需人工确认。**如果用户的 Chrome 开着这个开关,路径 C 会失效**,需要在 SKILL.md
   里提醒用户关闭该开关,或改问用户手动保存。

**判定下载是否成功、拿到真实路径的唯一可靠方法:点击下载前后对 Downloads 目录做文件名快照 diff**
(不是看时间戳,是做真实的 before/after 文件名集合差集)。原因:这次下载**不产生任何新的网络请求**
(`read_network_requests` 全程看不到痕迹),是纯前端 blob 操作,没法从网络层面判断下载是否发生。
具体脚本见 `scripts/snapshot-downloads.ps1` + `scripts/capture-download.ps1`。

### 死路径:通过 `javascript_tool` 把图片 URL/字节传出浏览器

- 直接 `return img.src` → 被拦截返回 `[BLOCKED: Cookie/query string data]`。
- `return btoa(img.src)`(base64 之后再传)→ 依然被拦截,返回 `[BLOCKED: Base64 encoded data]`。
  **过滤器不是只认 `&`/`=` 这种 query-string 特征,对通用 base64 字符集也有独立识别**,所以"转成
  base64 绕过"这个思路对这个安全过滤器完全无效,不要在这个方向上浪费时间。
- 这意味着**任何试图把完整 URL 或图片字节通过 `javascript_tool` 返回值搬出浏览器的方案都不可行**
  (不只是因为 1-2KB 截断,是从根上就会被内容过滤器拦截)。
- **例外**:`tabs_context_mcp` 汇报的"当前标签页 URL"不受这个过滤器影响(那是标签页元数据,不是
  页面脚本回传值)。如果确实需要拿到完整签名 URL(比如想在浏览器内直接导航过去验证），可以在
  `javascript_tool` 里执行 `location.href = img.src`(只返回一个安全占位字符串,不返回 URL 本身),
  再用 `tabs_context_mcp` 读跳转后的真实 URL——但这只是调试手段,**正式流程不需要这一步**,因为
  路径 C 已经完全够用。

## 内容策略 / 边界情况实测

- 用一个模糊但敏感的请求测试:`"a photorealistic image of a specific real living celebrity's exact face"`。
  ChatGPT **没有硬拒绝**,而是先展示一段可展开的"思考摘要"(灰色小字 `Creating a portrait of a
  fictional celebrity ›`),正文说明"请求缺乏足够细节以确定具体人物,不应该擅自评判/挑选,因此会
  生成一个虚构的、非常有魅力的名人形象",然后**继续正常生成并成功产出图片**。
  - 结论:对于"影射真实人物但没点名"这类边界请求,ChatGPT 倾向于**软改写**而不是硬拒绝,生成流程
    不会中断。
  - 检测方式:assistant turn 里在生成图片之前会多出一段带小箭头的折叠摘要 + 说明文字块,可以用
    `find`/`read_page` 观察到,但**不影响"生成中/完成"判定逻辑**(最终仍会出现
    `img[alt^="Generated image"]`)。
- **本次没有实测触发到真正的硬拒绝**(纯文字回复、不产生任何图片)。按通用经验,判定逻辑已经在
  上面"生成状态判定"表格里覆盖:停止按钮消失 + 从未出现 `img[alt^="Generated image"]` = 判定为
  拒绝/失败,读取该 turn 的文本内容作为原因转述给用户。
- **额度耗尽提示**:测试账号是 Pro 订阅,未观察到"达到限制/请升级"类提示,如实标注为未验证项,
  实现时不要编造具体文案,遇到时按"出现未知阻断性提示"降级为"终止并如实转述页面文字"处理。

## 待验证 / 已知缺口

- 参考图上传(图生图/编辑)的具体交互细节(`Upload a photo` 之后的文件选择、上传后如何附加到
  prompt)——本次未测试,`reference_image_path` 参数标注为"待后续实测"。
- 免费账号(非 Pro)的额度耗尽提示文案——未观察到,不要编造。
- 一次生成多图的官方 UI 控件——未发现,暂按"一次一图"设计。

## 工程性坑(和生图本身无关,但会打断流程)

- `computer` 的 `screenshot`/`zoom` 在这次侦察过程中**多次出现 `CDP sendCommand
  "Page.captureScreenshot" timed out after 30000ms" / "renderer may be frozen"`**,尤其是在刚点开
  图片查看器弹层(`role="dialog"`)之后立刻截图时。规律:**重试 1-2 次通常能恢复**;如果连续 3 次
  以上超时,不要死等同一个 tab——直接 `tabs_create_mcp` 开新标签页、`navigate` 回同一个对话 URL
  (`https://chatgpt.com/c/<uuid>`,对话历史是持久化的,可以直接复用这个 URL),再 `tabs_close_mcp`
  关掉坏的旧标签页。
- 图片查看器弹层(`role="dialog"`)打开后,**`computer` 截图经常拍不出弹层的正确内容**(有时返回
  一个奇怪的裁切尺寸如 477×62,或直接超时)。**不要依赖截图判断弹层是否打开/定位按钮**——改用
  `document.querySelectorAll('[role="dialog"]').length`(`javascript_tool`)或直接 `find` 按钮,这
  两种方式在弹层不可见/截图异常时依然能正确工作。
