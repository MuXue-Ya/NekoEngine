package ui.md3;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxMath;

/**
 * 自绘 MD3 滑动条: 轨道 + 已填充 + 圆形手柄, 触控拖动调值。
 */
class MD3Slider extends FlxSpriteGroup
{
	public var minV:Float = 0;
	public var maxV:Float = 1;
	public var step:Float = 0.1;
	public var decimals:Int = 1;
	public var value:Float = 0;
	public var onChange:Void->Void = null;
	public var dragging(default, null):Bool = false;

	var fill:FlxSprite;
	var knob:FlxSprite;
	var trackW:Float;
	var dragTrackedId:Int = -1;

	public function new(x:Float, y:Float, w:Float, minV:Float, maxV:Float, step:Float, decimals:Int, initial:Float)
	{
		super(x, y);
		this.trackW = w;
		this.minV = minV; this.maxV = maxV; this.step = step; this.decimals = decimals;
		var track = new FlxSprite(0, 0);
		track.pixels = MD3Rounded.createBitmap(Math.round(w), 10, 5);
		track.color = MD3Theme.outline;
		fill = new FlxSprite(0, 0);
		fill.pixels = MD3Rounded.createBitmap(Math.round(w), 10, 5);
		fill.color = MD3Theme.primary;
		knob = new FlxSprite(0, 0);
		knob.pixels = MD3Rounded.createBitmap(24, 24, 12);
		knob.color = MD3Theme.primary;
		add(track); add(fill); add(knob);
		value = initial;
		refresh();
	}

	public function setValue(v:Float):Void
	{
		if (step > 0) v = Math.round(v / step) * step;
		if (v < minV) v = minV;
		if (v > maxV) v = maxV;
		v = flixel.math.FlxMath.roundDecimal(v, decimals);
		if (v != value) { value = v; refresh(); if (onChange != null) onChange(); }
	}

	function refresh():Void
	{
		var frac:Float = (maxV > minV) ? (value - minV) / (maxV - minV) : 0;
		if (frac < 0) frac = 0;
		if (frac > 1) frac = 1;
		fill.clipRect = flixel.math.FlxRect.get(0, 0, trackW * frac, 10);
		knob.x = trackW * frac - 12;
		knob.y = 5 - 12;
	}

	override function update(elapsed:Float)
	{
		#if mobile
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed && overSlider(touch.x, touch.y))
			{
				dragging = true;
				dragTrackedId = touch.touchPointID;
				applyFromTouch(touch.x);
			}
			else if (dragging && touch.touchPointID == dragTrackedId)
			{
				if (touch.pressed) applyFromTouch(touch.x);
				if (touch.justReleased) dragging = false;
			}
		}
		if (dragging)
		{
			var still:Bool = false;
			for (t in FlxG.touches.list)
				if (t.touchPointID == dragTrackedId && (t.pressed || t.justPressed)) { still = true; break; }
			if (!still) dragging = false;
		}
		#end
		super.update(elapsed);
	}

	function overSlider(tx:Float, ty:Float):Bool
	{
		var cy:Float = this.y + 5;
		return (tx >= this.x - 24 && tx <= this.x + trackW + 24 && ty >= cy - 26 && ty <= cy + 26);
	}

	function applyFromTouch(tx:Float):Void
	{
		var frac:Float = (tx - this.x) / trackW;
		if (frac < 0) frac = 0;
		if (frac > 1) frac = 1;
		setValue(minV + frac * (maxV - minV));
	}
}
