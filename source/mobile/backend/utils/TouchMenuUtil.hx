package mobile.backend.utils;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.input.touch.FlxTouch;
import flixel.math.FlxPoint;

/**
 * 通用触控菜单组件:
 *  - 点某个选项 → 选中它
 *  - 点"已选中"的选项 → 确认(等价于按A/回车)
 *  - 上下滑动 → 逐项移动选择(每55px一步)
 * 在菜单状态的 update() 里调用 update() 即可。
 */
class TouchMenuUtil
{
	static var trackedId:Int = -1;
	static var startY:Float = 0;
	static var lastStepY:Float = 0;
	static var moved:Bool = false;

	/** 允许外部临时关闭(例如子状态打开时) */
	public static var enabled:Bool = true;

	/** 触发确认时的音效由各菜单自行处理 */
	public static function update(items:Array<FlxSprite>, curSelected:Int,
		onSelect:Int->Void, onSelectTo:Int->Void, onAccept:Void->Void, ?camera:flixel.FlxCamera):Void
	{
		#if mobile
		if (!enabled || items == null || items.length == 0) return;

		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed && trackedId == -1)
			{
				trackedId = touch.touchPointId;
				startY = touch.y;
				lastStepY = touch.y;
				moved = false;
			}
			else if (touch.touchPointId == trackedId)
			{
				if (touch.pressed)
				{
					if (!moved && Math.abs(touch.y - startY) > 24) moved = true;
					if (moved)
					{
						// 手指下拉 = 选择向上一项; 上滑 = 向下一项
						while (touch.y - lastStepY > 55) { lastStepY += 55; if (onSelect != null) onSelect(-1); }
						while (lastStepY - touch.y > 55) { lastStepY -= 55; if (onSelect != null) onSelect(1); }
					}
				}
				else if (touch.justReleased)
				{
					if (!moved)
					{
						var idx:Int = hitTest(items, touch.x, touch.y, camera);
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

		// 触点丢失保护(切后台等)
		if (trackedId != -1)
		{
			var still:Bool = false;
			for (t in FlxG.touches.list)
				if (t.touchPointId == trackedId && (t.pressed || t.justPressed)) { still = true; break; }
			if (!still) trackedId = -1;
		}
		#end
	}

	static function hitTest(items:Array<FlxSprite>, x:Float, y:Float, ?camera:flixel.FlxCamera):Int
	{
		if (camera == null) camera = FlxG.camera;
		x += camera.scrollX;  // 转世界坐标(菜单项 scrollFactor=1)
		y += camera.scrollY;

		var point = FlxPoint.weak(x, y);
		var result:Int = -1;
		for (i in 0...items.length)
		{
			var it = items[i];
			if (it == null || !it.exists || !it.active) continue;
			// 放大8px命中区, 方便手指点小字
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
