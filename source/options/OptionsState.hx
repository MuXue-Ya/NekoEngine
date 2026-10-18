package options;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import states.MainMenuState;
import ui.md3.MD3Switch;
import ui.md3.MD3Slider;
import ui.md3.MD3Theme;
import ui.md3.MD3Rounded;
import mobile.backend.utils.TouchMenuUtil;

/**
 * 双面板设置屏:
 *   左面板 = 分区列表(视觉效果/游戏玩法/图像设置 + 三个独立工具页)
 *   右面板 = 当前分区的选项卡片列表 + 底部说明
 * 触控: 点分类切换 / 点选项选中 / 点已选中确认 / 上下滑动逐项移动
 */
class OptionsState extends MusicBeatState
{
	public static var onPlayState:Bool = false;

	// ===== 分类定义 =====
	var inlineCats:Array<String> = ['视觉效果', '游戏玩法', '图像设置'];
	var specialCats:Array<String> = ['音符颜色', '按键设置', '延迟与连击校准'];
	var allCats:Array<String> = [];

	var curCat:Int = 0;
	var curSelected:Int = 0;
	var scrollOffset:Int = 0;
	var optionsByCat:Map<String, Array<Option>> = new Map();
	var optionsArray:Array<Option> = [];

	// ===== 布局常量 =====
	var panelY:Float = 84;
	var panelH:Float = 596;
	var leftX:Float = 36;
	var leftW:Float = 270;
	var rightX:Float = 330;
	var rowsStartY:Float = 150;
	var rowSpacing:Float = 56;
	var visibleRows:Int = 7;

	// ===== UI =====
	var bg:FlxSprite;
	var leftCard:FlxSprite;
	var rightCard:FlxSprite;
	var catTexts:FlxTypedGroup<FlxText>;
	var grpOptions:FlxTypedGroup<OptionNameText>;
	var grpCards:FlxTypedGroup<FlxSprite>;
	// 开关/滑条/值文字统一容器: 切分区时整组清空, 防止上一分区的控件残留屏幕
	var grpWidgets:FlxTypedGroup<FlxSprite>;
	var optionCards:Array<FlxSprite> = [];
	var switches:Array<MD3Switch> = [];
	var sliders:Array<MD3Slider> = [];
	var valueTexts:Array<FlxText> = [];
	var rightTitle:FlxText;
	var descText:FlxText;
	var descBox:FlxSprite;

	// 右上角自绘返回按钮
	var backBtn:FlxSprite;
	var backIcon:FlxSprite;
	var backPressId:Int = -1;
	var backPressed:Bool = false;

	// 重置按钮(把当前选中的选项恢复默认值)
	var resetBtn:FlxSprite;
	var resetIcon:FlxSprite;
	var resetPressId:Int = -1;
	var resetPressed:Bool = false;

	var changedMusic:Bool = false;
	var touchAcceptFlag:Bool = false;
	var touchValueFlag:Int = 0;
	var touchStartY:Float = 0;
	var touchTracking:Bool = false;

	var curOption(get, never):Option;
	function get_curOption():Option
		return (optionsArray.length > 0 && curSelected >= 0 && curSelected < optionsArray.length) ? optionsArray[curSelected] : null;

	override function create():Void
	{
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Settings Menu", null);
		#end

		allCats = inlineCats.concat(specialCats);

		// 构建3个内嵌分类的选项
		optionsByCat.set('视觉效果', buildVisuals());
		optionsByCat.set('游戏玩法', buildGameplay());
		optionsByCat.set('图像设置', buildGraphics());

		// 背景
		bg = new FlxSprite().makeGraphic(1, 1, MD3Theme.surface);
		bg.scale.set(FlxG.width + 10, FlxG.height + 10);
		bg.updateHitbox();
		bg.screenCenter();
		add(bg);

		// 左面板(分区)
		leftCard = new FlxSprite(leftX, panelY);
		leftCard.pixels = MD3Rounded.createBitmap(leftW, panelH, 22);
		leftCard.color = MD3Theme.surfaceContainer;
		add(leftCard);
		var leftTitle = new FlxText(leftX + 24, panelY + 16, 0, "设 置", 24);
		leftTitle.setFormat(Paths.font("vcr.ttf"), 24, MD3Theme.onSurface, flixel.text.FlxTextAlign.LEFT);
		add(leftTitle);

		catTexts = new FlxTypedGroup<FlxText>();
		add(catTexts);
		for (i in 0...allCats.length)
		{
			var label:FlxText = new FlxText(leftX + 28, 0, leftW - 56, (isSpecial(allCats[i]) ? allCats[i] + "  ›" : allCats[i]), 21);
			label.setFormat(Paths.font("vcr.ttf"), 21, MD3Theme.onSurfaceVariant, flixel.text.FlxTextAlign.LEFT);
			label.ID = i;
			catTexts.add(label);
		}

		// 右面板(选项)
		rightCard = new FlxSprite(rightX, panelY);
		rightCard.pixels = MD3Rounded.createBitmap(FlxG.width - rightX - 36, panelH, 22);
		rightCard.color = MD3Theme.surfaceContainer;
		add(rightCard);

		rightTitle = new FlxText(rightX + 28, panelY + 16, 0, inlineCats[0], 24);
		rightTitle.setFormat(Paths.font("vcr.ttf"), 24, MD3Theme.primary, flixel.text.FlxTextAlign.LEFT);
		add(rightTitle);

		grpCards = new FlxTypedGroup<FlxSprite>();
		add(grpCards);
		grpOptions = new FlxTypedGroup<OptionNameText>();
		add(grpOptions);
		grpWidgets = new FlxTypedGroup<FlxSprite>();
		add(grpWidgets);

		// 说明框(右面板底部)
		descBox = new FlxSprite().makeGraphic(1, 1, MD3Theme.surfaceContainerHigh);
		descBox.alpha = 0.95;
		add(descBox);
		descText = new FlxText(rightX + 40, 0, FlxG.width - rightX - 80, "", 20);
		descText.setFormat(Paths.font("vcr.ttf"), 20, MD3Theme.onSurfaceVariant, flixel.text.FlxTextAlign.LEFT);
		add(descText);

		// 右上角自绘返回按钮(不用虚拟按键)
		backBtn = new FlxSprite(FlxG.width - 36 - 48, 18);
		backBtn.pixels = MD3Rounded.createBitmap(48, 48, 24);
		backBtn.color = MD3Theme.surfaceContainerHigh;
		add(backBtn);
		backIcon = new FlxSprite(backBtn.x, backBtn.y);
		backIcon.pixels = MD3Rounded.createBackArrow(48, 3);
		backIcon.color = MD3Theme.onSurface;
		add(backIcon);

		// 重置按钮(返回键左侧): 选中任意一行后点它 = 该行恢复默认值
		resetBtn = new FlxSprite(FlxG.width - 36 - 48 - 56, 18);
		resetBtn.pixels = MD3Rounded.createBitmap(48, 48, 24);
		resetBtn.color = MD3Theme.surfaceContainerHigh;
		add(resetBtn);
		resetIcon = new FlxSprite(resetBtn.x, resetBtn.y);
		resetIcon.pixels = MD3Rounded.createResetIcon(48, 3);
		resetIcon.color = MD3Theme.onSurface;
		add(resetIcon);

		switchCategory(0);
		ClientPrefs.saveSettings();
	}

	// ==================== 选项构建(逐字搬自三个设置页) ====================

	function buildVisuals():Array<Option>
	{
		var arr:Array<Option> = [];
		function addOption(o:Option) arr.push(o);

		var noteSkins:Array<String> = Mods.mergeAllTextsNamed('images/noteSkins/list.txt');
		if(noteSkins.length > 0)
		{
			if(!noteSkins.contains(ClientPrefs.data.noteSkin))
				ClientPrefs.data.noteSkin = ClientPrefs.defaultData.noteSkin;
			noteSkins.insert(0, ClientPrefs.defaultData.noteSkin);
			var option:Option = new Option('音符皮肤:', "选择你喜欢的音符皮肤。", 'noteSkin', 'string', noteSkins);
			addOption(option);
		}

		var noteSplashes:Array<String> = Mods.mergeAllTextsNamed('images/noteSplashes/list.txt');
		if(noteSplashes.length > 0)
		{
			if(!noteSplashes.contains(ClientPrefs.data.splashSkin))
				ClientPrefs.data.splashSkin = ClientPrefs.defaultData.splashSkin;
			noteSplashes.insert(0, ClientPrefs.defaultData.splashSkin);
			var option:Option = new Option('音符特效:', "选择音符特效样式，或直接关闭。", 'splashSkin', 'string', noteSplashes);
			addOption(option);
		}

		var option:Option = new Option('音符特效透明度', '音符特效的透明程度。', 'splashAlpha', 'percent');
		option.scrollSpeed = 1.6; option.minValue = 0.0; option.maxValue = 1; option.changeValue = 0.1; option.decimals = 1;
		addOption(option);

		var option:Option = new Option('隐藏HUD', '开启后隐藏大部分游戏界面元素。', 'hideHud', 'bool');
		addOption(option);

		var option:Option = new Option('时间条:', "时间条要显示什么内容？", 'timeBarType', 'string',
			['Time Left', 'Time Elapsed', 'Song Name', 'Disabled']);
		addOption(option);

		var option:Option = new Option('闪光效果', "如果你对闪光敏感，请关闭此项！", 'flashing', 'bool');
		addOption(option);

		var option:Option = new Option('镜头缩放', "关闭后，镜头不再随节拍缩放。", 'camZooms', 'bool');
		addOption(option);

		var option:Option = new Option('得分文字缩放', "关闭后，每次击中音符时\n得分文字不再缩放。", 'scoreZoom', 'bool');
		addOption(option);

		var option:Option = new Option('血条透明度', '血条与头像图标的透明程度。', 'healthBarAlpha', 'percent');
		option.scrollSpeed = 1.6; option.minValue = 0.0; option.maxValue = 1; option.changeValue = 0.1; option.decimals = 1;
		addOption(option);

		#if !mobile
		var option:Option = new Option('FPS 显示器', '关闭后隐藏FPS显示器。', 'showFPS', 'bool');
		option.onChange = function() { if(Main.fpsVar != null) Main.fpsVar.visible = ClientPrefs.data.showFPS; };
		addOption(option);
		#end

		var option:Option = new Option('暂停界面音乐:', "暂停界面播放哪首音乐？", 'pauseMusic', 'string',
			['None', 'Breakfast', 'Tea Time']);
		addOption(option);
		option.onChange = onChangePauseMusic;

		#if CHECK_FOR_UPDATES
		var option:Option = new Option('检查更新', '正式版游戏中，开启后启动时会检查更新。', 'checkForUpdates', 'bool');
		addOption(option);
		#end

		#if DISCORD_ALLOWED
		var option:Option = new Option('Discord 状态展示', "关闭后不在Discord展示游戏状态，\n防止意外泄露隐私。", 'discordRPC', 'bool');
		addOption(option);
		#end

		var option:Option = new Option('连击叠加', "关闭后评价与连击数字不再叠加，\n节省内存且更易读。", 'comboStacking', 'bool');
		addOption(option);

		return arr;
	}

	function buildGameplay():Array<Option>
	{
		var arr:Array<Option> = [];
		function addOption(o:Option) arr.push(o);

		var option:Option = new Option('下落模式', '开启后音符向下落，而不是向上。', 'downScroll', 'bool');
		addOption(option);

		var option:Option = new Option('居中模式', '开启后你的音符会居中显示。', 'middleScroll', 'bool');
		addOption(option);

		#if mobile
		var option:Option = new Option('隐藏判定框', '开启后判定框将不可见。', 'invisibleHitbox', 'bool');
		addOption(option);

		#if !ios
		var option:Option = new Option('隐藏暂停按钮', '开启后暂停按钮将不可见。', 'invisibleButtonPause', 'bool');
		addOption(option);
		#end
		#end

		var option:Option = new Option('对手音符', '关闭后隐藏对手的音符。', 'opponentStrums', 'bool');
		addOption(option);

		var option:Option = new Option('幽灵按键', "开启后，方向上没有音符时\n按键不会被判为Miss。", 'ghostTapping', 'bool');
		addOption(option);

		var option:Option = new Option('自动暂停', "开启后，画面失去焦点时游戏自动暂停。", 'autoPause', 'bool');
		addOption(option);
		option.onChange = onChangeAutoPause;

		var option:Option = new Option('禁用重开键', "开启后按重开键将无效果。", 'noReset', 'bool');
		addOption(option);

		var option:Option = new Option('打击音效音量', '击中音符时会发出“Tick!”声，此项调整音量。', 'hitsoundVolume', 'percent');
		option.scrollSpeed = 1.6; option.minValue = 0.0; option.maxValue = 1; option.changeValue = 0.1; option.decimals = 1;
		addOption(option);
		option.onChange = onChangeHitsoundVolume;

		var option:Option = new Option('评价偏移', '调整击出“Sick!”评价所需的提前/延迟量。\n数值越大，判定越宽松。', 'ratingOffset', 'int');
		option.displayFormat = '%vms'; option.scrollSpeed = 20; option.minValue = -30; option.maxValue = 30;
		addOption(option);

		var option:Option = new Option('Sick! 判定窗口', '调整击出“Sick!”评价的\n时间窗口(毫秒)。', 'sickWindow', 'int');
		option.displayFormat = '%vms'; option.scrollSpeed = 15; option.minValue = 15; option.maxValue = 45;
		addOption(option);

		var option:Option = new Option('Good 判定窗口', '调整击出“Good”评价的\n时间窗口(毫秒)。', 'goodWindow', 'int');
		option.displayFormat = '%vms'; option.scrollSpeed = 30; option.minValue = 15; option.maxValue = 90;
		addOption(option);

		var option:Option = new Option('Bad 判定窗口', '调整击出“Bad”评价的\n时间窗口(毫秒)。', 'badWindow', 'int');
		option.displayFormat = '%vms'; option.scrollSpeed = 60; option.minValue = 15; option.maxValue = 135;
		addOption(option);

		var option:Option = new Option('安全帧数', '调整音符可提前或延后判定的帧数范围。', 'safeFrames', 'float');
		option.scrollSpeed = 5; option.minValue = 2; option.maxValue = 10; option.changeValue = 0.1;
		addOption(option);

		var option:Option = new Option('长条按单音符计', "开启后，Miss时长条不可继续按压，\n并按单个音符计分。", 'guitarHeroSustains', 'bool');
		addOption(option);

		return arr;
	}

	function buildGraphics():Array<Option>
	{
		var arr:Array<Option> = [];
		function addOption(o:Option) arr.push(o);

		var option:Option = new Option('低画质', '开启后减少背景细节，\n缩短加载时间并提升性能。', 'lowQuality', 'bool');
		addOption(option);

		var option:Option = new Option('抗锯齿', '关闭后禁用抗锯齿，提升性能，\n但画面边缘会更锐利。', 'antialiasing', 'bool');
		addOption(option);
		option.onChange = onChangeAntiAliasing;

		var option:Option = new Option('着色器', "关闭后禁用着色器。\n用于部分视觉效果，弱机开启较耗性能。", 'shaders', 'bool');
		addOption(option);

		var option:Option = new Option('GPU 缓存', "开启后用GPU缓存纹理，降低内存占用。\n显卡不行的话别开。", 'cacheOnGPU', 'bool');
		addOption(option);

		#if !html5
		var option:Option = new Option('帧率上限', "顾名思义，不用多说了吧。", 'framerate', 'int');
		addOption(option);
		final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
		option.minValue = 60;
		// 上限不超过屏幕刷新率: 更新频率超过设备能力会导致慢动作/丢输入
		option.maxValue = Std.int(Math.max(60, refreshRate));
		option.defaultValue = Std.int(FlxMath.bound(refreshRate, option.minValue, option.maxValue));
		option.displayFormat = '%v FPS';
		option.onChange = onChangeFramerate;
		#end

		return arr;
	}

	// ==================== 回调(搬自设置页) ====================

	function onChangeHitsoundVolume()
		FlxG.sound.play(Paths.sound('hitsound'), ClientPrefs.data.hitsoundVolume);

	function onChangeAutoPause()
		FlxG.autoPause = ClientPrefs.data.autoPause;

	function onChangeFramerate()
	{
		FlxG.drawFramerate = ClientPrefs.data.framerate;
		FlxG.updateFramerate = ClientPrefs.data.framerate;
	}

	function onChangeAntiAliasing()
	{
		for (sprite in members)
		{
			var sprite:FlxSprite = cast sprite;
			if(sprite != null && (sprite is FlxSprite) && !(sprite is FlxText))
				sprite.antialiasing = ClientPrefs.data.antialiasing;
		}
	}

	function onChangePauseMusic()
	{
		if(ClientPrefs.data.pauseMusic == 'None')
			FlxG.sound.music.volume = 0;
		else
			FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)));
		changedMusic = true;
	}

	// ==================== 分类与重建 ====================

	function isSpecial(cat:String):Bool return specialCats.contains(cat);

	function switchCategory(idx:Int):Void
	{
		ClientPrefs.saveSettings();
		curCat = idx;
		var cat:String = allCats[curCat];

		if (isSpecial(cat))
		{
			openSpecial(cat);
			return;
		}

		rebuildOptions(cat);
	}

	function openSpecial(cat:String):Void
	{
		switch (cat)
		{
			case '音符颜色': openSubState(new options.NotesSubState());
			case '按键设置': openSubState(new options.ControlsSubState());
			case '延迟与连击校准': MusicBeatState.switchState(new options.NoteOffsetState());
		}
	}

	function rebuildOptions(cat:String):Void
	{
		optionsArray = optionsByCat.get(cat);
		curSelected = 0;
		scrollOffset = 0;

		grpOptions.clear();
		grpCards.clear();
		grpWidgets.clear(); // 上一分区的开关/滑条/值文字整组移除
		// 控件数组按选项下标对齐, 类型不符的格子留 null(修复控件串行错位)
		switches = [for (i in 0...optionsArray.length) null];
		sliders = [for (i in 0...optionsArray.length) null];
		valueTexts = [for (i in 0...optionsArray.length) null];
		optionCards = [];
		rightTitle.text = cat;

		for (i in 0...optionsArray.length)
		{
			var opt:Option = optionsArray[i];

			var optionText:OptionNameText = new OptionNameText(rightX + 66, rowsStartY, opt.name, 20);
			optionText.isMenuItem = true;
			optionText.targetY = i;
			optionText.distancePerItem.y = rowSpacing;
			grpOptions.add(optionText);

			var card:FlxSprite = new FlxSprite(rightX + 24, 0);
			card.pixels = MD3Rounded.createBitmap(FlxG.width - rightX - 36 - 48, 48, 14);
			card.color = MD3Theme.surfaceContainerHigh;
			grpCards.add(card);
			optionCards.push(card);

			var widgetRight:Float = rightX + (FlxG.width - rightX - 36) - 96;
			if(opt.type == 'bool')
			{
				var sw:MD3Switch = new MD3Switch(widgetRight - 64, 0, opt.getValue() == true, function(v:Bool) {
					opt.setValue(v);
					opt.change();
					updateTextFrom(opt);
					ClientPrefs.saveSettings();
				});
				switches[i] = sw;
				grpWidgets.add(sw);
			}
			else if(opt.type == 'int' || opt.type == 'float' || opt.type == 'percent')
			{
				var sl:MD3Slider = new MD3Slider(widgetRight - 430, 0, 280, opt.minValue, opt.maxValue, opt.changeValue, opt.decimals, opt.getValue());
				sl.onChange = function() {
					opt.setValue(sl.value);
					opt.change();
					updateTextFrom(opt);
					ClientPrefs.saveSettings();
				};
				sliders[i] = sl;
				grpWidgets.add(sl);
				var vTxt = new FlxText(widgetRight - 130, 0, 110, "", 18);
				vTxt.setFormat(Paths.font("vcr.ttf"), 18, MD3Theme.onSurfaceVariant, flixel.text.FlxTextAlign.RIGHT);
				valueTexts[i] = vTxt;
				grpWidgets.add(vTxt);
			}
			else
			{
				var vTxt = new FlxText(widgetRight - 220, 0, 210, "", 18);
				vTxt.setFormat(Paths.font("vcr.ttf"), 18, MD3Theme.onSurfaceVariant, flixel.text.FlxTextAlign.RIGHT);
				valueTexts[i] = vTxt;
				grpWidgets.add(vTxt);
			}
			updateTextFrom(opt);
		}
		changeSelection();
	}

	function updateTextFrom(option:Option):Void
	{
		if(option.type == 'keybind') return;
		var text:String = option.displayFormat;
		var val:Dynamic = option.getValue();
		if(option.type == 'percent') val *= 100;
		var def:Dynamic = option.defaultValue;
		option.text = text.replace('%v', val).replace('%d', def);
	}


	// ==================== 选择与确认 ====================

	function changeSelection(change:Int = 0):Void
	{
		if (optionsArray.length == 0) return;
		curSelected += change;
		if (curSelected < 0) curSelected = optionsArray.length - 1;
		else if (curSelected >= optionsArray.length) curSelected = 0;

		// 滚动窗口
		if (curSelected < scrollOffset) scrollOffset = curSelected;
		if (curSelected > scrollOffset + visibleRows - 1) scrollOffset = curSelected - visibleRows + 1;
		if (scrollOffset < 0) scrollOffset = 0;
		if (scrollOffset > optionsArray.length - visibleRows) scrollOffset = optionsArray.length - visibleRows;
		if (scrollOffset < 0) scrollOffset = 0;

		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);

		var curOpt = curOption;
		descText.text = (curOpt != null && curOpt.description != null) ? curOpt.description : '';
		descText.y = panelY + panelH - 106;
		descBox.setPosition(descText.x - 10, descText.y - 10);
		descBox.setGraphicSize(Std.int(descText.width + 20), Std.int(descText.height + 20));
		descBox.updateHitbox();

		for (i in 0...grpOptions.members.length)
		{
			var item = grpOptions.members[i];
			item.targetY = i - scrollOffset;
			item.alpha = (i == curSelected) ? 1 : 0.6;
		}
		for (i in 0...valueTexts.length)
			if (valueTexts[i] != null) valueTexts[i].alpha = (i == curSelected) ? 1 : 0.55;
	}

	function acceptOption():Void
	{
		var curOpt = curOption;
		if (curOpt == null || nextAccept > 0) return;

		if (curOpt.type == 'bool')
		{
			if (switches[curSelected] != null) switches[curSelected].toggle();
			nextAccept = 5;
		}
		else if (curOpt.type == 'string')
		{
			stepValue(1);
		}
	}

	function stepValue(dir:Int):Void
	{
		var curOpt = curOption;
		if (curOpt == null) return;
		switch (curOpt.type)
		{
			case 'string':
				var num:Int = curOpt.curOption;
				num += dir;
				if(num < 0) num = curOpt.options.length - 1;
				else if(num >= curOpt.options.length) num = 0;
				curOpt.curOption = num;
				curOpt.setValue(curOpt.options[num]);
			case 'int' | 'float' | 'percent':
				var add:Dynamic = dir * curOpt.changeValue;
				var holdValue:Dynamic = curOpt.getValue() + add;
				if(holdValue < curOpt.minValue) holdValue = curOpt.minValue;
				else if (holdValue > curOpt.maxValue) holdValue = curOpt.maxValue;
				switch(curOpt.type)
				{
					case 'int':
						holdValue = Math.round(holdValue);
						curOpt.setValue(holdValue);
					case 'float' | 'percent':
						holdValue = FlxMath.roundDecimal(holdValue, curOpt.decimals);
						curOpt.setValue(holdValue);
				}
		}
		updateTextFrom(curOpt);
		curOpt.change();
		FlxG.sound.play(Paths.sound('scrollMenu'));
		nextAccept = 2;
	}

	function resetOption():Void
	{
		var leOption:Option = curOption;
		if (leOption == null) return;
		if (leOption.type != 'keybind')
		{
			leOption.setValue(leOption.defaultValue);
			if(leOption.type == 'string') leOption.curOption = leOption.options.indexOf(leOption.getValue());
			updateTextFrom(leOption);
		}
		leOption.change();
		FlxG.sound.play(Paths.sound('cancelMenu'));
		nextAccept = 5;
	}

	// ==================== update ====================

	var nextAccept:Int = 5;
	var holdTime:Float = 0;

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// 选项行定位(滚动窗口内) + 卡片跟随 + 选中高亮 + 越界隐藏
		for (i in 0...grpOptions.members.length)
		{
			var row = grpOptions.members[i];
			if (row == null) continue;
			row.targetY = i - scrollOffset;
			var rowY:Float = rowsStartY + row.targetY * rowSpacing;
			row.y = FlxMath.lerp(rowY, row.y, Math.exp(-elapsed * 12));
			row.x = rightX + 66;
			// 卡片高48, 底边不得越过说明框顶部, 避免盖住最后一行
			row.visible = (rowY >= panelY + 52 && rowY + 48 <= panelY + panelH - 132);
			if (optionCards[i] != null)
			{
				optionCards[i].x = rightX + 24;
				optionCards[i].y = row.y - 9;
				optionCards[i].visible = row.visible;
				optionCards[i].color = (i == curSelected) ? MD3Theme.primaryContainer : MD3Theme.surfaceContainerHigh;
				optionCards[i].alpha = (i == curSelected) ? 1 : 0.65;
			}
		}
		// 自绘控件跟随行 + 值同步
		var widgetRight:Float = rightX + (FlxG.width - rightX - 36) - 96;
		for (i in 0...optionCards.length)
		{
			var row = grpOptions.members[i];
			if (row == null || optionsArray[i] == null) continue;
			var opt:Option = optionsArray[i];
			if (switches[i] != null)
			{
				switches[i].x = widgetRight - 64;
				switches[i].y = row.y + 8;
				switches[i].visible = row.visible;
				switches[i].on = (opt.getValue() == true);
			}
			if (sliders[i] != null)
			{
				sliders[i].x = widgetRight - 430;
				sliders[i].y = row.y + 18;
				sliders[i].visible = row.visible;
				if (!sliders[i].dragging) sliders[i].setValue(opt.getValue());
			}
			if (valueTexts[i] != null)
			{
				valueTexts[i].x = widgetRight - 200;
				valueTexts[i].y = row.y + 14;
				valueTexts[i].visible = row.visible;
				// Option.text 是转发给 child(原版AttachedText)的代理, 本界面没有 child 会返回 null
				// 所以直接按 displayFormat 现算: %v=当前值 %d=默认值, percent 自动 x100
				var disp:String = opt.displayFormat;
				var val:Dynamic = opt.getValue();
				if (opt.type == 'percent') val = FlxMath.roundDecimal(val * 100, opt.decimals);
				valueTexts[i].text = disp.replace('%v', Std.string(val)).replace('%d', Std.string(opt.defaultValue));
				valueTexts[i].alpha = (i == curSelected) ? 1 : 0.6;
			}
		}

		// 左侧分类文字位置与高亮
		for (i in 0...catTexts.members.length)
		{
			var ct = catTexts.members[i];
			ct.y = panelY + 74 + i * 56;
			ct.color = (i == curCat) ? MD3Theme.primary : MD3Theme.onSurfaceVariant;
			ct.alpha = (i == curCat) ? 1 : 0.8;
		}

		// ===== 触控 =====
		#if mobile
		TouchMenuUtil.update(optionCards, curSelected,
			function(d:Int) changeSelection(d),
			function(i:Int) { if (nextAccept <= 0) changeSelection(i - curSelected); },
			function() {
				if (nextAccept > 0) return;
				var opt = optionsArray[curSelected];
				if (opt != null && (opt.type == 'int' || opt.type == 'float' || opt.type == 'percent'))
					return; // 滑动条直接拖
				touchAcceptFlag = true;
			}
		);
		handleCategoryTouch();
		handleBackTouch();
		handleResetTouch();
		#end

		// ===== 键盘/手柄 =====
		if (nextAccept <= 0)
		{
			if (controls.UI_UP_P) { changeSelection(-1); nextAccept = 3; }
			if (controls.UI_DOWN_P) { changeSelection(1); nextAccept = 3; }

			if (curOption != null)
			{
				if (curOption.type == 'bool')
				{
					if (controls.ACCEPT || touchAcceptFlag) { touchAcceptFlag = false; acceptOption(); }
				}
				else if (curOption.type == 'string' || curOption.type == 'int' || curOption.type == 'float' || curOption.type == 'percent')
				{
					if (controls.UI_LEFT_P) { stepValue(-1); nextAccept = 2; }
					else if (controls.UI_RIGHT_P || touchValueFlag != 0) { touchValueFlag = 0; stepValue(1); nextAccept = 2; }
					else if ((controls.UI_LEFT || controls.UI_RIGHT) && (curOption.type == 'int' || curOption.type == 'float' || curOption.type == 'percent'))
					{
						holdTime += elapsed;
						if (holdTime > 0.35) { holdTime = 0; stepValue(controls.UI_LEFT ? -1 : 1); nextAccept = 2; }
					}
					else holdTime = 0;
					if (controls.ACCEPT || touchAcceptFlag) { touchAcceptFlag = false; stepValue(1); }
				}
			}

			if (controls.RESET) resetOption();

			if (controls.ACCEPT || touchAcceptFlag)
			{
				touchAcceptFlag = false;
				var cat:String = allCats[curCat];
				if (isSpecial(cat)) openSpecial(cat);
				else acceptOption();
			}
		}
		if (nextAccept > 0) nextAccept -= 1;

		if (controls.BACK) goBack();
	}

	// ==================== 返回按钮 ====================

	function goBack():Void
	{
		ClientPrefs.saveSettings();
		if (changedMusic && !onPlayState) FlxG.sound.playMusic(Paths.music('freakyMenu'), 1, true);
		FlxG.sound.play(Paths.sound('cancelMenu'));
		MusicBeatState.switchState(new MainMenuState());
	}

	#if mobile
	function overReset(tx:Float, ty:Float):Bool
	{
		return tx >= resetBtn.x - 8 && tx <= resetBtn.x + resetBtn.width + 8
			&& ty >= resetBtn.y - 8 && ty <= resetBtn.y + resetBtn.height + 8;
	}

	function handleResetTouch():Void
	{
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed && overReset(touch.x, touch.y))
			{
				resetPressId = touch.touchPointID;
				resetPressed = true;
			}
			else if (resetPressId != -1 && touch.touchPointID == resetPressId)
			{
				if (touch.pressed) resetPressed = overReset(touch.x, touch.y);
				if (touch.justReleased)
				{
					if (overReset(touch.x, touch.y)) resetOption();
					resetPressId = -1;
					resetPressed = false;
				}
			}
		}
		if (resetPressId != -1)
		{
			var still:Bool = false;
			for (t in FlxG.touches.list)
				if (t.touchPointID == resetPressId && (t.pressed || t.justPressed)) { still = true; break; }
			if (!still) { resetPressId = -1; resetPressed = false; }
		}
		resetBtn.alpha = resetPressed ? 0.7 : 1;
		resetIcon.alpha = resetPressed ? 0.7 : 1;
	}
	#end

	#if mobile
	function overBack(tx:Float, ty:Float):Bool
	{
		return tx >= backBtn.x - 8 && tx <= backBtn.x + backBtn.width + 8
			&& ty >= backBtn.y - 8 && ty <= backBtn.y + backBtn.height + 8;
	}

	function handleBackTouch():Void
	{
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed && overBack(touch.x, touch.y))
			{
				backPressId = touch.touchPointID;
				backPressed = true;
			}
			else if (backPressId != -1 && touch.touchPointID == backPressId)
			{
				if (touch.pressed) backPressed = overBack(touch.x, touch.y);
				if (touch.justReleased)
				{
					if (overBack(touch.x, touch.y)) goBack();
					backPressId = -1;
					backPressed = false;
				}
			}
		}
		if (backPressId != -1)
		{
			var still:Bool = false;
			for (t in FlxG.touches.list)
				if (t.touchPointID == backPressId && (t.pressed || t.justPressed)) { still = true; break; }
			if (!still) { backPressId = -1; backPressed = false; }
		}
		backBtn.alpha = backPressed ? 0.7 : 1;
		backIcon.alpha = backPressed ? 0.7 : 1;
	}
	#end

	#if mobile
	function handleCategoryTouch():Void
	{
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed)
			{
				touchTracking = true;
				touchStartY = touch.y;
			}
			else if (touch.justReleased && touchTracking)
			{
				touchTracking = false;
				if (Math.abs(touch.y - touchStartY) < 24)
				{
					for (i in 0...catTexts.members.length)
					{
						var ct = catTexts.members[i];
						if (ct == null) continue;
						var cy:Float = ct.y + ct.height / 2;
						if (touch.y >= cy - 26 && touch.y <= cy + 26 && touch.x >= leftX && touch.x <= leftX + leftW)
						{
							if (i != curCat) { FlxG.sound.play(Paths.sound('scrollMenu'), 0.6); switchCategory(i); }
							else if (isSpecial(allCats[i])) openSpecial(allCats[i]);
							break;
						}
					}
				}
			}
		}
	}
	#end

	override function destroy():Void
	{
		ClientPrefs.saveSettings();
		if (changedMusic && !onPlayState) FlxG.sound.playMusic(Paths.music('freakyMenu'), 1, true);
		super.destroy();
	}
}
