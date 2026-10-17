package ui.md3;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxMath;

/**
 * 自绘 MD3 开关(药丸轨道 + 圆形滑块), 纯位图绘制, 不用引擎部件。
 */
class MD3Switch extends FlxSpriteGroup
{
	public var on(default, set):Bool = false;
	public var onToggle:Bool->Void = null;

	var track:FlxSprite;
	var knob:FlxSprite;
	static var trackG:flixel.graphics.FlxGraphic = null;
	static var knobG:flixel.graphics.FlxGraphic = null;
	static inline var TRACK_W:Int = 64;
	static inline var TRACK_H:Int = 32;
	static inline var KNOB:Int = 26;

	public function new(x:Float, y:Float, initial:Bool = false, ?onToggle:Bool->Void)
	{
		super(x, y);
		this.onToggle = onToggle;
		if (trackG == null) trackG = MD3Rounded.get(TRACK_W, TRACK_H, TRACK_H >> 1);
		if (knobG == null) knobG = MD3Rounded.get(KNOB, KNOB, KNOB >> 1);
		track = new FlxSprite(0, 0);
		track.loadGraphic(trackG);
		track.color = MD3Theme.outline;
		knob = new FlxSprite(3, 3);
		knob.loadGraphic(knobG);
		knob.color = 0xFFFFFFFF;
		add(track);
		add(knob);
		on = initial;
	}

	function set_on(v:Bool):Bool
	{
		on = v;
		track.color = v ? MD3Theme.primary : MD3Theme.outline;
		knob.color = v ? MD3Theme.onPrimary : 0xFFFFFFFF;
		return v;
	}

	override function update(elapsed:Float)
	{
		var targetX:Float = on ? (TRACK_W - KNOB - 3) : 3;
		knob.x = flixel.math.FlxMath.lerp(targetX, knob.x, Math.exp(-elapsed * 16));
		super.update(elapsed);
	}

	public function toggle():Void
	{
		on = !on;
		if (onToggle != null) onToggle(on);
	}
}
