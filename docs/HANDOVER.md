# NekoEngine 交接文档（新对话用）

> 更新：2026-10-26 · 远端 master = `223b18e1`（Run #88 ✅ 编译成功）
> 阅读本文件后即可接手，无需翻旧对话。

## 1. 项目概述

- **NekoEngine**：Psych Engine 0.7.3 的安卓手机移植版（FNF 改引擎）。
- 技术栈：HaxeFlixel 5.5.0 + lime-modified + hxcpp（FunkinCrew fork ref 5932340d）。
- 仓库：`MuXue-Ya/NekoEngine`（**公开仓库**，第三方 mod 素材勿推）。上游参考 RenTheSylvee/FNF-PsychEngine-0.7.3-Mobile。
- 构建方式：GitHub Actions（`MainBuild.yml`），推 master 自动触发，约 25-40 分钟；产物名 `NekoEngine-Android`。
- **没有本地 git/gradle 环境**，所有代码改动通过 GitHub REST API（Git Data API）推送（见 §2.1）。
- api.github.com 可用；直连 github.com 可能超时（raw.githubusercontent 偶尔可用）。
- 本地完整源码树：`/sdcard/网页开发/0.73手机版源码/`（~1.1G，与远端同步）。

## 2. 工作方法（必须先读）

### 2.1 推送（Git Data API，python3 + heredoc）
流程：GET `/git/ref/heads/master` 取 base commit（**必须 assert 预期值**）→ GET commit 取 base_tree →
POST `/git/blobs`（content 用 base64, encoding=base64）→ POST `/git/trees`（带 base_tree）→
POST `/git/commits`（parents=[base]）→ PATCH `/git/refs/heads/master`。
- 推送前必须校验 blob sha：`sha1("blob %d\0" % len(data) + data)`。
- 脚本用 `python3 - <<'唯一分隔符'` heredoc；token 从环境变量读（见 §2.6），绝不写进文件。
- 推送会触发构建；一次只推一批改动，避免并行构建混乱。

### 2.2 构建日志排错
- 先取 run id（注意 API 用**数据库 id** 不是 run_number）→ `/logs` 返回 302 →
  **先用不带 Authorization 头的请求跟随 Location**，否则 403。grep `error:` 找编译错误行。

### 2.3 括号/语法校验（本地推送前必做）
- 简单花括号计数会**误报**（Paths.hx 有骗过检查器的模式）。必须用**字符串感知 + 注释感知 + `${}` 感知**的解析器（本会话验证有效，代码见历史对话/工作区）。
- 对"已编译成功的旧版本"跑同一检查器可快速判定误报。

### 2.4 手机端能力（DSHA）
- 本体在用户安卓手机容器里；App 层接口走 `http://127.0.0.1:3090/app/*`。
- 工作区 = `/sdcard/网页开发`（可写）。mods 目录 `/sdcard/.NekoEngine/mods/` 可直接读写。
- 性能日志：游戏内 PerfProbe 写 `/sdcard/.NekoEngine/debug/perf_log.txt`，用户手动导出到工作区。

### 2.5 mod ASTC 工具（就绪，按需使用）
- `网页开发/astctool/bin/astcenc-neon`（ARM astcenc 5.7.0 arm64 官方版）。
- /sdcard 挂载 noexec → 先 `cp 到 /tmp && chmod +x` 再跑（容器 /tmp 可执行）。
- 用法：`astcenc-neon -cl 输入.png 输出.astc 6x6 -medium -silent`；批量脚本模式见 `astctool/convert_list.txt` 流程。
- 已转换：TalkInRed mod 全部 9 张（.astc 与 .png 并存，游戏自动优先 .astc）。
- **用户已毙掉"批量转换全部 mod"**——只按需转换。

### 2.6 token
- 用户在对话里直接给 token（classic PAT）。**严禁把 token 写进任何文件/日志/commit message**。
- 后台 job 里跑推送脚本时注意：heredoc 的 python 读 `os.environ['GH_TOKEN']`，必须 `export GH_TOKEN=...`（曾因只设了 shell 变量导致 KeyError 推送失败）。

## 3. 当前状态（2026-10-26）

### 3.1 仓库
- master = `223b18e1`（Run #88 ✅）。
- 构建成功率历史：#84(JNI 错误)、#86(SOUND_EXT) 失败过，#85/#87/#88 修复链全绿。

### 3.2 性能现状（实测）
- 打歌堆内存：72~223MB（随 mod 大小）；进程 rss：菜单 156 / 打歌 500-1000MB（mod 未转 ASTC 时）。
- 判定：1115 次击中 98% 准（±45ms），带符号均差 +2ms，无方向偏差。
- GC：41 秒/次（最初 1.6s/次）。进歌尖帧 3s（最初 4.7s）。
- fps：用户 61Hz 屏，锁 60 打；不锁时 123 满帧。

## 4. Run 历史（#68 起）

| Run | commit | 结果 | 内容 |
|---|---|---|---|
| #68 | 3953a986 | ✅ | ASTC 管线上线（compress-from-json + 回填脚本），APK 333→268MB |
| #69 | 9f38d26e | ✅ | 修 excludes 路径（mobile/images/virtualpad）+ 暂停页触控改造 |
| #70 | 69a049fd | ✅ | noteSkins 移出压缩（箭头走样）+ PerfProbe 内存分解 |
| #71 | 99a12fe5 | ✅ | excludes 补 pixelUI（像素箭头 10x10 走样）|
| #72 | 0f53621d | ✅ | week1/week6 大图 4x4 化（基础周目省 100MB）|
| #73 | 4933aa62 | ✅ | ≥4MB 大图自动 GPU 化（打歌堆 213→157MB）|
| #74 | c8a191b3 | ✅ | 暂停页回退虚拟手柄（触控体验不佳）|
| #75 | ed52cfea | ✅ | 内存分解修正（readable 区分 GPU 化）+ RSS 采集 |
| #76 | 553f88cd | ✅ | **谱面窗口化**（不全量实例化 Note，40 万谱可用）|
| #77 | 4c3242cc | ✅ | Freeplay/MainMenu 退出清理 + SONG 释放 + rss v2 |
| #78 | 91f01d6d | ✅ | clearStoredMemory 顺序修复 + 音频对象显式销毁 + rss 流式读 |
| #79 | f62227c0 | ✅ | 相机合并 6→3（hitbox/PauseButton/暂停手柄复用 camOther）|
| #80 | 6ae8ccec | ❌ | drift 监控（generatedMusic private 访问错误）|
| #81 | 9e595631 | ✅ | private 修复；**实测 drift +100ms 固定偏差** |
| #82 | 4ff82fc3 | ✅ | **音画对齐修复**（50ms 死区硬对齐）→ 判定全 shit 根治 |
| #83 | 403bc3c2 | ✅ | 判定直方图 + 日志美化一期 |
| #84 | a6703f11 | ❌ | lime.utils.JNI 不存在 |
| #85 | 030b3e3a | ✅ | 设备头改读 /system/build.prop（注：设备行在用户设备上仍未显示，待查）|
| #86 | fb52dd36 | ❌ | SOUND_EXT 未加类名前缀 |
| #87 | 58ca2105 | ✅ | SOUND_EXT 修复 |
| #88 | 223b18e1 | ✅ | 日志版式二修（中文短名 + 轻分隔 + 双空格）|

## 5. 已完成改动明细（文件级）

- `MainBuild.yml`：ASTC 压缩步骤（compress-from-json + scripts/astc_backfill.py 回填+删原png）+ astc-textures 缓存。
- `astc-compression-data.json`：excludes 修正与扩充（noteSkins/pixelUI/mobile/images/virtualpad/pauseButton + 修正路径层级），week1/week6weeb 改 custom 4x4。
- `scripts/astc_backfill.py`：.astc 回填 assets 并删已压缩 .png；零替换即报错。
- `source/backend/Paths.hx`：
  - inst/voices 接 AudioPreload.take（预载命中直接注册缓存）。
  - cacheBitmap 大图 GPU 化：解码 ≥2MB 上传 GL 后丢 CPU 副本（不受 cacheOnGPU 开关影响）。
- `source/backend/AudioPreload.hx`（新）：选歌预载。后台线程 Sound.fromFile 纯解码（不碰全局缓存零竞态），Mutex 保护 ready 表，过期结果丢弃，最多驻留一首。
- `source/states/PlayState.hx`：
  - **谱面窗口化**：chartTimes 等平行数组 + chartIdx 索引推进（8 秒窗口），makeChartNote 逐行实例化（sustain 链/chartStepCrochet 快照对齐原版）。
  - **音画对齐**：update 积分后 |music.time - songPosition|>50ms 硬对齐（根治全 shit）。
  - clearNotesBefore 同步 chartIdx；结束扣血补数据层；destroy 销毁 vocals/inst/opponentVocals。
  - popUpScore/noteMissCommon 挂 PerfProbe.onJudge（直方图，botplay 不计）。
- `source/backend/PerfProbe.hx`：内存分解（readable 区分 GPU 化）、rss 流式读（/proc size=0 坑）、drift/rate 监控、判定直方图、段小结、启动头（build.prop 方案）、中文短名。
- `source/states/FreeplayState.hx` + `MainMenuState.hx`：create 加 clearStoredMemory+clearUnusedMemory+SONG=null（退出打歌释放残留）。
- `source/backend/Paths.hx` clearStoredMemory：localTrackedAssets 重置提前（原顺序导致声音永远清不掉）。
- `source/backend/MusicBeatState.hx`/`MusicBeatSubstate.hx`：addMobileControls 支持 cameraOverride + hitboxCamOwned 标志。
- `source/mobile/backend/PauseButton.hx`：复用 camOther。
- `source/substates/PauseSubState.hx`：虚拟手柄版（触控已撤销），手柄直接挂 pageCam。

## 6. 用户否决清单（永远别重做）

1. **startOnTime**（已回退）。
2. **安卓设置功能**（已回滚）。
3. **暂停页触控**（#69 做过，体验不佳，#74 回退虚拟手柄）。
4. **辉光效果**（糊）。
5. **日志过度美化**（⚡▼⊞════ 装饰 + 中文伪对齐被否；现用中文短名 + 轻分隔 `--- 状态: X ---` + 双空格）。
6. **mod 批量 ASTC 转换**（只按需转换单个 mod；工具在 astctool/）。
7. **GPU 缓存全局默认开**（保留用户开关；≥2MB 自动 GPU 化已覆盖需求）。

## 7. 待办 / 待验证

1. **Unable-V2 判定复测**（音画对齐后的手感确认——drift 应 ±20ms）。
2. 启动头设备行缺失（build.prop 在用户设备读取失败，换数据源如 /system/etc/prop.default 或 JNI lime.system.JNI）。
3. 段小结判定归属跨段（打歌判定算进选曲段小结）——小修。
4. Freeplay 页面用户详细反馈（老待办）。
5. judgeCompensation 手感确认（老待办）。
6. 贴图清理：mainmenu/menu_*.png 7 个图集可删；menuDesat 不能删（老待办）。
7. 旧设置子页面 MD3 化（老待办）。
8. 可选：targetSdk 35/36（上 Play 商店才需要）。
9. 40 万谱 Dynamic 常驻（SONG.notes static 化）——仅极端谱需要。

## 8. 经验教训（新增）

1. **音画 100ms 固定偏差**：PlayState 谱面时钟是纯积分，与音频时钟存在固定起点差（本机实测 ~100ms）→ 音符视觉晚到 → 按音频打全 shit。修法：50ms 死区硬对齐。**别再用纯积分不对齐的时钟**。
2. **clearStoredMemory 顺序**：localTrackedAssets 重置必须在声音清理之前，否则上状态的 Inst/Voices 永远清不掉。
3. **音频对象挂全局 FlxG.sound.list**：状态销毁不会自动释放，必须显式 remove+destroy（PCM/AL 缓冲）。
4. **/proc 文件 size=0**：lime 的 getContent 按大小读会得到空串 → 必须用 FileInput.readAll() 流式读。
5. **lime.utils.JNI 不存在**（本 lime-modified）：设备信息改读 /system/build.prop 或 lime.system.JNI。
6. **ASTC excludes 路径必须与实际目录一致**（mobile/images/virtualpad 教训——少一层 images 导致手柄贴图被误压删）。
7. **手柄贴图不走 Paths.image**（直接拼路径 BitmapData.fromFile），ASTC 排除表必须覆盖它们。
8. **SOUND_EXT 等静态字段跨类必须 Paths.SOUND_EXT**；getPath 的 TEXT 参数可省略。
9. **/proc/meminfo 等流式读**的 readProcFile/readPropLine 辅助已就绪。
10. **后台线程解码音频**（Sound.fromFile）可行且安全（OpenAL buffer 与 context 无关），但**绝不要在后台线程碰 Paths 全局缓存 Map**（竞态）。
11. 括号校验器必须字符串/注释/插值感知（§2.3）。
12. GitHub Artifacts API 用数据库 id 不是 run_number；/logs 302 跟随时不带 auth。
13. **旧版 Psych 全量实例化音符 + splice/remove 是 O(n²)**：窗口化后 40 万谱可用；sustain 间距必须用构建期 stepCrochet 快照。

## 9. 布局速查（继承旧版，未变）

- 暂停面板：左菜单 36,80,520,360；右信息 572,80,672,360；行 x=56 w=480 h=40 pitch=44 首行 y=118；开关 x=456；◀▶ x=360/398；提示 y=688。
- 玩法调整子状态：行 cy=96+i×62 h=52；开关 x=1120；◀▶ x=1080/1160；数值 x=830 w=230。
- FPS 显示器：三行文字+三图，图 100x30，行距 18+3。

## 10. 用户偏好

- **全程中文**；喜欢猫娘元素（Botplay=「猫娘替你打喵」）。
- 大改动前先给设计/方案说明，认可再动手；小失败容忍度高，快速迭代。
- 会提供截图和导出的性能日志；给结论要具体（数字/坐标/文件行号）。
- **日志风格**：中文短名 + 轻分隔（`--- 状态: X ---`）+ 双空格；拒绝花哨装饰与伪对齐。
- token 不落盘；不用模糊匹配杀进程；不碰设备策略红线。
- GPU 缓存全局开关保持默认关（≥2MB 自动 GPU 化已覆盖）。

## 11. 新对话开场建议

1. 读本文档 → 2. 查最新 Run 状态与用户测试反馈 → 3. 按待办 §7 继续。
- 用户测试日志导出到 `/sdcard/网页开发/perf_log.txt`（每次覆盖）。
- 监控构建：轮询 `actions/runs?per_page=1` 的 status（用户要求"编译时监控"）。
