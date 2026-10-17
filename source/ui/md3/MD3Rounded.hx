package ui.md3;

import flixel.graphics.FlxGraphic;

/**
 * 圆角矩形位图工厂。
 * 统一生成白色底图, 用 .color 着色即可获得任意颜色 (位图按尺寸缓存复用)。
 */
class MD3Rounded
{
	static var cache:Map<String, FlxGraphic> = new Map();

	public static function get(w:Float, h:Float, radius:Float):FlxGraphic
	{
		var iw:Int = Math.round(w);
		var ih:Int = Math.round(h);
		var ir:Int = Math.round(radius);
		var key:String = 'MD3R_' + iw + '_' + ih + '_' + ir;
		if (cache.exists(key)) return cache.get(key);

		var bd = new openfl.display.BitmapData(iw, ih, true, 0x00000000);
		var shape = new openfl.display.Shape();
		shape.graphics.beginFill(0xFFFFFF, 1);
		shape.graphics.drawRoundRect(0, 0, iw, ih, ir, ir);
		shape.graphics.endFill();
		bd.draw(shape, null, null, null, null, true);

		var g = FlxGraphic.fromBitmapData(bd, false, key);
		cache.set(key, g);
		return g;
	}
}
