package backend;

import haxe.Timer;
import flixel.FlxG;
import flixel.FlxState;
import flixel.graphics.FlxGraphic;

#if sys
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;
#end

/**
 * 轻量性能探测点:
 *   - 钩住 preUpdate/postUpdate/preDraw/postDraw 信号, 分段测量每帧"更新/绘制"耗时
 *   - 按秒汇总: 真实fps / 更新均值与峰值 / 绘制均值与峰值 / GC次数
 *   - 尖帧(>40ms)逐条记录(每秒最多10条, 防刷屏)
 *   - GC 事件由 FPSCounter 回调, 带当帧耗时
 *   - 状态切换逐条记录
 * 日志: <StorageSystem目录>/debug/perf_log.txt, 每次启动重建, 超过1MB在下次启动时截断。
 * 全程原生计时(haxe.Timer.stamp), 无每帧堆分配; 每约2秒批量落盘一次。
 * 注意: 固定步长模式下 preUpdate 每逻辑步触发一次, frameMs 为步间隔; 帧数补偿开启时=真实帧间隔。
 */
class PerfProbe
{
	public static var enabled:Bool = true;

	static var lastPreMs:Float = -1;	// 上一帧 preUpdate 时间戳
	static var updStartMs:Float = 0;	// 更新段开始
	static var drawStartMs:Float = 0;	// 绘制段开始
	static var frameMs:Float = 0;		// 当前帧(步)总耗时

	static var secFrames:Int = 0;
	static var updSum:Float = 0;
	static var updMax:Float = 0;
	static var drawSum:Float = 0;
	static var drawMax:Float = 0;
	static var secStartMs:Float = 0;
	static var gcSec:Int = 0;
	static var spikeSec:Int = 0;

	static var lastStateRef:FlxState = null;
	static var segLabel:String = '';	// 当前段的标签(进入该状态时的短名, 修复段小结 off-by-one)
	static var startMs:Float = 0;

	static var buffer:Array<String> = [];
	static var out:FileOutput = null;
	static var filePath:String = null;
	static var summariesSinceFlush:Int = 0;
	static var lastBreakMs:Float = -100000;
	// D1: 内存分解(贴图缓存遍历+/proc 读取)开关, 默认关避免周期性尖帧
	public static var memBreakdown:Bool = false;
	// 供 FPS 卡片显示的上一秒平均更新/绘制耗时(ms)
	public static var lastUpdAvg:Float = 0;
	public static var lastDrawAvg:Float = 0;

	// 段级聚合(状态切换时输出小结) + 全场累计
	static var segStartMs:Float = 0;
	static var segFrames:Int = 0;
	static var segMemPeak:Float = 0;
	static var segJudgeN:Int = 0;
	static var segJudgeSum:Float = 0;
	static var segJudgeMiss:Int = 0;
	static var gcTotalMB:Float = 0;
	static var gcTotalCnt:Int = 0;
	static var spikeTotal:Int = 0;
	static var spikeMaxMs:Int = 0;

	// 分配速率(批次E 归因): GC 回收量 + 堆增量 反推每秒分配(MB/s)
	static var lastAllocUsageMB:Float = -1;
	static var lastAllocMs:Float = 0;
	static var gcFreedAccumMB:Float = 0;
	static var allocSegMB:Float = 0;
	static var allocSegSecs:Float = 0;

	public static function init():Void
	{
		#if (sys && mobile)
		try
		{
			var dir:String = mobile.backend.StorageSystem.getDirectory() + '/debug';
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			filePath = dir + '/perf_log.txt';
			File.saveContent(filePath, '');	// 每次启动重建, 一份日志对应一次运行
			push('=== PerfProbe 启动 ===');
			pushBootInfo();
			
			flush();
		}
		catch (e:Dynamic)
		{
			filePath = null;
			enabled = false;
		}
		#end
	}

	// 启动头: 设备/系统/屏幕/内存/引擎, 以后日志一眼认出环境
	static function pushBootInfo():Void
	{
		// 设备信息走 /system/build.prop(普通文件全 Android 可读), 不依赖 JNI
		try
		{
			var prop:String = readProcFile('/system/build.prop');
			var model:String = readPropLine(prop, 'ro.product.model');
			var market:String = readPropLine(prop, 'ro.product.marketname');
			var ver:String = readPropLine(prop, 'ro.build.version.release');
			var line:String = '设备: ' + ((market != null && market.length > 0) ? market : model);
			if (ver != null && ver.length > 0) line += '  |  Android ' + ver;
			push(line);
		}
		catch (e:Dynamic) {}
		try
		{
			var w:Int = FlxG.stage.application.window.width;
			var h:Int = FlxG.stage.application.window.height;
			var hz:Float = FlxG.stage.application.window.displayMode.refreshRate;
			push('屏幕: ' + w + 'x' + h + ' @' + Math.round(hz) + 'Hz');
		}
		catch (e2:Dynamic) {}
		try
		{
			var mi:String = readProcFile('/proc/meminfo');
			var idx:Int = mi.indexOf('MemTotal:');
			if (idx >= 0)
			{
				var endIdx:Int = mi.indexOf('kB', idx);
				var kb:Float = Std.parseFloat(mi.substr(idx + 9, endIdx - idx - 9));
				if (!Math.isNaN(kb) && kb > 0) push('总内存: ' + Math.round(kb / 1048576) + 'GB');
			}
		}
		catch (e3:Dynamic) {}
		push('引擎: Psych Engine 0.7.3 (NekoEngine 安卓移植)');
	}

	// ===== 每帧钩子(由 Main.hx 注册到 FlxG.signals) =====

	public static function onPreUpdate():Void
	{
		if (!enabled) return;
		var now:Float = Timer.stamp() * 1000;
		if (startMs <= 0) startMs = now;
		if (secStartMs <= 0) secStartMs = now;
		if (segStartMs <= 0) segStartMs = now;

		if (lastPreMs > 0)
		{
			frameMs = now - lastPreMs;
			if (frameMs > 40 && frameMs < 5000 && spikeSec < 10)
			{
				push('[' + fmt(now) + '] ⚡尖帧 ' + Math.round(frameMs) + 'ms @' + shortState(curStateName()));
				spikeSec++;
				spikeTotal++;
				if (Math.round(frameMs) > spikeMaxMs) spikeMaxMs = Math.round(frameMs);
			}
		}
		lastPreMs = now;
		updStartMs = now;
		secFrames++;

		// 状态切换检测(按引用比较, 零分配)
		var st:FlxState = FlxG.state;
		if (st != lastStateRef)
		{
			if (lastStateRef != null) pushSegSummary(now);
			if (lastStateRef != null) push('--- 状态: ' + shortState(curStateName()) + ' ---');
			lastStateRef = st;
			segLabel = shortState(curStateName());	// 本段标签 = 刚进入的状态(修复段小结 off-by-one)
		}

			// 按秒汇总
		if (now - secStartMs >= 1000)
		{
			var sec:Float = (now - secStartMs) / 1000;
			var updAvg:Float = updSum / Math.max(1, secFrames);
			var drawAvg:Float = drawSum / Math.max(1, secFrames);
			// 供 FPS 卡片显示(每秒刷新)
			lastUpdAvg = updAvg;
			lastDrawAvg = drawAvg;
			var memLine:String = '';
			#if cpp
			// 内存分解: 实用(真数据) / 堆总量(实用+空闲+垃圾), 差值即 GC 策略的代价
			var usageMB:Float = Math.round(cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE) / 104857.6) / 10;
			var rsvMB:Float = Math.round(cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_RESERVED) / 104857.6) / 10;
			memLine = ' mem=' + usageMB + '/' + rsvMB + 'MB';
			// 分配速率: (GC回收 + 堆净增量)/时长 —— 尖帧归因的关键曲线
			if (lastAllocUsageMB >= 0)
			{
				var dt:Float = (now - lastAllocMs) / 1000;
				if (dt > 0.2)
				{
					var allocMB:Float = gcFreedAccumMB + (usageMB - lastAllocUsageMB);
					if (allocMB < 0) allocMB = 0;
					memLine += ' 分配=' + Math.round(allocMB / dt) + 'MB/s';
					allocSegMB += allocMB;
					allocSegSecs += dt;
				}
			}
			lastAllocUsageMB = usageMB; lastAllocMs = now; gcFreedAccumMB = 0;
			#end
			// 判定直方图(本秒玩家击中偏差分布)
			var judgeLine:String = '';
			if (judgeCount > 0)
			{
				var jAvg:Float = judgeSum / judgeCount;
				judgeLine = ' 判定=' + judgeCount + ' 均差=' + (jAvg >= 0 ? '+' : '') + Math.round(jAvg)
					+ 'ms 准=' + judgeBuckets[2] + ' 早=' + (judgeBuckets[3] + judgeBuckets[4])
					+ ' 晚=' + (judgeBuckets[1] + judgeBuckets[0]);
				if (judgeMissCount > 0) judgeLine += ' miss=' + judgeMissCount;
			}
			else if (judgeMissCount > 0) judgeLine = ' 判定miss=' + judgeMissCount;

			push('[' + fmt(now) + '] ' + shortState(curStateName())
				+ '  fps=' + Math.round(secFrames / sec)
				+ '  upd=' + r1(updAvg) + 'ms(峰' + r1(updMax) + ')'
				+ '  draw=' + r1(drawAvg) + 'ms(峰' + r1(drawMax) + ')'
				+ '  GC=' + gcSec + memLine + allocLine() + driftLine() + judgeLine);

			// 段级累加(清零前)
			segFrames += secFrames;
			#if cpp
			if (usageMB > segMemPeak) segMemPeak = usageMB;
			#end
			segJudgeN += judgeCount;
			segJudgeSum += judgeSum;
			segJudgeMiss += judgeMissCount;

			secFrames = 0; updSum = 0; updMax = 0; drawSum = 0; drawMax = 0;
			gcSec = 0; spikeSec = 0;
			judgeCount = 0; judgeMissCount = 0; judgeSum = 0;
			for (i in 0...judgeBuckets.length) judgeBuckets[i] = 0;
			secStartMs = now;
			summariesSinceFlush++;
			if (summariesSinceFlush >= 5) flush();	// 约5秒落盘一次(降低写盘频率; 每2秒一次对打歌是无谓 I/O)

			// 内存分解: 每10秒定位堆里的大头(普通贴图/ASTC/资源跟踪量)
			// D1: 默认关闭 —— 该函数每 10s 遍历整个贴图缓存+读 /proc(1~5ms I/O), 是周期性尖帧的可疑来源;
			//     需要内存归因时把 memBreakdown 置 true(或挂到调试开关)
			if (memBreakdown && now - lastBreakMs >= 10000) { lastBreakMs = now; pushMemBreakdown(now); }
		}
	}

	// 段小结: 一个状态结束时输出该段整体表现 + 全场累计
	static function pushSegSummary(now:Float):Void
	{
		var segSec:Float = (now - segStartMs) / 1000;
		if (segStartMs <= 0 || segSec < 3) return;	// 段太短(切屏抖动)不输出

		var line:String = (segLabel != null && segLabel.length > 0 ? segLabel : shortState(curStateName())) + ' 段小结: ' + Math.round(segSec) + 's'
			+ '  fps均=' + Math.round(segFrames / Math.max(1, segSec))
			+ '  mem峰=' + Math.round(segMemPeak) + 'MB';
		if (segJudgeN > 0)
		{
			var avg:Float = segJudgeSum / segJudgeN;
			line += ' 判定=' + segJudgeN + ' 均差=' + (avg >= 0 ? '+' : '') + Math.round(avg) + 'ms'
				+ ' miss=' + segJudgeMiss;
		}
		if (gcTotalCnt > 0) line += '  GC=' + gcTotalCnt + '次-' + Math.round(gcTotalMB) + 'MB';
		if (allocSegSecs > 3) line += '  分配均=' + Math.round(allocSegMB / allocSegSecs) + 'MB/s';
		if (spikeTotal > 0) line += '  尖帧=' + spikeTotal + '(峰' + spikeMaxMs + 'ms)';
		push('--- ' + line + ' ---');

		segStartMs = now; segFrames = 0; segMemPeak = 0;
		segJudgeN = 0; segJudgeSum = 0; segJudgeMiss = 0;
		allocSegMB = 0; allocSegSecs = 0;
		spikeTotal = 0; spikeMaxMs = 0;		// 尖峰统计按段重置(此前跨段累计易误判)
		gcTotalCnt = 0; gcTotalMB = 0;		// GC 统计按段重置
	}

	public static function onPostUpdate():Void
	{
		if (!enabled) return;
		var now:Float = Timer.stamp() * 1000;
		var d:Float = now - updStartMs;
		updSum += d;
		if (d > updMax) updMax = d;
	}

	public static function onPreDraw():Void
	{
		if (!enabled) return;
		drawStartMs = Timer.stamp() * 1000;
	}

	public static function onPostDraw():Void
	{
		if (!enabled) return;
		var now:Float = Timer.stamp() * 1000;
		var d:Float = now - drawStartMs;
		drawSum += d;
		if (d > drawMax) drawMax = d;
	}

	// ===== GC 事件(FPSCounter 检测到堆内存显著下降时回调) =====

	public static function onGc(dropBytes:Float):Void
	{
		if (!enabled) return;
		gcSec++;
		gcTotalCnt++;
		gcTotalMB += dropBytes / 1048576;
		gcFreedAccumMB += dropBytes / 1048576;
		push('[' + fmt(Timer.stamp() * 1000) + '] GC -' + r1(dropBytes / 1048576)
			+ 'MB 帧耗时=' + Math.round(frameMs) + 'ms state=' + curStateName());
	}

	// ===== 外部日志入口(如触控诊断): 复用缓冲与约2秒落盘节奏 =====

	public static function log(line:String):Void
	{
		push(line);
	}

	// ===== 进歌耗时分解: 各阶段相对打点(点歌时 reset, 跨状态累计毫秒) =====

	public static var loadMarkT0:Float = 0;

	public static function loadMark(label:String):Void
	{
		#if (sys && mobile)
		var now:Float = Timer.stamp() * 1000;
		if (loadMarkT0 <= 0) loadMarkT0 = now;
		push('[进歌] +' + r1(now - loadMarkT0) + 'ms ' + label);
		#end
	}

	public static function loadMarkReset():Void
	{
		loadMarkT0 = 0;
	}

	// ===== 内部 =====

	// ===== 分配归因(诊断) =====
	// 用法: var h0 = PerfProbe.heapMB(); ...热点代码...; PerfProbe.addAlloc("溅射", h0);
	// 每秒汇总行会输出 "分:标签=MB ...", 用来定位周期性堆增长来自哪里
	static var allocLabels:Map<String, Float> = new Map<String, Float>();

	#if cpp
	public static inline function heapMB():Float
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE) / 1048576.0;
	#else
	public static inline function heapMB():Float return 0;
	#end

	public static inline function addAlloc(label:String, h0:Float):Void
	{
		#if cpp
		var d:Float = heapMB() - h0;
		if (d > 0.05)	// 忽略 50KB 以下噪声
			allocLabels.set(label, (allocLabels.exists(label) ? allocLabels.get(label) : 0) + d);
		#end
	}

	static function allocLine():String
	{
		var s:String = '';
		for (k => v in allocLabels) s += k + '=' + r1(v) + ' ';
		if (s.length < 1) return '';
		allocLabels.clear();
		return ' 分:' + s;
	}

	static function push(line:String):Void
	{
		#if (sys && mobile)
		if (filePath == null) return;
		buffer.push(line);
		#end
	}

	static function flush():Void
	{
		#if (sys && mobile)
		if (filePath == null || buffer.length == 0) return;
		#if cpp
		var h0:Float = heapMB();
		#end
		try
		{
			if (out == null) out = File.append(filePath, false);
			for (line in buffer)
				out.writeString(line + '\n');
			out.flush();
			buffer.resize(0);
			summariesSinceFlush = 0;
		}
		catch (e:Dynamic)
		{
			// 磁盘出错就停用, 避免每帧异常
			buffer.resize(0);
			enabled = false;
		}
		#if cpp
		addAlloc('日志', h0);
		#end
		#end
	}

	static function fmt(nowMs:Float):String
	{
		return r1((nowMs - startMs) / 1000) + 's';
	}

	static function r1(v:Float):String
	{
		return '' + (Math.round(v * 10) / 10);
	}

	// 状态名中文短名
	static function shortState(full:String):String
	{
		var s:String = full;
		s = StringTools.replace(s, 'CustomFadeTransition', '过渡');
		s = StringTools.replace(s, 'GameplayChangersSubstate', '玩法面板');
		s = StringTools.replace(s, 'PauseSubState', '暂停');
		s = StringTools.replace(s, 'GameoverState', '败北');
		s = StringTools.replace(s, 'TitleState', '标题');
		s = StringTools.replace(s, 'MainMenuState', '主菜单');
		s = StringTools.replace(s, 'FreeplayState', '选曲');
		s = StringTools.replace(s, 'StoryMenuState', '故事');
		s = StringTools.replace(s, 'OptionsState', '设置');
		s = StringTools.replace(s, 'PlayState', '打歌');
		s = StringTools.replace(s, 'ChartingState', '编辑器');
		s = StringTools.replace(s, 'State', '');
		s = StringTools.replace(s, 'SubState', '');
		return s;
	}

	static inline function curStateName():String
	{
		var n:String = Type.getClassName(Type.getClass(FlxG.state));
		var name:String = (n != null) ? n.substr(n.lastIndexOf('.') + 1) : 'null';
		if (FlxG.state.subState != null)
		{
			var sn:String = Type.getClassName(Type.getClass(FlxG.state.subState));
			name += '+' + ((sn != null) ? sn.substr(sn.lastIndexOf('.') + 1) : 'SubState');
		}
		return name;
	}

	// ===== 内存分解(每10秒): 普通BitmapData按RGBA估堆占用, ASTC只计张数(数据在显存) =====

	static function pushMemBreakdown(nowMs:Float):Void
	{
		#if (cpp && mobile)
		var texCnt:Int = 0;
		var texMB:Float = 0;
		var astcCnt:Int = 0;
		var gpuCnt:Int = 0;
		@:privateAccess
		for (key in FlxG.bitmap._cache.keys())
		{
			var g:FlxGraphic = FlxG.bitmap._cache.get(key);
			if (g == null || g.bitmap == null) continue;
			#if ASTC_SUPPORT
			if (Std.isOfType(g.bitmap, backend.astcsupport.openfl.display.ASTCBitmapData)) { astcCnt++; continue; }
			#end
			if (!g.bitmap.readable) { gpuCnt++; continue; }	// GPU化纹理: 数据在GL, 零堆占用
			texCnt++;
			texMB += g.bitmap.width * g.bitmap.height * 4 / 1048576;
		}
		var rssMB:Float = readRssMB();
		// 音频 PCM 驻留估算: lime Android 解码为 44.1kHz/16bit/立体声 = 176.4 B/ms = 0.00016822 MB/ms
		var audioCnt:Int = 0;
		var audioMB:Float = 0;
		@:privateAccess
		{
			if (FlxG.sound.music != null && FlxG.sound.music._sound != null)
			{
				audioCnt++;
				audioMB += FlxG.sound.music._sound.length * 0.00016822;
			}
			for (snd in FlxG.sound.list)
			{
				if (snd != null && snd._sound != null)
				{
					audioCnt++;
					audioMB += snd._sound.length * 0.00016822;
				}
			}
		}
		push('[' + fmt(nowMs) + '] 内存分解 堆内贴图=' + texCnt + '张/' + Math.round(texMB)
			+ 'MB GPU化=' + gpuCnt + ' ASTC=' + astcCnt
			+ ' 跟踪图=' + Lambda.count(Paths.currentTrackedAssets)
			+ ' 跟踪音=' + Lambda.count(Paths.currentTrackedSounds)
			+ ' 音频=' + audioCnt + '轨/~' + Math.round(audioMB) + 'MB'
			+ ' 曲=' + (states.PlayState.SONG != null ? states.PlayState.SONG.song : '-')
			+ ' rss=' + Math.round(rssMB) + 'MB');
		#end
	}

	// 进程真实内存(VmRSS): 含音频PCM/GPU驱动等 hxcpp堆之外的开销, 差值=堆外占用
	// 注意: /proc 文件 size=0, lime 按大小读会得到空串 —— 必须用 FileInput 流式读
	static var rssFailLogged:Bool = false;

	static function readRssMB():Float
	{
		#if (cpp && mobile)
		try
		{
			var s:String = readProcFile('/proc/self/status');
			var idx:Int = s.indexOf('VmRSS:');
			if (idx >= 0)
			{
				var endIdx:Int = s.indexOf('kB', idx);
				if (endIdx > idx)
				{
					var v:Float = Std.parseFloat(s.substr(idx + 6, endIdx - idx - 6));
					if (!Math.isNaN(v) && v >= 0) return v / 1024;
				}
			}
		}
		catch (e:Dynamic) {}
		try
		{
			var stat:String = readProcFile('/proc/self/stat');
			var closeIdx:Int = stat.lastIndexOf(')');
			if (closeIdx >= 0)
			{
				var parts:Array<String> = stat.substr(closeIdx + 2).split(' ');
				if (parts.length > 22)
				{
					var pages:Float = Std.parseFloat(parts[22]);
					if (!Math.isNaN(pages) && pages > 0) return pages * 4096 / 1048576;
				}
			}
		}
		catch (e2:Dynamic) {}
		if (!rssFailLogged)
		{
			rssFailLogged = true;
			push('[' + fmt(Timer.stamp() * 1000) + '] rss读取失败(两种途径均不可用)');
		}
		#end
		return -1;
	}

	static function readProcFile(path:String):String
	{
		var input:sys.io.FileInput = sys.io.File.read(path, false);
		var bytes = input.readAll();
		input.close();
		return bytes.toString();
	}

	// 从 build.prop 类文本取 key= 行的值
	static function readPropLine(content:String, key:String):String
	{
		var idx:Int = content.indexOf(key + '=');
		if (idx < 0) return null;
		var endIdx:Int = content.indexOf('\n', idx);
		if (endIdx < 0) endIdx = content.length;
		return content.substr(idx + key.length + 1, endIdx - idx - key.length - 1);
	}

	// ===== 判定直方图(玩家击中偏差, 按秒聚合) =====
	// 约定: rawDiff = note.strumTime - songPosition (正=按早, 负=按晚), 已除以 playbackRate 与判定窗口同尺度
	static var judgeCount:Int = 0;
	static var judgeMissCount:Int = 0;
	static var judgeSum:Float = 0;
	static var judgeBuckets:Array<Int> = [0,0,0,0,0];	// [晚>90, 晚45-90, ±45准, 早45-90, 早>90]

	public static function onJudge(rawDiff:Float, miss:Bool = false):Void
	{
		if (!enabled) return;
		if (miss) { judgeMissCount++; return; }
		judgeCount++;
		judgeSum += rawDiff;
		if (rawDiff <= -90) judgeBuckets[0]++;
		else if (rawDiff < -45) judgeBuckets[1]++;
		else if (rawDiff <= 45) judgeBuckets[2]++;
		else if (rawDiff <= 90) judgeBuckets[3]++;
		else judgeBuckets[4]++;
	}

	// 音画时钟漂移: music.time(音频真实位置) - Conductor.songPosition(谱面时钟)
	// 正值=谱面时钟落后(音符会晚到), 持续增大=谱面被"放慢"的直接证据; rate=回放速度(gameplaySettings 持久化)
	// v= 人声轨与伴奏轨的位置差(vocals.time - music.time): |v| 大了才会触发 stepHit 的人声重同步
	static function driftLine():String
	{
		#if (cpp && mobile)
		var ps = states.PlayState.instance;
		if (ps == null || FlxG.sound.music == null || !FlxG.sound.music.playing) return '';
		@:privateAccess if (!ps.generatedMusic) return '';
		var drift:Float = FlxG.sound.music.time - Conductor.songPosition;
		var vocalDelta:Float = 0;
		if (ps.vocals != null && ps.vocals.length > 0) vocalDelta = ps.vocals.time - FlxG.sound.music.time;
		return ' drift=' + Math.round(drift) + 'ms v=' + Math.round(vocalDelta) + 'ms rate=' + r1(ps.playbackRate);
		#end
		return '';
	}
}
