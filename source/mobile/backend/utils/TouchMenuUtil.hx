package mobile.backend.utils;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxPoint;

/**
 * 通用触控菜单组件:
 *  - 点某个选项 → 选中它
 *  - 点"已选中"的选项 → 确认
 *  - 上下滑动 → 逐项移动选择
 * 泛型签名避免 Haxe 数组不协变问题。
 */
class TouchMenuUtil
{
	static var trackedId:Int = -1;
	static var startY:Float = 0;
	static var lastStepY:Float = 0;
	static var moved:Bool = false;

	public static var enabled:Bool = true;

	public static function update<T:FlxSprite>(items:Array<T>, curSelected:Int,
		onSelect:Int->Void, onSelectTo:Int->Void, onAccept:Void->Void):Void
	{
		#if mobile
		if (!enabled || items == null || items.length == 0) return;

		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed && trackedId == -1)
			{
				trackedId = touch.touchPointID;
				startY = touch.y;
				lastStepY = touch.y;
				moved = false;
			}
			else if (touch.touchPointID == trackedId)
			{
				if (touch.pressed)
				{
					if (!moved && Math.abs(touch.y - startY) > 24) moved = true;
					if (moved)
					{
						while (touch.y - lastStepY > 55) { lastStepY += 55; if (onSelect != null) onSelect(-1); }
						while (lastStepY - touch.y > 55) { lastStepY -= 55; if (onSelect != null) onSelect(1); }
					}
				}
				else if (touch.justReleased)
				{
					if (!moved)
					{
						var idx:Int = hitTest(items, touch.x, touch.y);
						if (idx >= 0)
						{
							if (idx == curSelected) { if (onAccept != null) onAccept(); }
							else if (onSelectTo != null) onSelectTo(idx);
						}
					}
					trackedId = -1;
				}
			}
		}

		if (trackedId != -1)
		{
			var still:Bool = false;
			for (t in FlxG.touches.list)
				if (t.touchPointID == trackedId && (t.pressed || t.justPressed)) { still = true; break; }
			if (!still) trackedId = -1;
		}
		#end
	}

	static function hitTest<T:FlxSprite>(items:Array<T>, x:Float, y:Float):Int
	{
		var point = FlxPoint.weak(x, y);
		var result:Int = -1;
		for (i in 0...items.length)
		{
			var it = items[i];
			if (it == null || !it.exists || !it.active) continue;
			var halfW:Float = it.width / 2 + 8;
			var halfH:Float = it.height / 2 + 8;
			var cx:Float = it.x + it.width / 2;
			var cy:Float = it.y + it.height / 2;
			if (point.x >= cx - halfW && point.x <= cx + halfW && point.y >= cy - halfH && point.y <= cy + halfH)
			{
				result = i;
				break;
			}
		}
		return result;
	}
}
