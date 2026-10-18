package backend;

import haxe.Timer;
import flixel.FlxG;
import flixel.FlxState;

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
			push('[' + fmt(now) + '] ' + curStateName()
				+ ' fps=' + Math.round(secFrames / sec)
				+ ' upd=' + r1(updAvg) + 'ms(峰' + r1(updMax) + ')'
				+ ' draw=' + r1(drawAvg) + 'ms(峰' + r1(drawMax) + ')'
				+ ' GC=' + gcSec + '次');
			secFrames = 0; updSum = 0; updMax = 0; drawSum = 0; drawMax = 0;
			gcSec = 0; spikeSec = 0;
			secStartMs = now;
			summariesSinceFlush++;
			if (summariesSinceFlush >= 2) flush();	// 约2秒落盘一次
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

	inline function curStateName():String
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
}
