package states;

import flixel.addons.transition.FlxTransitionableState;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxTimer;
import states.editors.MasterEditorMenu;
import options.OptionsState;
import mobile.backend.utils.TouchMenuUtil;
import ui.md3.MD3Rounded;
import ui.md3.MD3Theme;

/**
 * 主菜单 (MD3):
 *   左侧标题区(自绘猫耳随节拍弹跳 + 版本信息 + 支持作者小字)
 *   右侧 6 张入口卡片(自绘图标 + 中文名), 触控/虚拟按键/键盘均可操作
 * 跳转逻辑与原版完全一致。
 */
class MainMenuState extends MusicBeatState
{
	public static var psychEngineVersion:String = '0.7.3'; // This is also used for Discord RPC
	public static var curSelected:Int = 0;

	var optionShit:Array<String> = [
		'story_mode',
		'freeplay',
		#if MODS_ALLOWED 'mods', #end
		#if ACHIEVEMENTS_ALLOWED 'awards', #end
		'credits',
		'options'
	];

	var optionNames:Map<String, String> = [
		'story_mode' => '故事模式',
		'freeplay' => '自由游戏',
		'mods' => '模组管理',
		'awards' => '成就',
		'credits' => '制作组',
		'options' => '设置'
	];

	// 每行成员的平行数组(下标严格对应 optionShit)
	var cards:Array<FlxSprite> = [];
	var iconBases:Array<FlxSprite> = [];
	var icons:Array<FlxSprite> = [];
	var nameTexts:Array<FlxText> = [];
	var bars:Array<FlxSprite> = [];

	var ears:FlxSprite;
	var donateText:FlxText;

	var selectedSomethin:Bool = false;

	override function create()
	{
		#if MODS_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menus", null);
		#end

		transIn = FlxTransitionableState.defaultTransIn;
		transOut = FlxTransitionableState.defaultTransOut;

		persistentUpdate = persistentDraw = true;

		// ===== 背景 + MD3 暗色罩层 =====
		var bg:FlxSprite = new FlxSprite(-80).loadGraphic(Paths.image('menuBG'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.setGraphicSize(Std.int(bg.width * 1.175));
		bg.updateHitbox();
		bg.screenCenter();
		bg.scrollFactor.set();
		add(bg);

		var shade:FlxSprite = new FlxSprite().makeGraphic(1, 1, MD3Theme.surface);
		shade.scale.set(FlxG.width + 10, FlxG.height + 10);
		shade.updateHitbox();
		shade.screenCenter();
		shade.scrollFactor.set();
		shade.alpha = 0.65;
		add(shade);

		// ===== 左侧标题区 =====
		ears = new FlxSprite(64, 70);
		ears.pixels = MD3Rounded.createCatEars(150, 62);
		ears.color = MD3Theme.primary;
		add(ears);

		var titleText:FlxText = new FlxText(48, 140, 0, 'NekoEngine', 52);
		titleText.setFormat(Paths.font('vcr.ttf'), 52, MD3Theme.onSurface);
		add(titleText);

		var subText:FlxText = new FlxText(48, 208, 0, 'NekoEngine v0.01  |  Psych Engine ' + psychEngineVersion, 16);
		subText.setFormat(Paths.font('vcr.ttf'), 16, MD3Theme.onSurfaceVariant);
		add(subText);

		var fnfVer:FlxText = new FlxText(48, FlxG.height - 30, 0, "Friday Night Funkin' v0.2.8", 14);
		fnfVer.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onSurfaceVariant);
		fnfVer.scrollFactor.set();
		add(fnfVer);

		// 捐赠(决策点3A): 左下角小字按钮, 不占主列表
		donateText = new FlxText(48, FlxG.height - 58, 0, '支持作者', 16);
		donateText.setFormat(Paths.font('vcr.ttf'), 16, MD3Theme.primary);
		donateText.scrollFactor.set();
		add(donateText);

		// ===== 右侧入口卡片列表 =====
		var listX:Float = 460;
		var cardH:Float = 64;
		var gap:Float = 14;
		var cardW:Float = FlxG.width - listX - 36;
		var listH:Float = optionShit.length * cardH + (optionShit.length - 1) * gap;
		var listY:Float = (FlxG.height - listH) / 2;

		for (i in 0...optionShit.length)
		{
			var cy:Float = listY + i * (cardH + gap);

			var card:FlxSprite = new FlxSprite(listX, cy);
			card.pixels = MD3Rounded.createBitmap(cardW, cardH, 16);
			card.color = MD3Theme.surfaceContainer;
			card.alpha = 0.85;
			add(card);
			cards.push(card);

			var iconBase:FlxSprite = new FlxSprite(listX + 10, cy + 10);
			iconBase.pixels = MD3Rounded.createBitmap(44, 44, 12);
			iconBase.color = MD3Theme.primaryContainer;
			add(iconBase);
			iconBases.push(iconBase);

			var icon:FlxSprite = new FlxSprite(listX + 18, cy + 18);
			icon.pixels = MD3Rounded.createMenuIcon(optionShit[i], 28, 3);
			icon.color = 0xFFFFFFFF;
			add(icon);
			icons.push(icon);

			var nameT:FlxText = new FlxText(listX + 70, cy + (cardH - 26) / 2, 0, optionNames.get(optionShit[i], optionShit[i]), 22);
			nameT.setFormat(Paths.font('vcr.ttf'), 22, MD3Theme.onSurface);
			add(nameT);
			nameTexts.push(nameT);

			var bar:FlxSprite = new FlxSprite(listX - 2, cy + 12);
			bar.pixels = MD3Rounded.createBitmap(4, 40, 2);
			bar.color = MD3Theme.primary;
			bar.visible = false;
			add(bar);
			bars.push(bar);
		}

		// 入场动画: 右滑入 + 淡入(stagger), 目标透明度与选中态一致
		for (i in 0...optionShit.length)
		{
			var sel:Bool = (i == curSelected);
			animateIn(cards[i], sel ? 1 : 0.85, i * 0.04);
			animateIn(iconBases[i], 1, i * 0.04);
			animateIn(icons[i], 1, i * 0.04);
			animateIn(nameTexts[i], sel ? 1 : 0.7, i * 0.04);
		}
		refreshSelection();

		#if ACHIEVEMENTS_ALLOWED
		// Unlocks "Freaky on a Friday Night" achievement if it's a Friday and between 18:00 PM and 23:59 PM
		var leDate = Date.now();
		if (leDate.getDay() == 5 && leDate.getHours() >= 18)
			Achievements.unlock('friday_night_play');

		#if MODS_ALLOWED
		Achievements.reloadList();
		#end
		#end

		#if mobile
		addVirtualPad('UP_DOWN', 'A_B_C');
		#end

		super.create();
	}

	// 入场: 记录目标位置后右偏50px+全透明, 再滑回
	function animateIn(spr:FlxSprite, targetAlpha:Float, delay:Float):Void
	{
		var tx:Float = spr.x;
		spr.x = tx + 50;
		spr.alpha = 0;
		FlxTween.tween(spr, {x: tx, alpha: targetAlpha}, 0.35, {startDelay: delay, ease: FlxEase.quadOut});
	}

	function refreshSelection():Void
	{
		for (i in 0...optionShit.length)
		{
			var sel:Bool = (i == curSelected);
			cards[i].color = sel ? MD3Theme.primaryContainer : MD3Theme.surfaceContainer;
			cards[i].alpha = sel ? 1 : 0.85;
			bars[i].visible = sel;
			iconBases[i].color = sel ? MD3Theme.primary : MD3Theme.primaryContainer;
			nameTexts[i].color = sel ? MD3Theme.onSurface : MD3Theme.onSurfaceVariant;
			nameTexts[i].alpha = sel ? 1 : 0.7;
		}
	}

	function changeItem(delta:Int = 0):Void
	{
		FlxG.sound.play(Paths.sound('scrollMenu'));
		curSelected += delta;
		if (curSelected >= optionShit.length) curSelected = 0;
		if (curSelected < 0) curSelected = optionShit.length - 1;
		refreshSelection();
	}

	function acceptItem():Void
	{
		if (selectedSomethin) return;	// 防止触控+按键同帧双重触发
		FlxG.sound.play(Paths.sound('confirmMenu'));
		selectedSomethin = true;

		// 选中卡片颜色脉冲, 其他行淡出
		cards[curSelected].color = MD3Theme.primary;
		for (i in 0...optionShit.length)
		{
			if (i == curSelected) continue;
			fadeRow(i, 0.12);
		}

		new FlxTimer().start(0.35, function(t:FlxTimer)
		{
			switch (optionShit[curSelected])
			{
				case 'story_mode':
					MusicBeatState.switchState(new StoryMenuState());
				case 'freeplay':
					MusicBeatState.switchState(new FreeplayState());

				#if MODS_ALLOWED
				case 'mods':
					MusicBeatState.switchState(new ModsMenuState());
				#end

				#if ACHIEVEMENTS_ALLOWED
				case 'awards':
					MusicBeatState.switchState(new AchievementsMenuState());
				#end

				case 'credits':
					MusicBeatState.switchState(new CreditsState());
				case 'options':
					MusicBeatState.switchState(new OptionsState());
					OptionsState.onPlayState = false;
					if (PlayState.SONG != null)
					{
						PlayState.SONG.arrowSkin = null;
						PlayState.SONG.splashSkin = null;
						PlayState.stageUI = 'normal';
					}
			}
		});
	}

	function fadeRow(i:Int, targetAlpha:Float):Void
	{
		// 先杀掉入场动画的补间, 避免两个补间拉扯同一属性
		FlxTween.killTweensOf(cards[i]);
		FlxTween.killTweensOf(iconBases[i]);
		FlxTween.killTweensOf(icons[i]);
		FlxTween.killTweensOf(nameTexts[i]);
		FlxTween.tween(cards[i], {alpha: targetAlpha}, 0.25, {ease: FlxEase.quadOut});
		FlxTween.tween(iconBases[i], {alpha: targetAlpha}, 0.25);
		FlxTween.tween(icons[i], {alpha: targetAlpha}, 0.25);
		FlxTween.tween(nameTexts[i], {alpha: targetAlpha}, 0.25);
		bars[i].visible = false;
	}

	override function beatHit():Void
	{
		super.beatHit();
		if (ears != null && !selectedSomethin) ears.scale.set(1.12, 1.12);
	}

	override function update(elapsed:Float)
	{
		if (FlxG.sound.music.volume < 0.8)
		{
			FlxG.sound.music.volume += 0.5 * elapsed;
			if (FreeplayState.vocals != null)
				FreeplayState.vocals.volume += 0.5 * elapsed;
		}

		// 猫耳弹跳回落
		if (ears != null && (ears.scale.x != 1 || ears.scale.y != 1))
			ears.scale.set(Math.max(1, ears.scale.x - elapsed * 1.2), Math.max(1, ears.scale.y - elapsed * 1.2));

		if (!selectedSomethin)
		{
			// 屏幕触控: 点卡片=选中, 再点已选中=确认, 上下滑动=换选
			TouchMenuUtil.update(cards, curSelected, changeItem, function(i:Int) changeItem(i - curSelected), acceptItem);

			#if mobile
			handleDonateTouch();
			#end

			if (controls.UI_UP_P)
				changeItem(-1);

			if (controls.UI_DOWN_P)
				changeItem(1);

			if (controls.BACK)
			{
				selectedSomethin = true;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new TitleState());
			}

			if (controls.ACCEPT)
				acceptItem();

			if (controls.justPressed('debug_1') #if mobile || virtualPad.getButton('buttonC').justPressed #end)
			{
				selectedSomethin = true;
				MusicBeatState.switchState(new MasterEditorMenu());
			}
		}

		super.update(elapsed);
	}

	#if mobile
	function handleDonateTouch():Void
	{
		if (donateText == null) return;
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed
				&& touch.x >= donateText.x - 12 && touch.x <= donateText.x + donateText.width + 12
				&& touch.y >= donateText.y - 12 && touch.y <= donateText.y + donateText.height + 12)
			{
				CoolUtil.browserLoad('https://ninja-muffin24.itch.io/funkin');
			}
		}
	}
	#end
}
