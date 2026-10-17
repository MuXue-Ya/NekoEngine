package options;

import flixel.FlxG;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.text.FlxText;

/**
 * 设置菜单的选项名文字。
 * 用 FlxText 代替 Alphabet(图片字母), 让中文正常渲染;
 * 同时复刻 Alphabet 的菜单滚动定位(targetY 缓动)以保持原版手感。
 */
class OptionNameText extends FlxText
{
	public var isMenuItem:Bool = false;
	public var targetY:Int = 0;
	public var distancePerItem:FlxPoint = new FlxPoint(20, 120);
	public var startPosition:FlxPoint = new FlxPoint(0, 0);
	public var changeX:Bool = true;
	public var changeY:Bool = true;

	public function new(x:Float, y:Float, text:String, size:Int = 20)
	{
		super(x, y, 0, text, size);
		startPosition.x = x;
		startPosition.y = y;
		setFormat(Paths.font("vcr.ttf"), size, flixel.util.FlxColor.WHITE, LEFT, flixel.text.FlxTextBorderStyle.OUTLINE, flixel.util.FlxColor.BLACK);
		borderSize = 2;
	}

	override function update(elapsed:Float)
	{
		if (isMenuItem)
		{
			var lerpVal:Float = Math.exp(-elapsed * 9.6);
			if (changeX)
				x = FlxMath.lerp((targetY * distancePerItem.x) + startPosition.x, x, lerpVal);
			if (changeY)
				y = FlxMath.lerp((targetY * 1.3 * distancePerItem.y) + startPosition.y, y, lerpVal);
		}
		super.update(elapsed);
	}
}
