package ui.md3;

/**
 * 圆角矩形位图工厂。
 * 返回裸 BitmapData, 配合 FlxSprite.pixels = ... 使用(绕开 FlxGraphic 缓存链)。
 * 白色底图, 用 FlxSprite.color 着色获得任意颜色。
 */
class MD3Rounded
{
	public static function createBitmap(w:Float, h:Float, radius:Float):openfl.display.BitmapData
	{
		var iw:Int = Math.round(w);
		var ih:Int = Math.round(h);
		var ir:Int = Math.round(radius);
		if (iw < 1) iw = 1;
		if (ih < 1) ih = 1;
		if (ir < 1) ir = 1;
		if (ir > Std.int(Math.min(iw, ih) / 2)) ir = Std.int(Math.min(iw, ih) / 2);

		var bd = new openfl.display.BitmapData(iw, ih, true, 0x00000000);
		var shape = new openfl.display.Shape();
		shape.graphics.beginFill(0xFFFFFF, 1);
		shape.graphics.drawRoundRect(0, 0, iw, ih, ir * 2, ir * 2);
		shape.graphics.endFill();
		bd.draw(shape, null, null, null, null, true);
		return bd;
	}
}
