package debug;

import flixel.FlxG;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.geom.Rectangle;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.system.System;

/**
	引擎信息显示器: 引擎名+版本 / 帧数+曲线 / 内存+曲线
**/
class FPSCounter extends Sprite
{
	/**
		The current frame rate, expressed using frames-per-second
	**/
	public var currentFPS(default, null):Int;

	/**
		The current memory usage (WARNING: this is NOT your total program memory usage, rather it shows the garbage collector memory)
	**/
	public var memoryMegas(get, never):Float;

	// ===== 图表参数 =====
	static inline var GRAPH_W:Int = 100;	// 曲线宽度(像素)
	static inline var GRAPH_H:Int = 30;		// 曲线高度(像素)
	static inline var GAP:Int = 3;			// 行间距
	static inline var SAMPLE_MS:Float = 150;	// 采样间隔: 100列×150ms ≈ 15秒历史(原每帧一格只有1.7秒, 看不出趋势)

	// ===== 柱状图配色(RGB; 画的时候柱身叠半透明, 柱帽用全亮) =====
	static inline var COL_FPS_OK:Int = 0x66FF99;	// 帧数正常: 绿
	static inline var COL_FPS_BAD:Int = 0xFF5555;	// 帧数过低: 红
	static inline var COL_MEM:Int = 0x55CCFF;	// 内存: 蓝
	static inline var COL_GC:Int = 0xFFBB55;	// GC: 橙

	// ===== 内部组件 =====
	var verText:TextField;	// 引擎名+版本
	var fpsText:TextField;	// 帧数
	var memText:TextField;	// 内存
	var gcText:TextField;	// GC 堆占用
	var fpsBD:BitmapData;	// 帧数曲线
	var memBD:BitmapData;	// 内存曲线
	var gcBD:BitmapData;	// GC 曲线(每次回收的回收量)
	var baseColor:Int;

	var times:Array<Float>;
	var memMax:Float = 1;	// 内存曲线的动态最大值
	var gcMax:Float = 1;	// GC占用曲线的动态最大值
	var lastGcMem:Float = 0;	// 上一帧的 GC 当前堆内存

	var sampleAcc:Float = 0;	// 采样累积器(ms)

	var _rect:Rectangle = new Rectangle();	// 复用的矩形, 避免每帧分配
	var textCooldown:Float = 0;	// 文字降频刷新计时

	public function new(x:Float = 10, y:Float = 10, color:Int = 0x000000)
	{
		super();

		this.x = x #if ios + 50 #end;
		this.y = y;
		baseColor = color;

		currentFPS = 0;
		mouseEnabled = false;
		mouseChildren = false;
		times = [];

		var fmt = new TextFormat("_sans", 12, color);

		// ===== 固定布局(不依赖文本实时高度, 防止曲线盖住文字) =====
		var lineH:Float = 18;
		var yVer:Float = 0;
		var yFps:Float = yVer + lineH + GAP;
		var yFpsG:Float = yFps + lineH + GAP;
		var yMem:Float = yFpsG + GRAPH_H + GAP;
		var yMemG:Float = yMem + lineH + GAP;
		var yGc:Float = yMemG + GRAPH_H + GAP;
		var yGcG:Float = yGc + lineH + GAP;

		// 曲线先加(垫底层)
		fpsBD = new BitmapData(GRAPH_W, GRAPH_H, true, 0x00000000);
		var fpsGraph:Bitmap = new Bitmap(fpsBD);
		fpsGraph.x = 0;
		fpsGraph.y = yFpsG;
		addChild(fpsGraph);

		memBD = new BitmapData(GRAPH_W, GRAPH_H, true, 0x00000000);
		var memGraph:Bitmap = new Bitmap(memBD);
		memGraph.x = 0;
		memGraph.y = yMemG;
		addChild(memGraph);

		gcBD = new BitmapData(GRAPH_W, GRAPH_H, true, 0x00000000);
		var gcGraph:Bitmap = new Bitmap(gcBD);
		gcGraph.x = 0;
		gcGraph.y = yGcG;
		addChild(gcGraph);

		// 文字后加(上层, 不会被曲线遮挡)
		verText = mkText(fmt);
		verText.text = 'NekoEngine v0.01';
		verText.y = yVer;
		addChild(verText);

		fpsText = mkText(fmt);
		fpsText.text = 'FPS: 0';
		fpsText.y = yFps;
		addChild(fpsText);

		memText = mkText(fmt);
		memText.text = 'Memory: 0 MB';
		memText.y = yMem;
		addChild(memText);

		gcText = mkText(fmt);
		gcText.text = 'GC: 0 MB';
		gcText.y = yGc;
		addChild(gcText);

		lastGcMem = getGcCurrent();

		#if mobile
		setScale();
		#end
	}

	inline function mkText(fmt:TextFormat):TextField
	{
		var t = new TextField();
		t.selectable = false;
		t.mouseEnabled = false;
		t.defaultTextFormat = fmt;
		t.autoSize = LEFT;
		t.multiline = false;
		t.text = '';
		return t;
	}

	var deltaTimeout:Float = 0.0;

	// Event Handlers
	private override function __enterFrame(deltaTime:Float):Void
	{
		// prevents the overlay from updating every frame, why would you need to anyways
		if (deltaTimeout > 1000) {
			deltaTimeout = 0.0;
			return;
		}

		final now:Float = haxe.Timer.stamp() * 1000;
		times.push(now);
		while (times[0] < now - 1000) times.shift();

		currentFPS = times.length < FlxG.updateFramerate ? times.length : FlxG.updateFramerate;
		// 文字每 200ms 刷一次; 曲线内部按 150ms 采样, 每帧只累积计时
		textCooldown += deltaTime;
		if (textCooldown >= 200)
		{
			textCooldown = 0;
			updateTexts();
		}
		updateGraphs(deltaTime);
		#if mobile setScale(); #end
		deltaTimeout += deltaTime;
	}

	public dynamic function updateText():Void { // so people can override it in hscript
		updateTexts();
		updateGraphs(0);
	}

	dynamic function updateTexts():Void {
		fpsText.text = 'FPS: $currentFPS';
		fpsText.textColor = (currentFPS < FlxG.drawFramerate * 0.5) ? 0xFFFF0000 : baseColor;

		memText.text = 'Memory: ${flixel.util.FlxStringUtil.formatBytes(memoryMegas)}';
		memText.textColor = baseColor;

		gcText.text = 'GC: ' + (Math.round(getGcCurrent() / 104857.6) / 10) + ' MB';	// GC堆当前占用
		gcText.textColor = baseColor;
	}

	dynamic function updateGraphs(deltaMs:Float = 0):Void {
		// 定间隔采样: 每列代表 150ms, 100列 ≈ 15秒趋势; 不足间隔只累积不画
		sampleAcc += deltaMs;
		if (sampleAcc < SAMPLE_MS) return;
		sampleAcc -= SAMPLE_MS;

		// ===== 帧数曲线(柱状) =====
		_rect.x = GRAPH_W - 1; _rect.y = 0; _rect.width = 1; _rect.height = GRAPH_H;
		fpsBD.scroll(-1, 0);	// 左移一格
		fpsBD.fillRect(_rect, 0x00000000);	// 清空最右列
		var fpsH:Int = Std.int(Math.max(1, Math.min(1.0, currentFPS / Math.max(FlxG.drawFramerate, 1)) * GRAPH_H));
		var fpsRGB:Int = (currentFPS < FlxG.drawFramerate * 0.5) ? COL_FPS_BAD : COL_FPS_OK;
		plotBar(fpsBD, GRAPH_H - fpsH, fpsRGB);

		// ===== 内存曲线(柱状) =====
		var mem:Float = memoryMegas;
		// 动态量程: 峰值缓慢衰减, 曲线不会长期贴顶
		memMax = Math.max(mem, memMax * 0.9985);
		if (memMax < 1) memMax = 1;
		_rect.x = GRAPH_W - 1; _rect.y = 0; _rect.height = GRAPH_H;
		memBD.scroll(-1, 0);
		memBD.fillRect(_rect, 0x00000000);
		var memH:Int = Std.int(Math.max(1, Math.min(1.0, mem / memMax) * GRAPH_H));
		plotBar(memBD, GRAPH_H - memH, COL_MEM);

		// ===== GC 堆占用曲线(柱状, 锯齿: 上升=垃圾积累, 陡降=发生回收) =====
		// hxcpp 没有暂停耗时接口, 回收判定用"堆内存显著下降"(阈值2MB), 事件走日志
		var curMem:Float = getGcCurrent();
		var drop:Float = lastGcMem - curMem;
		lastGcMem = curMem;
		if (drop >= 2 * 1024 * 1024)
		{
			backend.PerfProbe.onGc(drop);	// 探测点: 记录GC事件+当帧耗时
		}
		gcMax = Math.max(curMem, gcMax * 0.9985);
		if (gcMax < 1) gcMax = 1;
		_rect.x = GRAPH_W - 1; _rect.y = 0; _rect.height = GRAPH_H;
		gcBD.scroll(-1, 0);
		gcBD.fillRect(_rect, 0x00000000);
		var gcH:Int = Std.int(Math.max(1, Math.min(1.0, curMem / gcMax) * GRAPH_H));
		plotBar(gcBD, GRAPH_H - gcH, COL_GC);
	}

	// 柱状图绘制: 半透明柱身 + 顶部2px全亮实心横线(柱帽), 无辉光, 边缘锐利
	inline function plotBar(bd:BitmapData, y:Int, rgb:Int):Void
	{
		// 柱帽: 顶部亮横线(2px, 全亮度, 不透明)
		_rect.x = GRAPH_W - 1; _rect.y = y; _rect.width = 1; _rect.height = 2;
		bd.fillRect(_rect, 0xFF000000 | rgb);
		// 柱身: 从柱帽往下到底, 半透明
		_rect.y = y + 2; _rect.height = GRAPH_H - y - 2;
		if (_rect.height > 0) bd.fillRect(_rect, 0x55000000 | rgb);
	}

	// GC 当前堆内存(含未回收垃圾, 锯齿波动); 非cpp目标退化为总内存
	inline function getGcCurrent():Float
	{
		#if cpp
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_CURRENT);
		#else
		return memoryMegas;
		#end
	}

	#if mobile
	public inline function setScale(?scale:Float):Void {
	    if (scale == null) {
	        var screenW:Float = FlxG.stage.window.width;
	        var screenH:Float = FlxG.stage.window.height;
	        scale = Math.min(screenW / FlxG.width, screenH / FlxG.height);
	    }
	
	    #if android
	        var finalScale:Float = (scale > 1) ? scale : 1;
	    #else
	        var finalScale:Float = (scale < 1 ? scale : 1);
	    #end
	
	    scaleX = scaleY = finalScale;
	}
	#end

	inline function get_memoryMegas():Float
		return cast(System.totalMemory, UInt);
}
