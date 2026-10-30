# NekoEngine 交接文档（新对话用）

> 更新：2026-10-30 · 远端 master = `b68d5118`（Run #117 构建中：lua 音效后台预载+首载诊断+探针口径）
> 阅读本文件后即可接手，无需翻旧对话。

## 1. 项目概述

- **NekoEngine**：Psych Engine 0.7.3 的安卓手机移植版（FNF 改引擎）。
- 技术栈：HaxeFlixel 5.5.0 + lime-modified + hxcpp（FunkinCrew fork ref 5932340d）。
- 仓库：`MuXue-Ya/NekoEngine`（**公开仓库**，第三方 mod 素材勿推）。上游参考 RenTheSylvee/FNF-PsychEngine-0.7.3-Mobile。
- 构建方式：GitHub Actions（`MainBuild.yml`），推 master 自动触发；**源码变了全量编 ~20 分钟，只改资产/文档命中 obj 缓存 ~8 分钟**（#98 精确 key：源变必 miss 全量重编保证正确性）；产物名 `NekoEngine-Android`。
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
- 简单花括号计数会**误报**（Paths.hx 有骗过检查器的模式）。必须用**字符串感知 + 注释感知 + `${}` 感知 + 正则感知**的解析器。
- 校验器已落盘：`tools/check_haxe.py`（对已构建成功版本跑基线应全 OK；`${}` 插值结束的 `}` 要回字符串模式，勿当不配对）。
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

## 3. 当前状态（2026-10-27）

### 3.1 仓库
- master = `f5d86183`。#102 长箭头断缝修复；#103 icon 间距已撤回；#105 恢复误删的 data 根级文件(introText 等 5 个)；#106 窗口化兼容(旧式 mod lua 兜底)。
- 构建成功率历史：#84(JNI)、#86(SOUND_EXT)、#91(removeByKey) 失败过，其余全绿；#89 仅文档。

### 3.2 性能现状（2026-10-27 Duality-VIP 整曲实测，567 判定/214s）
- **进歌 16.5s 链路分解**：SONG 就绪 +0.6s → generateSong +5.0s（**4.4s = gf/dad/bf 三个 Character 构造**）→ 解码完 +6.6s → 谱面 +6.6s → create 完成 +16.5s（**10s = 舞台/UI 贴图 + 20+ 个 lua 脚本加载**）→ 批次 B 目标明确。
- **GC 风暴 = 中盘掉帧主因**：打歌 385 次 GC/214s（0.4~1.1s/次，分配率 10~20MB/s），暂停中位 21ms / P90 43ms / 峰 218ms；≥40ms 尖帧 172 次 ≡ GC P90。fps 65(前段)→39(后段) 随堆 285→452MB 劣化 → **批次 C 提级**。
- **中盘贴图尖峰**：59.4s 尖帧 1667ms；168.5s 堆内贴图 116→211MB(+95MB)——角色换装一次性加载，批次 B 证据。
- 判定：总均差 +9~10ms，正偏 72%，无 UnableF-mix 旧日志的 -20~-40ms 系统漂移 → 判定复测收口。
- 打歌堆峰 452MB / rss 峰 2031MB（5GB 机器）；退出清理正常（GC -379MB 回落 72.8MB）。
- fps：用户 61Hz 屏，锁 60 打；不锁时 123 满帧。
- **2026-10-29/30 多模组对照结论**：deathmatch(1834行) 全曲分配≈0MB/s、GC 仅 3 次——**引擎本体分配极干净**；Duality-VIP 的 30MB/s 分配与 GC 风暴 = 其 mod lua（每帧遍历 notes 组+打歌中动态加载）。打歌中周期性 +32~63MB 大尖帧 = **换装/特效大图整张同步解码瞬态**（80-156ms/次，死缓冲等 GC 回收呈阶梯）。Infraction(他机 120Hz/11GB)：音轨 1→8 波动、四次 1.5-4s 卡顿=动态音轨解码，42 miss 中 39 个来自两次卡顿。稳态(fps/判定/draw)在所有 mod 上均健康。
- 弹出动画最终态 = **粘性弹出**(#112 内容)：击中原地刷新+Q弹+池化；倾斜/乒乓球实验已回退。

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
| #89 | 677a6633 | ✅ | 仅交接文档同步（docs/HANDOVER.md，无源码）|
| #90 | 200e8aa4 | ✅ | 批次A：大图GPU化降采样 + 事件索引化 + 音频PCM估算 |
| #91 | 9453c117 | ❌ | hotfix 一修：FlxG.bitmap.remove() 编译错（应 removeByKey）|
| #92 | 34af57ea | ✅ | hotfix 二修：图集用途禁止降采样（fromAtlas 全链路）|
| #93 | 516ef318 | ✅ | 还原：Paths.hx 回 #88（无降采样）+ 音频估算单位修正；**降采样永久否决** |
| #94 | ba1b6062 | ✅ | 删原版周目(保留教程, 资产-224MB) + 进歌耗时分解 + AudioPreload 进歌取消 |
| #95 | ad527b95 | ✅ | CI：hxcpp obj 编译缓存首跑（保存缓存）|
| #96 | bf285572 | ❌ | git 层面删周目资产(392文件)但 Project.xml week_assets 悬空声明漏清 → Compile 0s 失败 |
| #97 | 2799df95 | ✅ | Project.xml 移除 week_assets 声明(2 assets + 1 library)；周目删除首次生效 |
| #98 | e0fec91d | ✅ | CI 修正：obj 缓存精确 key + obj touch 未来(#97 实测 mtime 归一对 haxe 生成物无效) |
| #99 | 5ea2cb46 | ✅ | 平滑血条(玩法开关) + 图标挤压源码化(挤压.lua 移植, 恒开) |
| #100 | 5250f2c6 | ❌ | 双振荡器改造：resetIconsSquash 漏改数组下标(Float+Array 编译错) |
| #101 | dccf0947 | ✅ | 图标挤压双振荡器：对手档位按互补血量(玩家100%=对手0血用惨状档), miss 静止保持双停 |
| #102 | 42e17411 | ✅ | 长箭头断缝修复：窗口化批量生成后补 unspawnNotes.sort(sortByTime)（原版有, 窗口化漏了）|
| #103 | 83bc0175 | ✗ | icon 间距实验包：已取消并 force 回退（iconSpread 撤回, 本地已同步还原）|
| #105 | 92a15559 | ✅ | 恢复误删 data 根级文件(introText/characterList/stageList/specialThanks/main-view.xml)——修标题崩溃；**obj 缓存首次兑现：源码不变构建 184s** |
| #106 | f5d86183 | ✅ | **窗口化兼容**：带 custom_notetypes/custom_events 脚本且谱面 ≤4000 行时，脚本加载前按原版全量实例化——修复旧式 onCreate 遍历 unspawnNotes 的箭头/事件 lua 全部落空（GF Sing/Duality-MomNote/Shoot Note 等）；新增 noteScriptExists()。全量构建 27.5min |
| #107 | cc97937a | ✅ | 仅交接文档同步（docs/HANDOVER.md 补齐 #94-#106）；obj 缓存兑现：仅文档构建 ~4 分钟 |
| #108 | af4817d9 | ✅ | **批次E+归因+B1**：GC 调参(setMinimumFreeSpace 48MB+target 40%) / PerfProbe 分配速率行 / create 细分打点 / vocals 后台并行解码(1.55s→0.8s) |
| #109 | 8c8718ea | ✅ | 评分弹出随机倾斜 ±15°（视觉实验一）|
| #110 | 6a2b7b9a | ❌ | Q弹+池化：flixel 5.5.0 无 FlxTween.killTweensOf，4 处编译错 |
| #111 | 4f210119 | ✅ | hotfix：tween 登记表(regPopupTween/killPopupTweens)替代 killTweensOf |
| #112 | f6a6675a | ✅ | **粘性弹出**：击中原地刷新+Q弹脉冲，停手 600ms 淡出；池化落地(popUpScore 零 new/destroy) |
| #113 | 3d1a64f5 | ✅ | 乒乓球弹跳+允许堆叠（视觉实验三）|
| #114 | 80b98386 | ✅ | **回退至 #112 内容**(blob 6bd5bd7d)——乒乓球/倾斜实验取消，粘性弹出为最终态 |
| #115 | 65970d7e | ✅ | **窗口化补帧限流** CHART_REFILL_CAP=24/帧 + 谱面数据段归因打点(事件加载完/谱面平铺完) |
| #116 | cf9fdfbe | ✅ | 音画对齐死区 50→25ms（漂移 -6~-35ms 缓慢游走，最坏视音偏移减半）|
| #117 | b68d5118 | ⏳ | **lua 音效后台预载**(LuaSoundScan) + 打歌中首载诊断([首载] 行) + 探针口径修复(段标签/按段重置) |

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

**批次A（#90，200e8aa4）**：
- `source/backend/Paths.hx`：GPU 化前降采样兜底——面积 >2048²(16MB GL) 的图等比缩到 2048² 内再上传（4096² RGBA=67MB/张，安卓统一内存下 GL 纹理计入 rss）；新增 `gpuScaledCount` 计数，clearStoredMemory 重置。
- `source/states/PlayState.hx`：checkEventNote 的 shift O(n) 改 `evtIdx` 索引推进（同 chartIdx 模式）；KillNotes 同步 `evtIdx=0`。
- `source/backend/PerfProbe.hx`：内存分解行新增 `缩图=N` 与 `音频=N轨/~YMB`（44.1kHz/16bit/立体声 ≈176.4B/ms 估 PCM 驻留，遍历 FlxG.sound.music + FlxG.sound.list 的 Sound.length）。

**还原（#93，516ef318）**：
- `source/backend/Paths.hx` 原样恢复 #88（blob 43227c50，无任何降采样）；PerfProbe 删 `缩图=` 字段 + 修音频估算单位（0.1764 忘除 1048576，68755MB 实为 ~66MB，现 0.00016822）。

**周目删除 + 进歌优化（#94，ba1b6062）**：
- 资产删除：`assets/songs/` 22 首(-186MB)、`week_assets/` week1-7(-38MB)、`shared/data/` 24 个谱面目录、`weeks/` week1-7.json；`weekList.txt` 只留 tutorial。**保留** `shared/images/characters`（mod 复用基础角色）与 tutorial 全套。
- `astc-compression-data.json` 清理 week1/week6weeb 条目（源文件已删，防 backfill 报错）。
- `AudioPreload.cancel()`：worker 判断加 `want.length>0` 防死循环；PlayState.generateSong 开头调用——进歌时停后台预载线程，主线程独占音频解码。
- `PerfProbe.loadMark/loadMarkReset`：进歌全链路 7 个打点（选曲点歌→JSON解析完→SONG就绪→generateSong 开始→inst/voices 解码完→谱面数据构建完→create 完成），Freeplay/Story/直进三条路径都覆盖。
- **进歌变长归因**：主因=#90/#92 降采样的纯 CPU 缩放（13 张大图 × 数百 ms，已随 #93 还原）；次因=AudioPreload 竞争（#94 cancel 解决）。

**CI 编译缓存（#95 试错 → #98 定稿，仅 .github）**：
- MainBuild.yml：缓存 `export/release/android/obj`；**精确 key** `hashFiles(source/**/*.hx, Project.xml, hmm.json)`，**无 restore-keys 前缀兜底**（源变必 miss 全量重编，杜绝旧产物挡新代码）；恢复后 **obj 整体 touch 未来 +6h**（haxe 生成 cpp 的 mtime=now 恒新于缓存 obj，touch Haxe 源无效——#97 实测教训）。
- **#105 实测兑现：源码不变的构建 20 分钟 → 184 秒**；改源码的构建照旧全量 ~20 分钟（正确性优先）。

**平滑血条 + 图标挤压（#99-#101，5ea2cb46→dccf0947）**：
- `source/backend/ClientPrefs.hx`：gameplaySettings 加 `'smoothhealth' => true`（自动持久化）。
- `source/substates/GameplayChangersSubstate.hx`：新增「平滑血条」bool 行（默认开；旧存档无键视为开）。
- `source/states/PlayState.hx` 平滑血条：`healthBar.valueFunction = () -> smoothHealth`（Bar.bound 兜住溢出）；update 内脚本公式追踪（除零/NaN 保护）；判定/死亡仍用真实 health。
- `source/states/PlayState.hx` 图标挤压（挤压.lua 源码化，恒开无开关）：**双振荡器** P1/P2 各自独立（t/amp/freq/damp/swing/restOffset），**对手档位按互补血量**（玩家 hp=health*50，对手 hp=100-health*50——玩家满血时对手用惨状档）；三档参数与 Lua 逐项一致（>80 高频振荡+旋转 / <20 深压+swing+下坠7px / 中段 0.30）；每拍各自起振；miss 静止双停（接住解除/破 20% 自动解除）；updateIconsScale 原版弹跳被替代（动态钩子保留供 mod 覆盖）；挤压在 updateIconsPosition 之后执行（x 由原版定位管理，swing 直接叠加不累积）。
- 曾试 icon 各外移 16px(#103)：**用户要求撤回**，间距回原版（后续按 8/10/16px 档位待用户测试后再定）。

**长箭头断缝修复（#102，42e17411）**：
- `source/states/PlayState.hx`：窗口化批量生成循环后补 `unspawnNotes.sort(sortByTime)`——sustain 链 piece 的 strumTime 跨越后续行本体时间，队列乱序使 spawn 循环（只看队头）被"未来" piece 卡住 → 后续行延迟出现 → 长箭头之间断缝。原版全量生成后本就有此排序，窗口化改造时漏带。

**误删恢复（#105，92a15559）**：
- 恢复 `assets/shared/data/` 根级 5 文件：introText.txt（**标题随机文案，崩溃源**：TitleState.beatHit case 10 curWacky[0] 空引用）、characterList.txt、stageList.txt、specialThanks.txt、main-view.xml。本地源码树一直都在，仅远端 git 缺失（#96 前缀规则误删）。

**窗口化兼容（#106，f5d86183）**：
- 症状：duality-vip mod 的特殊箭头（GF Sing 247/Duality-MomNote 113/Shoot Note 56 根）lua 全部失效，表现为"无法识别箭头 lua"。根因：旧式 mod 脚本在 `onCreate`（FunkinLua 构造时立即执行）遍历 `unspawnNotes`——原版 generateSong 全量实例化后脚本才加载所以能看到全部；#76 窗口化下 create 阶段 unspawnNotes 为空数组，属性设置全部落空。
- 修法（引擎侧，用户拍板）：`source/states/PlayState.hx` 在自定义音符类型/事件脚本加载**之前**插入检测——本谱存在 `custom_notetypes/<type>.lua|.hx` 或 `custom_events/<event>.lua|.hx` 且 `chartTimes.length <= 4000` 时，走 `makeChartNote` 循环一次性全量实例化 + `unspawnNotes.sort(sortByTime)`，完整复现原版语义；无脚本谱面与超大谱（40 万谱）仍走窗口化零影响。
- 新增 `noteScriptExists(relPath)`：存在性判断与 startLuasNamed 同款（Paths.modFolders 优先 → getSharedPath 回退）。
- 代价：带脚本谱面常驻全量音符（本谱 ~2000 行多占几十 MB 堆）。附带收益：`data/<song>/` 里 onCreate 遍历式的谱面数据脚本同样被覆盖。
- 受影响文件：仅 `source/states/PlayState.hx`（+48 行）。mod 侧脚本未动。

## 6. 用户否决清单（永远别重做）

1. **startOnTime**（已回退）。
2. **安卓设置功能**（已回滚）。
3. **暂停页触控**（#69 做过，体验不佳，#74 回退虚拟手柄）。
4. **辉光效果**（糊）。
5. **日志过度美化**（⚡▼⊞════ 装饰 + 中文伪对齐被否；现用中文短名 + 轻分隔 `--- 状态: X ---` + 双空格）。
6. **mod 批量 ASTC 转换**（只按需转换单个 mod；工具在 astctool/）。
7. **GPU 缓存全局默认开**（保留用户开关；≥2MB 自动 GPU 化已覆盖需求）。
8. **帧率跟随刷新率**（用户固定设 120 帧，不要动帧率逻辑；#90 起记录）。
9. **贴图降采样/缩放——永久否决（不分人物/背景/任何图）**（#90 事故：角色图集缩放后 Sparrow XML 帧坐标错位满屏碎片；#92 fromAtlas 修复后背景仍错位，用户「全部还原」——#93 Paths.hx 已回 #88。后续任何优化一律不碰贴图像素内容与尺寸，GPU 化原尺寸上传保持 #88 原状）。
10. **mod 贴图压缩（ASTC 等）——红线（2026-10-30 用户明示）**："不能动的就是贴图压缩，要不然又识别失败"。mod 人物/背景贴图一律不转换不压缩；引擎自带资产的 ASTC 管线不受影响。mod lua 脚本允许修改（用户授权"mod 动不动随便你"）。

## 7. 待办 / 待验证

0. **装 Run #117+ 实测（两台机）**：① deathmatch 验证补帧限流（基线 fps均=40/尖帧158 → 目标 55+）② Infraction 验证 lua 音效后台预载（音轨 1→8 波动的 1.5-4s 卡顿应消失，miss=42 应个位数）③ Duality 打一首看 `[首载]` 行点名 32MB 阶梯资源 ④ 粘性弹出+池化手感确认。
1. ~~进歌耗时复测~~ **已收口**（#108 打点：Duality 16-19.8s = gf 3.9-4.9s + HUD 5.3s + lua 3.2s + 预载 3.8s + 解码 0.8-2.8s；deathmatch 另有谱面数据段 5.8-8.6s 待 #115 打点定位）。
1b. **icon 间距**：暂缓（用户测试其他 mod 后再定，档位 8/10/16px 已备，16px 包 #103 已取消）。
2. **批次 B：进歌分帧预载**（打点数据已到手：4.4s = gf/dad/bf Character 构造，10s = 舞台/UI/lua 脚本；另中盘角色换装 +95MB/1667ms 尖峰同属此批）。
3. **批次 C：popUpScore 池化**（**已提级**：GC 风暴实测 0.4~1.1s/次、P90 43ms ≡ 172 次尖帧，是当前唯一压制 fps 因素；另注：mod lua 每帧遍历 notes 组也是分配源，如 charDance.lua onUpdatePost）。
4. **批次 D：mod 大图 ASTC 清单**（扫 >2MB 非 excludes PNG 出清单，用户挑着转 6x6，astctool 就绪）。
5. ~~判定复测~~ **已收口**（Duality-VIP 实测总均差 +9~10ms，无系统性漂移；UnableF-mix 旧问题未复现）。
6. 启动头设备行缺失（build.prop 在用户设备读取失败，换数据源如 /system/etc/prop.default 或 JNI lime.system.JNI）。
7. 段小结判定归属跨段（打歌判定算进选曲段小结）——小修。
8. Freeplay 页面用户详细反馈（老待办）。
9. judgeCompensation 手感确认（老待办）。
10. 贴图清理：mainmenu/menu_*.png 7 个图集可删；menuDesat 不能删（老待办）。
11. 旧设置子页面 MD3 化（老待办）。
12. 可选：targetSdk 35/36（上 Play 商店才需要）。
13. 40 万谱 Dynamic 常驻（SONG.notes static 化）——仅极端谱需要。

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
14. **rss 大头不在 hxcpp 堆**（实测堆 227MB vs rss 1077MB）：安卓统一内存下 GL 纹理计入 RSS——GPU 化省堆不省 RSS，4096² RGBA=67MB/张 → **降采样/ASTC 才是 RSS 解药**；音频 PCM 在 native（估 176.4B/ms）。进歌瞬时尖峰 = 全部大图「解码 RGBA + 上传 GL」双份时间窗。
15. **APK 版本核对**：日志版式可判版本（⊞=旧版，`内存分解 …=…` = #88+）；分析性能前先确认用户手机跑的是哪个包，避免基于过期数据下结论。
16. **git 层面删文件 ≠ 本地 rm**：#94 只推了代码, 资产删除未进 git(#94 漏提交) → 必须 tree 快照/显式条目删除；**删目录时根级散文件**(data/introText.txt 等)必须逐一核对——#105 标题崩溃即 introText 误删。
17. **hxcpp obj 缓存正确姿势**(#98/#105)：精确 key(source+Project.xml+hmm.json hash)、obj 整体 touch 未来、**无 restore-keys 前缀兜底**（防旧产物挡新代码）；haxe 生成 cpp 的 mtime=now 恒新于缓存 obj，touch Haxe 源无效。源码不变构建 20min→3min。
18. **窗口化生成后必须 unspawnNotes.sort(sortByTime)**(#102)：sustain 链 piece 跨越后续行时间, 队列乱序会让 spawn 循环(只看队头)卡住 → 长箭头断缝/音符延迟。
19. **窗口化 vs 旧式 mod lua**(#106)：mod 脚本在 `onCreate`（FunkinLua 构造即执行）遍历 `unspawnNotes` 是旧版 Psych 的隐含契约（那时全量实例化先于脚本加载）；窗口化打破该契约 → 特殊箭头/事件 lua 静默失效（无报错，难排查）。引擎侧兜底：检测到 custom_notetypes/custom_events 脚本且谱面 ≤4000 行就回退全量实例化。新写 mod 脚本应改用 `onSpawnNote` 钩子（引擎每根箭头实例化时都回调，窗口化下也正确）。
20. **flixel 5.5.0 无 FlxTween.killTweensOf**(#110)：静态门面只有 completeTweensOf；需杀 tween 时自建登记表(对象→tween 数组)+逐个 cancel，且只 cancel active 的(防 onComplete 内重入)。顺带修掉延迟 tween 复用后误触发的隐患。
21. **Haxe 闭包捕获循环变量是共享的**：`for (x in arr) push(function() use x)` 所有闭包看到最后一个 x——循环体内 `var cur = x;` 重新声明才是按次捕获。
22. **/sdcard 上 write 工具新建文件报 EINVAL**(原子发布不支持)：新文件用 bash heredoc `cat >` 创建；git trees API 对大仓库返回截断——按路径取文件用 contents API(`?ref=sha`)。
23. **外部 AI 分析(DeepSeek/元宝)要核验后再动手**：两份报告都有误读——元宝把 `谱面实例化完(兼容路径按需)` 打点当成了卡顿根因(实际是 #106 全量实例化的耗时记录)，其"池化 1317 行"方案=legacyFill 已做的事。共见结论才可信：稳态健康、突发大块工作(资源同步解码)是主要矛盾。
24. **多设备测试**：用户有两台机(5GB/61Hz + 11GB/120Hz)，日志头看设备行；#115 前的包没有 补帧限流/归因打点，旧包日志缺新打点属正常。

## 9. 布局速查（继承旧版，未变）

- 暂停面板：左菜单 36,80,520,360；右信息 572,80,672,360；行 x=56 w=480 h=40 pitch=44 首行 y=118；开关 x=456；◀▶ x=360/398；提示 y=688。
- 玩法调整子状态：行 cy=96+i×62 h=52；开关 x=1120；◀▶ x=1080/1160；数值 x=830 w=230；**新增「平滑血条」行**（Botplay 之后，行序自动排）。
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
