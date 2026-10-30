package debug;

import backend.PerfProbe;
import flixel.FlxG;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.geom.Rectangle;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.system.System;

/**
	现代风格性能卡:
	┌─────────────────────────┐
	│  62  FPS        16.1 ms │
	│  ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁        │  ← 帧率曲线(约 21 秒)
	│  MEM 134M   U2.5 D1.1   │  ← 内存 / 更新&绘制耗时
	└─────────────────────────┘
	隐藏时不跑任何逻辑; 每 200ms 刷文字, 每 150ms 画一格曲线。
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

	// ===== 卡片布局(逻辑像素, 移动端由 setScale 整体缩放) =====
	static inline var CARD_W:Float = 168;
	static inline var CARD_H:Float = 88;
	static inline var PAD:Float = 12;
	static inline var RADIUS:Float = 14;
	static inline var GRAPH_W:Int = 144;
	static inline var GRAPH_H:Int = 22;
	static inline var SAMPLE_MS:Float = 150;	// 144列 × 150ms ≈ 21 秒历史

	// ===== 配色(MD3 深色) =====
	static inline var C_BG:Int = 0x1C1B1F;
	static inline var C_TEXT:Int = 0xEDEDF0;
	static inline var C_MUTED:Int = 0x9AA0A6;
	static inline var C_OK:Int = 0x8FE1A2;
	static inline var C_WARN:Int = 0xFFCE6B;
	static inline var C_BAD:Int = 0xFF7B7B;

	// ===== 组件 =====
	var card:Bitmap;
	var fpsText:TextField;	// 大号帧数
	var unitText:TextField;	// "FPS"
	var msText:TextField;	// 帧耗时(右对齐)
	var footText:TextField;	// 内存 / 更新·绘制耗时
	var graphBD:BitmapData;	// 帧率曲线
	var baseColor:Int;

	// ===== 采样 =====
	var sampleAcc:Float = 0;
	var textCooldown:Float = 0;
	var lastGcMem:Float = 0;
	var _rect:Rectangle = new Rectangle();

	// FPS 环形时间窗(替代 push+shift 的 O(n) 搬移)
	static inline var TIMES_CAP:Int = 128;
	var times:Array<Float>;
	var timesHead:Int = 0;
	var timesCount:Int = 0;

	public function new(x:Float = 12, y:Float = 12, color:Int = C_TEXT)
	{
		super();

		this.x = x #if ios + 50 #end;
		this.y = y;
		baseColor = color;
		currentFPS = 0;
		mouseEnabled = false;
		mouseChildren = false;
		times = [];

		// 背板(圆角卡片)
		card = new Bitmap(createCard());
		card.mouseEnabled = false;
		addChild(card);

		// 大号帧数
		fpsText = mkText(30, C_TEXT);
		fpsText.x = PAD;
		fpsText.y = 2;
		fpsText.text = '0';
		addChild(fpsText);

		// "FPS" 单位
		unitText = mkText(10, C_MUTED);
		unitText.x = PAD + 54;
		unitText.y = 20;
		unitText.text = 'FPS';
		addChild(unitText);

		// 帧耗时(右对齐)
		msText = mkText(11, C_MUTED, 60, 'right');
		msText.x = CARD_W - PAD - 60;
		msText.y = 20;
		msText.text = '-- ms';
		addChild(msText);

		// 帧率曲线
		graphBD = new BitmapData(GRAPH_W, GRAPH_H, true, 0x00000000);
		var graph:Bitmap = new Bitmap(graphBD);
		graph.x = PAD;
		graph.y = 46;
		graph.mouseEnabled = false;
		addChild(graph);

		// 底部信息行
		footText = mkText(10, C_MUTED, CARD_W - PAD * 2);
		footText.x = PAD;
		footText.y = 70;
		footText.text = 'MEM 0M';
		addChild(footText);

		lastGcMem = getGcCurrent();

		#if mobile
		setScale();
		#end
	}

	// ===== 背板绘制: 圆角卡片 + 1px 描边 =====
	function createCard():BitmapData
	{
		var iw:Int = Math.round(CARD_W);
		var ih:Int = Math.round(CARD_H);
		var bd:BitmapData = new BitmapData(iw, ih, true, 0x00000000);
		var s:Shape = new Shape();
		s.graphics.beginFill(C_BG, 0.84);
		s.graphics.drawRoundRect(0.5, 0.5, iw - 1, ih - 1, RADIUS * 2, RADIUS * 2);
		s.graphics.endFill();
		s.graphics.lineStyle(1, 0xFFFFFF, 0.10);
		s.graphics.drawRoundRect(0.5, 0.5, iw - 1, ih - 1, RADIUS * 2, RADIUS * 2);
		bd.draw(s);
		return bd;
	}

	function mkText(size:Int, color:Int, width:Float = 0, ?align:String):TextField
	{
		var t:TextField = new TextField();
		t.selectable = false;
		t.mouseEnabled = false;
		t.multiline = false;
		if (width > 0) t.width = width;
		var fmt:TextFormat = new TextFormat('_sans', size, color);
		if (align != null) fmt.align = align;
		t.defaultTextFormat = fmt;
		t.text = '';
		return t;
	}

	// Event Handlers
	private override function __enterFrame(deltaTime:Float):Void
	{
		// 隐藏时彻底不干活(不采样/不画曲线/不做原生尺寸查询)
		if (!visible) return;

		final now:Float = haxe.Timer.stamp() * 1000;
		if (timesCount < TIMES_CAP)
		{
			times[(timesHead + timesCount) % TIMES_CAP] = now;
			timesCount++;
		}
		else
		{
			times[timesHead] = now;
			timesHead = (timesHead + 1) % TIMES_CAP;
		}
		while (timesCount > 0 && times[timesHead] < now - 1000)
		{
			timesHead = (timesHead + 1) % TIMES_CAP;
			timesCount--;
		}

		currentFPS = timesCount < FlxG.updateFramerate ? timesCount : FlxG.updateFramerate;

		textCooldown += deltaTime;
		if (textCooldown >= 200)
		{
			textCooldown = 0;
			updateTexts();
		}

		updateGraphs(deltaTime);

		#if mobile
		setScale();
		#end
	}

	public dynamic function updateText():Void
	{
		updateTexts();
		updateGraphs(0);
	}

	dynamic function updateTexts():Void
	{
		var target:Float = Math.max(FlxG.drawFramerate, 1);
		var col:Int = C_OK;
		if (currentFPS < target * 0.5) col = C_BAD;
		else if (currentFPS < target * 0.85) col = C_WARN;

		fpsText.text = Std.string(currentFPS);
		fpsText.textColor = col;

		msText.text = (currentFPS > 0) ? (Math.round((1000 / currentFPS) * 10) / 10) + ' ms' : '-- ms';

		// 底部: 内存 + 更新/绘制平均耗时(来自 PerfProbe, 无数据时显示 0)
		var foot:String = 'MEM ' + Math.round(memoryMegas) + 'M';
		if (PerfProbe.lastUpdAvg > 0)
			foot += '  U' + r1(PerfProbe.lastUpdAvg) + ' D' + r1(PerfProbe.lastDrawAvg);
		footText.text = foot;
	}

	dynamic function updateGraphs(deltaMs:Float = 0):Void
	{
		// GC 事件检测(PerfProbe 的 GC 日志依赖这里)
		var curMem:Float = getGcCurrent();
		var drop:Float = lastGcMem - curMem;
		lastGcMem = curMem;
		if (drop >= 2 * 1024 * 1024)
			PerfProbe.onGc(drop);

		// 定间隔采样: 每列 150ms
		sampleAcc += deltaMs;
		if (sampleAcc < SAMPLE_MS) return;
		sampleAcc -= SAMPLE_MS;

		// 左移一格 + 清空最右列
		graphBD.scroll(-1, 0);
		_rect.setTo(GRAPH_W - 1, 0, 1, GRAPH_H);
		graphBD.fillRect(_rect, 0x00000000);

		var target:Float = Math.max(FlxG.drawFramerate, 1);
		var h:Int = Std.int(Math.max(1, Math.min(1.0, currentFPS / target) * GRAPH_H));
		var col:Int = C_OK;
		if (currentFPS < target * 0.5) col = C_BAD;
		else if (currentFPS < target * 0.85) col = C_WARN;

		// 柱身(半透明) + 顶帽(全亮)
		_rect.setTo(GRAPH_W - 1, GRAPH_H - h, 1, h);
		graphBD.fillRect(_rect, 0x88000000 | col);
		var capH:Int = (h >= 2) ? 2 : 1;
		_rect.setTo(GRAPH_W - 1, GRAPH_H - h, 1, capH);
		graphBD.fillRect(_rect, 0xFF000000 | col);
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

	inline function r1(v:Float):String
	{
		return '' + (Math.round(v * 10) / 10);
	}

	#if mobile
	public inline function setScale(?scale:Float):Void
	{
		if (scale == null)
		{
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
