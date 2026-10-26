package substates;

import flixel.input.touch.FlxTouch;
import ui.md3.MD3Rounded;
import ui.md3.MD3Theme;
import ui.md3.MD3Switch;

/**
 * 玩法调整 (MD3):
 *   滚动类型/滚动速度/回放速率/回血倍率/扣血倍率/一击必杀/练习模式/猫娘替你打喵
 * 触控: 点行选中, bool行点开关切换, 数值行点◀▶单步调整; 键盘: 上下/左右(长按连调)/回车/RESET恢复默认
 * GameplayOption 逻辑类原样保留。
 */
class GameplayChangersSubstate extends MusicBeatSubstate
{
	private var curOption:GameplayOption = null;
	private var curSelected:Int = 0;
	private var optionsArray:Array<Dynamic> = [];

	// 每行成员的平行数组(下标严格对应 optionsArray)
	var rowCards:Array<FlxSprite> = [];
	var rowLabels:Array<FlxText> = [];
	var rowValues:Array<FlxText> = [];
	var rowSwitches:Array<MD3Switch> = [];
	var rowDecL:Array<FlxSprite> = [];
	var rowDecR:Array<FlxSprite> = [];

	var backBtn:FlxSprite;
	var resetBtn:FlxSprite;
	// 触控状态机: 0=无 1=待定 2=纵向导航(滑动换行) 3=横向调值(仅数值行)
	var tId:Int = -1;
	var tState:Int = 0;
	var tRow:Int = -1;
	var tStartX:Float = 0;
	var tStartY:Float = 0;
	var tLastX:Float = 0;
	var tLastY:Float = 0;
	var tNavY:Float = 0;

	#if mobile
	// 触控诊断(本轮验证用): 红点=引擎认为的触点位置, 底部红字=坐标+命中行, 抬手停留0.6秒便于截图
	public static var touchDebug:Bool = true;
	var dbgDot:FlxSprite;
	var dbgText:FlxText;
	var dbgHold:Float = 0;
	#end

	function getOptions()
	{
		var goption:GameplayOption = new GameplayOption('Scroll Type', 'scrolltype', 'string', 'multiplicative', ["multiplicative", "constant"]);
		optionsArray.push(goption);

		var option:GameplayOption = new GameplayOption('Scroll Speed', 'scrollspeed', 'float', 1);
		option.scrollSpeed = 2.0;
		option.minValue = 0.35;
		option.changeValue = 0.05;
		option.decimals = 2;
		if (goption.getValue() != "constant")
		{
			option.displayFormat = '%vX';
			option.maxValue = 3;
		}
		else
		{
			option.displayFormat = "%v";
			option.maxValue = 6;
		}
		optionsArray.push(option);

		#if FLX_PITCH
		var option:GameplayOption = new GameplayOption('Playback Rate', 'songspeed', 'float', 1);
		option.scrollSpeed = 1;
		option.minValue = 0.5;
		option.maxValue = 3.0;
		option.changeValue = 0.05;
		option.displayFormat = '%vX';
		option.decimals = 2;
		optionsArray.push(option);
		#end

		var option:GameplayOption = new GameplayOption('Health Gain Multiplier', 'healthgain', 'float', 1);
		option.scrollSpeed = 2.5;
		option.minValue = 0;
		option.maxValue = 5;
		option.changeValue = 0.1;
		option.displayFormat = '%vX';
		optionsArray.push(option);

		var option:GameplayOption = new GameplayOption('Health Loss Multiplier', 'healthloss', 'float', 1);
		option.scrollSpeed = 2.5;
		option.minValue = 0.5;
		option.maxValue = 5;
		option.changeValue = 0.1;
		option.displayFormat = '%vX';
		optionsArray.push(option);

		optionsArray.push(new GameplayOption('Instakill on Miss', 'instakill', 'bool', false));
		optionsArray.push(new GameplayOption('Practice Mode', 'practice', 'bool', false));
		optionsArray.push(new GameplayOption('Botplay', 'botplay', 'bool', false));
		optionsArray.push(new GameplayOption('Smooth Health Bar', 'smoothhealth', 'bool', true));
	}

	public function getOptionByName(name:String)
	{
		for(i in optionsArray)
		{
			var opt:GameplayOption = i;
			if (opt.name == name)
				return opt;
		}
		return null;
	}

	// 内部名 -> 中文标签
	function getLabel(name:String):String
	{
		return switch (name)
		{
			case 'Scroll Type': '滚动类型';
			case 'Scroll Speed': '滚动速度';
			case 'Playback Rate': '回放速率';
			case 'Health Gain Multiplier': '回血倍率';
			case 'Health Loss Multiplier': '扣血倍率';
			case 'Instakill on Miss': '一击必杀';
			case 'Practice Mode': '练习模式';
			case 'Botplay': '猫娘替你打喵';
			case 'Smooth Health Bar': '平滑血条';
			default: name;
		}
	}

	public function new()
	{
		super();

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, MD3Theme.surface);
		bg.alpha = 0.88;
		add(bg);

		var title:FlxText = new FlxText(0, 20, FlxG.width, '玩法调整', 30);
		title.setFormat(Paths.font('vcr.ttf'), 30, MD3Theme.onSurface, CENTER);
		add(title);

		// 左上返回 / 右上恢复默认
		backBtn = new FlxSprite(36, 18);
		backBtn.pixels = MD3Rounded.createBitmap(44, 44, 22);
		backBtn.color = MD3Theme.surfaceContainerHigh;
		add(backBtn);
		var backIcon:FlxSprite = new FlxSprite(backBtn.x + 8, backBtn.y + 8);
		backIcon.pixels = MD3Rounded.createBackArrow(28, 3);
		backIcon.color = 0xFFFFFFFF;
		add(backIcon);

		resetBtn = new FlxSprite(FlxG.width - 36 - 44, 18);
		resetBtn.pixels = MD3Rounded.createBitmap(44, 44, 22);
		resetBtn.color = MD3Theme.surfaceContainerHigh;
		add(resetBtn);
		var resetIcon:FlxSprite = new FlxSprite(resetBtn.x + 8, resetBtn.y + 8);
		resetIcon.pixels = MD3Rounded.createResetIcon(28, 3);
		resetIcon.color = 0xFFFFFFFF;
		add(resetIcon);

		getOptions();

		for (i in 0...optionsArray.length)
		{
			var opt:GameplayOption = optionsArray[i];
			var cy:Float = 96 + i * 62;

			var card:FlxSprite = new FlxSprite(60, cy);
			card.pixels = MD3Rounded.createBitmap(1160, 52, 12);
			card.color = MD3Theme.surfaceContainer;
			add(card);
			rowCards.push(card);

			var label:FlxText = new FlxText(84, cy + 14, 0, getLabel(opt.name), 20);
			label.setFormat(Paths.font('vcr.ttf'), 20, MD3Theme.onSurface);
			add(label);
			rowLabels.push(label);

			if(opt.type == 'bool')
			{
				var optRef:GameplayOption = opt;
				var sw:MD3Switch = new MD3Switch(1120, cy + 10, opt.getValue() == true, function(v:Bool)
				{
					optRef.setValue(v);
					optRef.change();
					FlxG.sound.play(Paths.sound('scrollMenu'));
				});
				add(sw);
				rowSwitches.push(sw);
				rowValues.push(null);
				rowDecL.push(null);
				rowDecR.push(null);
			}
			else
			{
				rowSwitches.push(null);	// 平行数组占位: 保证 rowSwitches[i] 与 optionsArray[i] 严格对应(修复开关视觉错刷)
				var valT:FlxText = new FlxText(830, cy + 14, 230, '', 18);
				valT.setFormat(Paths.font('vcr.ttf'), 18, MD3Theme.onSurfaceVariant, RIGHT);
				add(valT);
				rowValues.push(valT);

				var decL:FlxSprite = new FlxSprite(1080, cy + 10);
				decL.pixels = MD3Rounded.createBitmap(32, 32, 8);
				decL.color = MD3Theme.primaryContainer;
				add(decL);
				var decLText:FlxText = new FlxText(0, 0, 0, '<', 14);
				decLText.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onPrimaryContainer, CENTER);
				decLText.setPosition(decL.x + (32 - decLText.width) / 2, decL.y + 8);
				add(decLText);
				rowDecL.push(decL);

				var decR:FlxSprite = new FlxSprite(1160, cy + 10);
				decR.pixels = MD3Rounded.createBitmap(32, 32, 8);
				decR.color = MD3Theme.primaryContainer;
				add(decR);
				var decRText:FlxText = new FlxText(0, 0, 0, '>', 14);
				decRText.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onPrimaryContainer, CENTER);
				decRText.setPosition(decR.x + (32 - decRText.width) / 2, decR.y + 8);
				add(decRText);
				rowDecR.push(decR);

				updateTextFrom(opt);
			}
		}

		#if mobile
		if (touchDebug)
		{
			dbgDot = new FlxSprite();
			dbgDot.pixels = MD3Rounded.createBitmap(18, 18, 9);
			dbgDot.color = 0xFFFF4D6A;
			dbgDot.alpha = 0.85;
			dbgDot.visible = false;
			add(dbgDot);

			dbgText = new FlxText(0, 688, FlxG.width, '', 16);
			dbgText.setFormat(Paths.font('vcr.ttf'), 16, 0xFFFF4D6A, CENTER);
			dbgText.visible = false;
			add(dbgText);
		}
		#end

		changeSelection();
	}

	var nextAccept:Int = 5;
	var holdTime:Float = 0;
	var holdValue:Float = 0;

	override function update(elapsed:Float)
	{
		if (controls.UI_UP_P)
			changeSelection(-1);
		if (controls.UI_DOWN_P)
			changeSelection(1);

		if (controls.BACK)
			doClose();

		#if mobile
		handleTouch(elapsed);
		#end

		if(nextAccept <= 0)
		{
			if(curOption.type == 'bool')
			{
				if(controls.ACCEPT)
					toggleBool(curSelected);
			} else {
				if(controls.UI_LEFT || controls.UI_RIGHT) {
					var pressed = (controls.UI_LEFT_P || controls.UI_RIGHT_P);
					if(holdTime > 0.5 || pressed) {
						if(pressed) {
							adjustOption(curOption, controls.UI_LEFT ? -1 : 1);
						} else if(curOption.type != 'string') {
							holdValue = Math.max(curOption.minValue, Math.min(curOption.maxValue, holdValue + curOption.scrollSpeed * elapsed * (controls.UI_LEFT ? -1 : 1)));

							switch(curOption.type)
							{
								case 'int':
									curOption.setValue(Math.round(holdValue));

								case 'float' | 'percent':
									var blah:Float = Math.max(curOption.minValue, Math.min(curOption.maxValue, holdValue + curOption.changeValue - (holdValue % curOption.changeValue)));
									curOption.setValue(FlxMath.roundDecimal(blah, curOption.decimals));
							}
							updateTextFrom(curOption);
							curOption.change();
						}
					}

					if(curOption.type != 'string') {
						holdTime += elapsed;
					}
				} else if(controls.UI_LEFT_R || controls.UI_RIGHT_R) {
					clearHold();
				}
			}

			if(controls.RESET)
				resetAll();
		}

		if(nextAccept > 0) {
			nextAccept -= 1;
		}
		super.update(elapsed);
	}

	// ===== 触控 =====
	#if mobile
	function handleTouch(elapsed:Float):Void
	{
		// 结束检测(手指抬起/丢失/被池化回收)
		if (tId != -1)
		{
			var still:Bool = false;
			for (touch in FlxG.touches.list)
				if (touch.touchPointID == tId && (touch.pressed || touch.justPressed || touch.justReleased)) { still = true; break; }
			if (!still)
			{
				tId = -1;
				tState = 0;
				tRow = -1;
			}
		}

		for (touch in FlxG.touches.list)
		{
			// 新按下: 无条件接管(防僵尸触点把 tId 卡死导致后续点按全部失效)
			if (touch.justPressed)
			{
				tId = touch.touchPointID;
				tState = 0;
				tRow = -1;
				// 手势基准全部重置为本次按下位置(旧代码残留上次手势的 tStart/tLast/tNav, 会污染方向判定与调值步进)
				tStartX = touch.x;
				tStartY = touch.y;
				tLastX = touch.x;
				tLastY = touch.y;
				tNavY = touch.y;

				var dbgDesc:String = '无命中';
				if (hitSpr(touch, backBtn)) { dbgDesc = '返回'; doClose(); }
				else if (hitSpr(touch, resetBtn)) { dbgDesc = '恢复默认'; resetAll(); }
				else
				{
					for (i in 0...rowCards.length)
					{
						var card:FlxSprite = rowCards[i];
						if (touch.x >= card.x && touch.x <= card.x + card.width && touch.y >= card.y && touch.y <= card.y + card.height)
						{
							tRow = i;
							dbgDesc = '行' + i + ':' + getLabel(optionsArray[i].name);
							selectTo(i);
							var opt:GameplayOption = optionsArray[i];
							if (opt.type == 'bool')
							{
								toggleBool(i);	// bool行: 按下即切换, 手势剩余部分忽略
								tState = 0;
							}
							else if (hitSpr(touch, rowDecL[i]))
								adjustOption(opt, -1);
							else if (hitSpr(touch, rowDecR[i]))
								adjustOption(opt, 1);
							else
								tState = 1;	// 待定: 纵向滑动=导航 / 横向拖动=调值
							break;
						}
					}
				}
				backend.PerfProbe.log('[触控] down x=' + Math.round(touch.x) + ' y=' + Math.round(touch.y) + ' ' + dbgDesc);
				if (touchDebug)
				{
					dbgHold = 0.6;
					dbgText.text = '触点 x=' + Math.round(touch.x) + ' y=' + Math.round(touch.y) + '  ' + dbgDesc;
					dbgDot.setPosition(touch.x - 9, touch.y - 9);
				}
				continue;
			}

			if (touch.touchPointID != tId || !touch.pressed) continue;

			var dx:Float = touch.x - tLastX;
			var dy:Float = touch.y - tLastY;
			tLastX = touch.x;
			tLastY = touch.y;
			if (touchDebug)
			{
				dbgHold = 0.6;
				dbgDot.setPosition(touch.x - 9, touch.y - 9);
			}

			// 方向判定: 纵向=导航, 横向(仅数值行)=调值
			if (tState == 1)
			{
				if (Math.abs(touch.y - tStartY) > 20)
					tState = 2;
				else if (Math.abs(touch.x - tStartX) > 20 && tRow != -1 && optionsArray[tRow].type != 'bool')
					tState = 3;
			}

			if (tState == 2)
			{
				while (touch.y - tNavY > 55) { tNavY += 55; changeSelection(1); }
				while (tNavY - touch.y > 55) { tNavY -= 55; changeSelection(-1); }
			}
			else if (tState == 3 && tRow != -1)
			{
				var opt:GameplayOption = optionsArray[tRow];
				if (opt.type != 'string')
				{
					holdValue = Math.max(opt.minValue, Math.min(opt.maxValue, holdValue + opt.changeValue * dx / 30));
					switch(opt.type)
					{
						case 'int':
							opt.setValue(Math.round(holdValue));
						case 'float' | 'percent':
							opt.setValue(FlxMath.roundDecimal(holdValue, opt.decimals));
					}
					updateTextFrom(opt);
					opt.change();
				}
			}
		}

		if (touchDebug && dbgDot != null)
		{
			if (dbgHold > 0)
			{
				dbgHold -= elapsed;
				dbgDot.visible = true;
				dbgText.visible = true;
			}
			else
			{
				dbgDot.visible = false;
				dbgText.visible = false;
			}
		}
	}

	function hitSpr(touch:FlxTouch, spr:FlxSprite):Bool
	{
		if (spr == null || !spr.visible) return false;
		return touch.x >= spr.x - 6 && touch.x <= spr.x + spr.width + 6
			&& touch.y >= spr.y - 6 && touch.y <= spr.y + spr.height + 6;
	}
	#end

	// ===== 动作(键盘与触控共用) =====

	function doClose():Void
	{
		ClientPrefs.saveSettings();
		FlxG.sound.play(Paths.sound('cancelMenu'));
		close();
	}

	var lastToggleIdx:Int = -1;
	var lastToggleTime:Float = 0;
	function toggleBool(i:Int):Void
	{
		var now:Float = haxe.Timer.stamp();
		if (i == lastToggleIdx && now - lastToggleTime < 0.2) return;	// 同行0.2秒内重复触发=触点抖动, 忽略
		lastToggleIdx = i;
		lastToggleTime = now;
		var opt:GameplayOption = optionsArray[i];
		FlxG.sound.play(Paths.sound('scrollMenu'));
		opt.setValue((opt.getValue() == true) ? false : true);
		opt.change();
		syncSwitches();
	}

	function adjustOption(opt:GameplayOption, dir:Int):Void
	{
		if (opt.type == 'string')
		{
			cycleStringOption(opt, dir);
			return;
		}
		// int/float/percent: 单步调整
		holdValue = opt.getValue() + dir * opt.changeValue;
		if(holdValue < opt.minValue) holdValue = opt.minValue;
		else if(holdValue > opt.maxValue) holdValue = opt.maxValue;

		switch(opt.type)
		{
			case 'int':
				holdValue = Math.round(holdValue);
				opt.setValue(holdValue);
			case 'float' | 'percent':
				holdValue = FlxMath.roundDecimal(holdValue, opt.decimals);
				opt.setValue(holdValue);
		}
		updateTextFrom(opt);
		opt.change();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	function cycleStringOption(opt:GameplayOption, dir:Int):Void
	{
		var num:Int = opt.curOption;
		num += dir;
		if(num < 0) num = opt.options.length - 1;
		else if(num >= opt.options.length) num = 0;
		opt.curOption = num;
		opt.setValue(opt.options[num]);

		if (opt.name == "Scroll Type")
		{
			var oOption:GameplayOption = getOptionByName("Scroll Speed");
			if (oOption != null)
			{
				if (opt.getValue() == "constant")
				{
					oOption.displayFormat = "%v";
					oOption.maxValue = 6;
				}
				else
				{
					oOption.displayFormat = "%vX";
					oOption.maxValue = 3;
					if(oOption.getValue() > 3) oOption.setValue(3);
				}
				updateTextFrom(oOption);
			}
		}
		updateTextFrom(opt);
		opt.change();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	function resetAll():Void
	{
		for (i in 0...optionsArray.length)
		{
			var leOption:GameplayOption = optionsArray[i];
			leOption.setValue(leOption.defaultValue);
			if(leOption.type != 'bool')
			{
				if(leOption.type == 'string')
				{
					leOption.curOption = leOption.options.indexOf(leOption.getValue());
				}
				updateTextFrom(leOption);
			}

			if(leOption.name == 'Scroll Speed')
			{
				leOption.displayFormat = "%vX";
				leOption.maxValue = 3;
				if(leOption.getValue() > 3)
				{
					leOption.setValue(3);
				}
				updateTextFrom(leOption);
			}
			leOption.change();
		}
		FlxG.sound.play(Paths.sound('cancelMenu'));
		syncSwitches();
	}

	// ===== 视觉同步 =====

	// 值文字: 写到本行 FlxText(不再走 Alphabet child 代理)
	function updateTextFrom(option:GameplayOption) {
		var idx:Int = optionsArray.indexOf(option);
		if (idx < 0 || idx >= rowValues.length || rowValues[idx] == null) return;
		var text:String = option.displayFormat;
		var val:Dynamic = option.getValue();
		if (option.name == 'Scroll Type')
			val = (val == 'constant') ? '固定' : '倍增';
		rowValues[idx].text = text.replace('%v', Std.string(val)).replace('%d', Std.string(option.defaultValue));
	}

	function clearHold()
	{
		if(holdTime > 0.5) {
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}
		holdTime = 0;
	}

	function changeSelection(change:Int = 0)
	{
		curSelected += change;
		if (curSelected < 0)
			curSelected = optionsArray.length - 1;
		if (curSelected >= optionsArray.length)
			curSelected = 0;

		curOption = optionsArray[curSelected];

		for (i in 0...rowCards.length)
			rowCards[i].color = (i == curSelected) ? MD3Theme.primaryContainer : MD3Theme.surfaceContainer;

		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	function selectTo(i:Int):Void
	{
		if (i < 0 || i >= optionsArray.length) return;
		curSelected = i;
		curOption = optionsArray[i];
		for (j in 0...rowCards.length)
			rowCards[j].color = (j == curSelected) ? MD3Theme.primaryContainer : MD3Theme.surfaceContainer;
	}

	function syncSwitches():Void
	{
		for (i in 0...rowSwitches.length)
			if (rowSwitches[i] != null)
				rowSwitches[i].on = (optionsArray[i].getValue() == true);
	}
}

class GameplayOption
{
	private var child:Alphabet;
	public var text(get, set):String;
	public var onChange:Void->Void = null; //Pressed enter (on Bool type options) or pressed/held left/right (on other types)

	public var type(get, default):String = 'bool'; //bool, int (or integer), float (or fl), percent, string (or str)
	// Bool will use checkboxes
	// Everything else will use a text

	public var showBoyfriend:Bool = false;
	public var scrollSpeed:Float = 50; //Only works on int/float, defines how fast it scrolls per second while holding left/right

	private var variable:String = null; //Variable from ClientPrefs.hx's gameplaySettings
	public var defaultValue:Dynamic = null;

	public var curOption:Int = 0; //Don't change this
	public var options:Array<String> = null; //Only used in string type
	public var changeValue:Dynamic = 1; //Only used in int/float/percent type, how much is changed when you PRESS
	public var minValue:Dynamic = null; //Only used in int/float/percent type
	public var maxValue:Dynamic = null; //Only used in int/float/percent type
	public var decimals:Int = 1; //Only used in float/percent type

	public var displayFormat:String = '%v'; //How String/Float/Percent/Int values are shown, %v = Current value, %d = Default value
	public var name:String = 'Unknown';

	public function new(name:String, variable:String, type:String = 'bool', defaultValue:Dynamic = 'null variable value', ?options:Array<String> = null)
	{
		this.name = name;
		this.variable = variable;
		this.type = type;
		this.defaultValue = defaultValue;
		this.options = options;

		if(defaultValue == 'null variable value')
		{
			switch(type)
			{
				case 'bool':
					defaultValue = false;
				case 'int' | 'float':
					defaultValue = 0;
				case 'percent':
					defaultValue = 1;
				case 'string':
					defaultValue = '';
					if(options.length > 0) {
						defaultValue = options[0];
					}
			}
		}

		if(getValue() == null) {
			setValue(defaultValue);
		}

		switch(type)
		{
			case 'string':
				var num:Int = options.indexOf(getValue());
				if(num > -1) {
					curOption = num;
				}
	
			case 'percent':
				displayFormat = '%v%';
				changeValue = 0.01;
				minValue = 0;
				maxValue = 1;
				scrollSpeed = 0.5;
				decimals = 2;
		}
	}

	public function change()
	{
		//nothing lol
		if(onChange != null) {
			onChange();
		}
	}

	public function getValue():Dynamic
	{
		return ClientPrefs.data.gameplaySettings.get(variable);
	}
	public function setValue(value:Dynamic)
	{
		ClientPrefs.data.gameplaySettings.set(variable, value);
	}

	public function setChild(child:Alphabet)
	{
		this.child = child;
	}

	private function get_text()
	{
		if(child != null) {
			return child.text;
		}
		return null;
	}
	private function set_text(newValue:String = '')
	{
		if(child != null) {
			child.text = newValue;
		}
		return null;
	}

	private function get_type()
	{
		var newValue:String = 'bool';
		switch(type.toLowerCase().trim())
		{
			case 'int' | 'float' | 'percent' | 'string': newValue = type;
			case 'integer': newValue = 'int';
			case 'str': newValue = 'string';
			case 'fl': newValue = 'float';
		}
		type = newValue;
		return type;
	}
}