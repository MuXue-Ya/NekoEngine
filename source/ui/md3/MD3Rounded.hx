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

	/**
	 * 自绘返回箭头(白色线条, 用 FlxSprite.color 染色)。
	 * size = 画布边长, thickness = 线条粗细。
	 */
	public static function createBackArrow(size:Int, thickness:Int):openfl.display.BitmapData
	{
		if (size < 8) size = 8;
		if (thickness < 1) thickness = 1;
		var bd = new openfl.display.BitmapData(size, size, true, 0x00000000);
		var shape = new openfl.display.Shape();
		var c:Float = size / 2;
		var x0:Float = c - size * 0.16;  // 箭尖
		var x1:Float = c + size * 0.18;  // 尾部
		var head:Float = size * 0.14;    // 箭头翼展
		shape.graphics.lineStyle(thickness, 0xFFFFFF, 1);
		shape.graphics.moveTo(x1, c);
		shape.graphics.lineTo(x0, c);
		shape.graphics.moveTo(x0 + head, c - head);
		shape.graphics.lineTo(x0, c);
		shape.graphics.lineTo(x0 + head, c + head);
		shape.graphics.endFill();
		bd.draw(shape, null, null, null, null, true);
		return bd;
	}

	/**
	 * 自绘重置图标(圆弧箭头, 白色线条, 用 FlxSprite.color 染色)。
	 */
	public static function createResetIcon(size:Int, thickness:Int):openfl.display.BitmapData
	{
		if (size < 8) size = 8;
		if (thickness < 1) thickness = 1;
		var bd = new openfl.display.BitmapData(size, size, true, 0x00000000);
		var shape = new openfl.display.Shape();
		var c:Float = size / 2;
		var r:Float = size * 0.27;
		var a0:Float = -1.1;
		var a1:Float = 3.9;
		shape.graphics.lineStyle(thickness, 0xFFFFFF, 1);
		shape.graphics.moveTo(c + r * Math.cos(a0), c + r * Math.sin(a0));
		var steps:Int = 26;
		for (i in 1...(steps + 1))
		{
			var t:Float = a0 + (a1 - a0) * i / steps;
			shape.graphics.lineTo(c + r * Math.cos(t), c + r * Math.sin(t));
		}
		// 箭头: 弧线末端沿切线方向画两翼
		var ex:Float = c + r * Math.cos(a1);
		var ey:Float = c + r * Math.sin(a1);
		var tang:Float = Math.atan2(Math.cos(a1), -Math.sin(a1));
		var hl:Float = size * 0.17;
		for (s in [-1.0, 1.0])
		{
			var wa:Float = tang + s * 2.55;
			shape.graphics.moveTo(ex, ey);
			shape.graphics.lineTo(ex + hl * Math.cos(wa), ey + hl * Math.sin(wa));
		}
		shape.graphics.endFill();
		bd.draw(shape, null, null, null, null, true);
		return bd;
	}
}
