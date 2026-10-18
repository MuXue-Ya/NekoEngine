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

	// ==================== 主菜单自绘图标(白色线条, 用 FlxSprite.color 染色) ====================

	/** 主菜单入口图标分发: 按入口名返回对应位图 */
	public static function createMenuIcon(name:String, size:Int, thickness:Int):openfl.display.BitmapData
	{
		return switch (name)
		{
			case 'story_mode': createIconFlag(size, thickness);
			case 'freeplay': createIconNote(size, thickness);
			case 'mods': createIconMod(size, thickness);
			case 'awards': createIconStar(size, thickness);
			case 'credits': createIconPerson(size, thickness);
			case 'options': createIconSliders(size, thickness);
			default: createIconStar(size, thickness);
		}
	}

	static function newIconCanvas(size:Int):openfl.display.BitmapData
	{
		return new openfl.display.BitmapData(size, size, true, 0x00000000);
	}

	/** 故事模式: 旗帜 */
	public static function createIconFlag(size:Int, thickness:Int):openfl.display.BitmapData
	{
		var bd = newIconCanvas(size);
		var s = new openfl.display.Shape();
		s.graphics.lineStyle(thickness, 0xFFFFFF, 1);
		s.graphics.moveTo(size * 0.3, size * 0.12);			// 旗杆
		s.graphics.lineTo(size * 0.3, size * 0.88);
		s.graphics.moveTo(size * 0.3, size * 0.14);			// 旗面
		s.graphics.lineTo(size * 0.78, size * 0.27);
		s.graphics.lineTo(size * 0.3, size * 0.44);
		bd.draw(s, null, null, null, null, true);
		return bd;
	}

	/** 自由游戏: 八分音符 */
	public static function createIconNote(size:Int, thickness:Int):openfl.display.BitmapData
	{
		var bd = newIconCanvas(size);
		var s = new openfl.display.Shape();
		s.graphics.lineStyle(thickness, 0xFFFFFF, 1);
		s.graphics.moveTo(size * 0.64, size * 0.14);		// 符杆
		s.graphics.lineTo(size * 0.64, size * 0.72);
		s.graphics.moveTo(size * 0.64, size * 0.14);		// 符尾
		s.graphics.lineTo(size * 0.36, size * 0.28);
		s.graphics.beginFill(0xFFFFFF, 1);					// 符头(实心圆)
		s.graphics.drawCircle(size * 0.44, size * 0.76, size * 0.13);
		s.graphics.endFill();
		bd.draw(s, null, null, null, null, true);
		return bd;
	}

	/** 模组: 箱子+加号 */
	public static function createIconMod(size:Int, thickness:Int):openfl.display.BitmapData
	{
		var bd = newIconCanvas(size);
		var s = new openfl.display.Shape();
		s.graphics.lineStyle(thickness, 0xFFFFFF, 1);
		s.graphics.drawRoundRect(size * 0.16, size * 0.16, size * 0.68, size * 0.68, thickness * 2, thickness * 2);
		s.graphics.moveTo(size * 0.5, size * 0.34);			// 加号
		s.graphics.lineTo(size * 0.5, size * 0.66);
		s.graphics.moveTo(size * 0.34, size * 0.5);
		s.graphics.lineTo(size * 0.66, size * 0.5);
		bd.draw(s, null, null, null, null, true);
		return bd;
	}

	/** 成就: 五角星 */
	public static function createIconStar(size:Int, thickness:Int):openfl.display.BitmapData
	{
		var bd = newIconCanvas(size);
		var s = new openfl.display.Shape();
		s.graphics.lineStyle(thickness, 0xFFFFFF, 1);
		var c:Float = size / 2;
		var ro:Float = size * 0.42;
		var ri:Float = size * 0.17;
		for (i in 0...10)
		{
			var ang:Float = -Math.PI / 2 + i * Math.PI / 5;
			var r:Float = (i % 2 == 0) ? ro : ri;
			var px:Float = c + r * Math.cos(ang);
			var py:Float = c + r * Math.sin(ang);
			if (i == 0) s.graphics.moveTo(px, py);
			else s.graphics.lineTo(px, py);
		}
		s.graphics.lineTo(c, c - ro);
		bd.draw(s, null, null, null, null, true);
		return bd;
	}

	/** 制作组: 头像(圆头+圆角方肩) */
	public static function createIconPerson(size:Int, thickness:Int):openfl.display.BitmapData
	{
		var bd = newIconCanvas(size);
		var s = new openfl.display.Shape();
		s.graphics.lineStyle(thickness, 0xFFFFFF, 1);
		s.graphics.drawCircle(size * 0.5, size * 0.32, size * 0.15);
		s.graphics.drawRoundRect(size * 0.24, size * 0.56, size * 0.52, size * 0.32, size * 0.16, size * 0.16);
		bd.draw(s, null, null, null, null, true);
		return bd;
	}

	/** 设置: 调音台滑杆 */
	public static function createIconSliders(size:Int, thickness:Int):openfl.display.BitmapData
	{
		var bd = newIconCanvas(size);
		var s = new openfl.display.Shape();
		s.graphics.lineStyle(thickness, 0xFFFFFF, 1);
		s.graphics.moveTo(size * 0.15, size * 0.25);
		s.graphics.lineTo(size * 0.85, size * 0.25);
		s.graphics.moveTo(size * 0.15, size * 0.5);
		s.graphics.lineTo(size * 0.85, size * 0.5);
		s.graphics.moveTo(size * 0.15, size * 0.75);
		s.graphics.lineTo(size * 0.85, size * 0.75);
		s.graphics.beginFill(0xFFFFFF, 1);
		s.graphics.drawCircle(size * 0.36, size * 0.25, size * 0.09);
		s.graphics.drawCircle(size * 0.68, size * 0.5, size * 0.09);
		s.graphics.drawCircle(size * 0.46, size * 0.75, size * 0.09);
		s.graphics.endFill();
		bd.draw(s, null, null, null, null, true);
		return bd;
	}

	/** 猫耳(两只白色实心三角, 用 FlxSprite.color 染成 primary), 用于标题装饰 */
	public static function createCatEars(width:Int, height:Int):openfl.display.BitmapData
	{
		var bd = new openfl.display.BitmapData(width, height, true, 0x00000000);
		var s = new openfl.display.Shape();
		var earW:Float = width * 0.42;
		var gap:Float = width * 0.16;
		s.graphics.beginFill(0xFFFFFF, 1);
		s.graphics.moveTo(0, height);
		s.graphics.lineTo(earW * 0.5, 0);
		s.graphics.lineTo(earW, height);
		s.graphics.endFill();
		s.graphics.beginFill(0xFFFFFF, 1);
		var rx:Float = earW + gap;
		s.graphics.moveTo(rx, height);
		s.graphics.lineTo(rx + earW * 0.5, 0);
		s.graphics.lineTo(rx + earW, height);
		s.graphics.endFill();
		bd.draw(s, null, null, null, null, true);
		return bd;
	}
}
