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
	static var startMs:Float = 0;

	static var buffer:Array<String> = [];
	static var out:FileOutput = null;
	static var filePath:String = null;
	static var summariesSinceFlush:Int = 0;
	static var lastBreakMs:Float = -100000;

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
			flush();
		}
		catch (e:Dynamic)
		{
			filePath = null;
			enabled = false;
		}
		#end
	}

	// ===== 每帧钩子(由 Main.hx 注册到 FlxG.signals) =====

	public static function onPreUpdate():Void
	{
		if (!enabled) return;
		var now:Float = Timer.stamp() * 1000;
		if (startMs <= 0) startMs = now;
		if (secStartMs <= 0) secStartMs = now;

		if (lastPreMs > 0)
		{
			frameMs = now - lastPreMs;
			if (frameMs > 40 && frameMs < 5000 && spikeSec < 10)
			{
				push('[' + fmt(now) + '] 尖帧 ' + Math.round(frameMs) + 'ms state=' + curStateName());
				spikeSec++;
			}
		}
		lastPreMs = now;
		updStartMs = now;
		secFrames++;

		// 状态切换检测(按引用比较, 零分配)
		var st:FlxState = FlxG.state;
		if (st != lastStateRef)
		{
			if (lastStateRef != null) push('[' + fmt(now) + '] 状态切换 -> ' + curStateName());
			lastStateRef = st;
		}

		// 按秒汇总
		if (now - secStartMs >= 1000)
		{
			var sec:Float = (now - secStartMs) / 1000;
			var updAvg:Float = updSum / Math.max(1, secFrames);
			var drawAvg:Float = drawSum / Math.max(1, secFrames);
			var memLine:String = '';
			#if cpp
			// 内存分解: 实用(真数据) / 堆总量(实用+空闲+垃圾), 差值即 GC 策略的代价
			var usageMB:Float = Math.round(cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE) / 104857.6) / 10;
			var rsvMB:Float = Math.round(cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_RESERVED) / 104857.6) / 10;
			memLine = ' mem=' + usageMB + '/' + rsvMB + 'MB';
			#end
			push('[' + fmt(now) + '] ' + curStateName()
				+ ' fps=' + Math.round(secFrames / sec)
				+ ' upd=' + r1(updAvg) + 'ms(峰' + r1(updMax) + ')'
				+ ' draw=' + r1(drawAvg) + 'ms(峰' + r1(drawMax) + ')'
				+ ' GC=' + gcSec + '次' + memLine + driftLine());
			secFrames = 0; updSum = 0; updMax = 0; drawSum = 0; drawMax = 0;
			gcSec = 0; spikeSec = 0;
			secStartMs = now;
			summariesSinceFlush++;
			if (summariesSinceFlush >= 2) flush();	// 约2秒落盘一次

			// 内存分解: 每10秒定位堆里的大头(普通贴图/ASTC/资源跟踪量)
			if (now - lastBreakMs >= 10000) { lastBreakMs = now; pushMemBreakdown(now); }
		}
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
		push('[' + fmt(Timer.stamp() * 1000) + '] GC -' + r1(dropBytes / 1048576)
			+ 'MB 帧耗时=' + Math.round(frameMs) + 'ms state=' + curStateName());
	}

	// ===== 外部日志入口(如触控诊断): 复用缓冲与约2秒落盘节奏 =====

	public static function log(line:String):Void
	{
		push(line);
	}

	// ===== 内部 =====

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
		var rssLine:String = (rssMB >= 0) ? ' rss=' + Math.round(rssMB) + 'MB(进程总)' : '';
		push('[' + fmt(nowMs) + '] 内存分解 堆内贴图=' + texCnt + '张/' + Math.round(texMB)
			+ 'MB GPU化=' + gpuCnt + '张 ASTC=' + astcCnt + '张 跟踪图=' + Lambda.count(Paths.currentTrackedAssets)
			+ ' 跟踪音=' + Lambda.count(Paths.currentTrackedSounds)
			+ ' 曲=' + (states.PlayState.SONG != null ? states.PlayState.SONG.song : '-') + rssLine);
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

	// 音画时钟漂移: music.time(音频真实位置) - Conductor.songPosition(谱面时钟)
	// 正值=谱面时钟落后(音符会晚到), 持续增大=谱面被"放慢"的直接证据; rate=回放速度(gameplaySettings 持久化)
	static function driftLine():String
	{
		#if (cpp && mobile)
		var ps = states.PlayState.instance;
		if (ps == null || !ps.generatedMusic || FlxG.sound.music == null || !FlxG.sound.music.playing) return '';
		var drift:Float = FlxG.sound.music.time - Conductor.songPosition;
		return ' drift=' + Math.round(drift) + 'ms rate=' + r1(ps.playbackRate);
		#end
		return '';
	}
}
