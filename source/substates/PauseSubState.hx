package substates;

import backend.Highscore;
import backend.Song;

import flixel.addons.transition.FlxTransitionableState;

import flixel.FlxBasic;
import flixel.input.touch.FlxTouch;
import flixel.util.FlxStringUtil;

import states.StoryMenuState;
import states.FreeplayState;
import options.OptionsState;
import ui.md3.MD3Rounded;
import ui.md3.MD3Theme;
import ui.md3.MD3Switch;

/**
 * 暂停 (MD3): 三页结构(主列表/难度/打谱工具), 全触控+键盘兼容, 动作语义与原版一致。
 * 触控: 未选中行=仅选中; 已选中行=按下即激活(0.25s防误触); 开关行切换MD3Switch;
 *       跳转时间行◀▶±1s / 横向拖动扫秒 / 抬起位移<20px=应用。
 * 键盘: 上下换选 / ACCEPT激活 / BACK返回 / Skip Time左右长按连调。
 */
class PauseSubState extends MusicBeatSubstate
{
	// ===== 三页列表(内部键保留英文原串, 显示走 labelOf) =====
	var menuItems:Array<String> = [];
	var menuItemsOG:Array<String> = [];
	var difficultyChoices:Array<String> = [];
	var chartChoices:Array<String> = ['Leave Charting Mode', 'Skip Time', 'Toggle Practice Mode', 'Toggle Botplay', 'BACK'];
	var curPage:Int = 0;	// 0=主列表 1=难度 2=打谱
	var curSelected:Int = 0;

	var pauseMusic:FlxSound;
	var curTime:Float = Math.max(0, Conductor.songPosition);
	var skipRowIdx:Int = -1;

	// ===== MD3 元素 =====
	var bg:FlxSprite;
	var backBtn:FlxSprite;
	var backIcon:FlxSprite;
	var titleText:FlxText;
	var subText:FlxText;
	var badgeText:FlxText;

	// 行成员平行数组(下标严格对应 menuItems —— 玩法调整页教训)
	var rowCards:Array<FlxSprite> = [];
	var rowLabels:Array<FlxText> = [];
	var rowValues:Array<FlxText> = [];
	var rowSwitches:Array<MD3Switch> = [];
	var rowDecL:Array<FlxSprite> = [];
	var rowDecR:Array<FlxSprite> = [];
	var allRowMembers:Array<FlxBasic> = [];

	var missingTextBG:FlxSprite;
	var missingText:FlxText;

	public static var songName:String = null;

	override function create()
	{
		buildMainList();

		for (i in 0...Difficulty.list.length)
			difficultyChoices.push(Difficulty.getString(i));
		difficultyChoices.push('BACK');

		pauseMusic = new FlxSound();
		try
		{
			var pauseSong:String = getPauseSong();
			if(pauseSong != null) pauseMusic.loadEmbedded(Paths.music(pauseSong), true, true);
		}
		catch(e:Dynamic) {}
		pauseMusic.volume = 0;
		pauseMusic.play(false, FlxG.random.int(0, Std.int(pauseMusic.length / 2)));

		FlxG.sound.list.add(pauseMusic);

		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, MD3Theme.surface);
		bg.alpha = 0;
		add(bg);
		FlxTween.tween(bg, {alpha: 0.88}, 0.25, {ease: FlxEase.quartOut});	// 暂停要快

		backBtn = new FlxSprite(36, 18);
		backBtn.pixels = MD3Rounded.createBitmap(44, 44, 22);
		backBtn.color = MD3Theme.surfaceContainerHigh;
		add(backBtn);
		backIcon = new FlxSprite(backBtn.x + 8, backBtn.y + 8);
		backIcon.pixels = MD3Rounded.createBackArrow(28, 3);
		backIcon.color = 0xFFFFFFFF;
		add(backIcon);

		titleText = new FlxText(0, 20, FlxG.width, '已暂停', 30);
		titleText.setFormat(Paths.font('vcr.ttf'), 30, MD3Theme.onSurface, CENTER);
		add(titleText);

		subText = new FlxText(0, 58, FlxG.width, '', 16);
		subText.setFormat(Paths.font('vcr.ttf'), 16, MD3Theme.onSurfaceVariant, CENTER);
		subText.text = PlayState.SONG.song + ' · ' + Difficulty.getString() + ' · 死亡 ' + PlayState.deathCounter + ' 次';
		add(subText);

		badgeText = new FlxText(0, 26, FlxG.width - 36, '', 16);
		badgeText.setFormat(Paths.font('vcr.ttf'), 16, MD3Theme.primary, RIGHT);
		badgeText.visible = false;
		add(badgeText);
		updateBadge();

		// 谱面加载失败浮层(原版语义, 加在行之上)
		missingTextBG = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		missingTextBG.scale.set(FlxG.width, FlxG.height);
		missingTextBG.updateHitbox();
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		add(missingTextBG);

		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		add(missingText);

		goMainList();
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];

		super.create();
	}

	function getPauseSong()
	{
		var formattedSongName:String = (songName != null ? Paths.formatToSongPath(songName) : '');
		var formattedPauseMusic:String = Paths.formatToSongPath(ClientPrefs.data.pauseMusic);
		if(formattedSongName == 'none' || (formattedSongName != 'none' && formattedPauseMusic == 'none')) return null;

		return (formattedSongName != '') ? formattedSongName : formattedPauseMusic;
	}

	// ===== 列表构建 =====

	function buildMainList():Void
	{
		var list:Array<String> = ['Resume', 'Restart Song', 'Chart Editor'];
		if(Difficulty.list.length >= 2) list.push('Change Difficulty');
		if(PlayState.chartingMode) list.push('Charting Tools');
		list.push('Options');
		list.push('Exit to menu');
		menuItemsOG = list;
	}

	function labelOf(key:String):String
	{
		return switch (key)
		{
			case 'Resume': '继续';
			case 'Restart Song': '重开本曲';
			case 'Chart Editor': '图表编辑器';
			case 'Change Difficulty': '调整难度';
			case 'Charting Tools': '打谱工具';
			case 'Options': '设置';
			case 'Exit to menu': '退出到菜单';
			case 'Leave Charting Mode': '离开打谱模式';
			case 'Skip Time': '跳转时间';
			case 'Toggle Practice Mode': '练习模式';
			case 'Toggle Botplay': '猫娘替你打喵';
			case 'BACK': '返回';
			default: key;
		}
	}

	function updateBadge():Void
	{
		if (PlayState.chartingMode) badgeText.text = '打谱模式';
		else if (PlayState.instance != null && PlayState.instance.practiceMode) badgeText.text = '练习模式';
		else { badgeText.text = ''; badgeText.visible = false; return; }
		badgeText.visible = true;
	}

	function goMainList():Void { curPage = 0; menuItems = menuItemsOG; regenMenu(); }
	function goDiffList():Void
	{
		curPage = 1; menuItems = difficultyChoices; regenMenu();
		// 预选当前难度(而非第一行), 避免误触即刻换难度重开
		if (PlayState.storyDifficulty >= 0 && PlayState.storyDifficulty < menuItems.length - 1)
		{
			curSelected = PlayState.storyDifficulty;
			recolorRows();
		}
	}
	function goChartList():Void { curPage = 2; menuItems = chartChoices; regenMenu(); }

	function onBack():Void
	{
		if (curPage != 0) { FlxG.sound.play(Paths.sound('cancelMenu')); goMainList(); return; }
		close();
	}

	var holdTime:Float = 0;
	var cantUnpause:Float = 0.25;
	override function update(elapsed:Float)
	{
		cantUnpause -= elapsed;
		if (pauseMusic.volume < 0.5)
			pauseMusic.volume += 0.01 * elapsed;

		super.update(elapsed);

		#if android
		if (FlxG.android.justReleased.BACK) { onBack(); return; }
		#end
		if (controls.BACK) { onBack(); return; }

		#if mobile
		handleTouch(elapsed);
		#end

		if (controls.UI_UP_P)
			changeSelection(-1);
		if (controls.UI_DOWN_P)
			changeSelection(1);

		if (menuItems[curSelected] == 'Skip Time')
		{
			if (controls.UI_LEFT_P)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				curTime -= 1000;
				holdTime = 0;
			}
			if (controls.UI_RIGHT_P)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				curTime += 1000;
				holdTime = 0;
			}

			if(controls.UI_LEFT || controls.UI_RIGHT)
			{
				holdTime += elapsed;
				if(holdTime > 0.5)
				{
					curTime += 45000 * elapsed * (controls.UI_LEFT ? -1 : 1);
				}

				wrapSkipTime();
				updateSkipTimeText();
			}
		}

		if (controls.ACCEPT && (cantUnpause <= 0 || !controls.controllerMode))
			activateCurrent();
	}

	// ===== 动作(键盘ACCEPT与触控共用; 语义=原版) =====

	function activateCurrent():Void
	{
		var daSelected:String = menuItems[curSelected];

		if (curPage == 1)	// 难度子页
		{
			if (daSelected == 'BACK') { goMainList(); return; }
			try
			{
				var name:String = PlayState.SONG.song;
				var poop = Highscore.formatSong(name, curSelected);
				PlayState.SONG = Song.loadFromJson(poop, name);
				PlayState.storyDifficulty = curSelected;
				MusicBeatState.resetState();
				FlxG.sound.music.volume = 0;
				PlayState.changedDifficulty = true;
				PlayState.chartingMode = false;
			}
			catch(e:Dynamic)
			{
				trace('ERROR! $e');

				var errorStr:String = e.toString();
				if(errorStr.startsWith('[file_contents,assets/data/')) errorStr = 'Missing file: ' + errorStr.substring(27, errorStr.length-1); //Missing chart
				missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
				missingText.screenCenter(Y);
				missingText.visible = true;
				missingTextBG.visible = true;
				FlxG.sound.play(Paths.sound('cancelMenu'));
			}
			return;
		}

		switch (daSelected)
		{
			case "Resume":
				close();
			case 'Change Difficulty':
				goDiffList();
			case 'Charting Tools':
				goChartList();
			case 'Toggle Practice Mode':
				PlayState.instance.practiceMode = !PlayState.instance.practiceMode;
				PlayState.changedDifficulty = true;
				syncSwitchVisuals();
				updateBadge();
			case "Restart Song":
				restartSong();
			case "Chart Editor":
				PlayState.instance.openChartEditor();
			case "Leave Charting Mode":
				restartSong();
				PlayState.chartingMode = false;
			case 'Skip Time':
				applySkipTime();
			case 'End Song':
				close();
				PlayState.instance.notes.clear();
				PlayState.instance.unspawnNotes = [];
				PlayState.instance.finishSong(true);
			case 'Toggle Botplay':
				PlayState.instance.cpuControlled = !PlayState.instance.cpuControlled;
				PlayState.changedDifficulty = true;
				PlayState.instance.botplayTxt.visible = PlayState.instance.cpuControlled;
				PlayState.instance.botplayTxt.alpha = 1;
				PlayState.instance.botplaySine = 0;
				syncSwitchVisuals();
				updateBadge();
			case 'Options':
				PlayState.instance.paused = true; // For lua
				PlayState.instance.vocals.volume = 0;
				MusicBeatState.switchState(new OptionsState());
				if(ClientPrefs.data.pauseMusic != 'None')
				{
					FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)), pauseMusic.volume);
					FlxTween.tween(FlxG.sound.music, {volume: 1}, 0.8);
					FlxG.sound.music.time = pauseMusic.time;
				}
				OptionsState.onPlayState = true;
			case "Exit to menu":
				#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
				PlayState.deathCounter = 0;
				PlayState.seenCutscene = false;

				Mods.loadTopMod();
				if(PlayState.isStoryMode)
					MusicBeatState.switchState(new StoryMenuState());
				else
					MusicBeatState.switchState(new FreeplayState());

				FlxG.sound.playMusic(Paths.music('freakyMenu'));
				PlayState.changedDifficulty = false;
				PlayState.chartingMode = false;
				FlxG.camera.followLerp = 0;
		}
	}

	function applySkipTime():Void
	{
		if(curTime < Conductor.songPosition)
		{
			PlayState.startOnTime = curTime;
			restartSong(true);
		}
		else
		{
			if (curTime != Conductor.songPosition)
			{
				PlayState.instance.clearNotesBefore(curTime);
				PlayState.instance.setSongTime(curTime);
			}
			close();
		}
	}

	function wrapSkipTime():Void
	{
		if(FlxG.sound.music.length > 0)
		{
			if(curTime >= FlxG.sound.music.length) curTime -= FlxG.sound.music.length;
			else if(curTime < 0) curTime += FlxG.sound.music.length;
		}
		else if(curTime < 0) curTime = 0;
	}

	public static function restartSong(noTrans:Bool = false)
	{
		PlayState.instance.paused = true; // For lua
		FlxG.sound.music.volume = 0;
		PlayState.instance.vocals.volume = 0;

		if(noTrans)
		{
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
		}
		MusicBeatState.resetState();
	}

	override function destroy()
	{
		pauseMusic.destroy();

		super.destroy();
	}

	// ===== 视觉 =====

	function changeSelection(change:Int = 0):Void
	{
		curSelected += change;
		if (curSelected < 0)
			curSelected = menuItems.length - 1;
		if (curSelected >= menuItems.length)
			curSelected = 0;
		if (change != 0)
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		recolorRows();
		if (menuItems[curSelected] == 'Skip Time')
		{
			curTime = Math.max(0, Conductor.songPosition);
			updateSkipTimeText();
		}
		missingText.visible = false;
		missingTextBG.visible = false;
	}

	function selectTo(i:Int):Void
	{
		if (i < 0 || i >= menuItems.length) return;
		var changed:Bool = (curSelected != i);
		curSelected = i;
		recolorRows();
		if (changed)
		{
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
			if (menuItems[curSelected] == 'Skip Time')
			{
				curTime = Math.max(0, Conductor.songPosition);
				updateSkipTimeText();
			}
		}
		missingText.visible = false;
		missingTextBG.visible = false;
	}

	function recolorRows():Void
	{
		for (j in 0...rowCards.length)
			rowCards[j].color = (j == curSelected) ? MD3Theme.primaryContainer : MD3Theme.surfaceContainer;
	}

	function regenMenu():Void
	{
		for (obj in allRowMembers)
		{
			remove(obj, true);
			obj.destroy();
		}
		allRowMembers.resize(0);
		rowCards.resize(0);
		rowLabels.resize(0);
		rowValues.resize(0);
		rowSwitches.resize(0);
		rowDecL.resize(0);
		rowDecR.resize(0);
		skipRowIdx = -1;

		for (i in 0...menuItems.length)
		{
			var key:String = menuItems[i];
			var cy:Float = 96 + i * 62;

			var card:FlxSprite = new FlxSprite(60, cy);
			card.pixels = MD3Rounded.createBitmap(1160, 52, 12);
			card.color = MD3Theme.surfaceContainer;
			add(card);
			allRowMembers.push(card);
			rowCards.push(card);

			// 难度子页: 原始难度名 + 返回; 其余页: labelOf 中文
			var labelText:String = (curPage == 1 && key != 'BACK') ? key : labelOf(key);
			var label:FlxText = new FlxText(84, cy + 14, 0, labelText, 20);
			label.setFormat(Paths.font('vcr.ttf'), 20, MD3Theme.onSurface);
			add(label);
			allRowMembers.push(label);
			rowLabels.push(label);

			if (key == 'Toggle Practice Mode' || key == 'Toggle Botplay')
			{
				var sw:MD3Switch = new MD3Switch(1120, cy + 10,
					(key == 'Toggle Practice Mode') ? PlayState.instance.practiceMode : PlayState.instance.cpuControlled, null);
				add(sw);
				allRowMembers.push(sw);
				rowSwitches.push(sw);
				rowValues.push(null);
				rowDecL.push(null);
				rowDecR.push(null);
			}
			else if (key == 'Skip Time')
			{
				skipRowIdx = i;
				rowSwitches.push(null);
				var valT:FlxText = new FlxText(830, cy + 14, 230, '', 18);
				valT.setFormat(Paths.font('vcr.ttf'), 18, MD3Theme.onSurfaceVariant, RIGHT);
				add(valT);
				allRowMembers.push(valT);
				rowValues.push(valT);

				var decL:FlxSprite = new FlxSprite(1080, cy + 10);
				decL.pixels = MD3Rounded.createBitmap(32, 32, 8);
				decL.color = MD3Theme.primaryContainer;
				add(decL);
				allRowMembers.push(decL);
				rowDecL.push(decL);
				var decLText:FlxText = new FlxText(0, 0, 0, '<', 14);
				decLText.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onPrimaryContainer, CENTER);
				decLText.setPosition(decL.x + (32 - decLText.width) / 2, decL.y + 8);
				add(decLText);
				allRowMembers.push(decLText);

				var decR:FlxSprite = new FlxSprite(1160, cy + 10);
				decR.pixels = MD3Rounded.createBitmap(32, 32, 8);
				decR.color = MD3Theme.primaryContainer;
				add(decR);
				allRowMembers.push(decR);
				rowDecR.push(decR);
				var decRText:FlxText = new FlxText(0, 0, 0, '>', 14);
				decRText.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onPrimaryContainer, CENTER);
				decRText.setPosition(decR.x + (32 - decRText.width) / 2, decR.y + 8);
				add(decRText);
				allRowMembers.push(decRText);

				updateSkipTimeText();
			}
			else
			{
				rowSwitches.push(null);
				rowValues.push(null);
				rowDecL.push(null);
				rowDecR.push(null);
			}
		}

		curSelected = 0;
		recolorRows();
	}

	function updateSkipTimeText():Void
	{
		if (skipRowIdx < 0 || skipRowIdx >= rowValues.length || rowValues[skipRowIdx] == null) return;
		rowValues[skipRowIdx].text = FlxStringUtil.formatTime(Math.max(0, Math.floor(curTime / 1000)), false) + ' / '
			+ FlxStringUtil.formatTime(Math.max(0, Math.floor(FlxG.sound.music.length / 1000)), false);
	}

	function syncSwitchVisuals():Void
	{
		for (i in 0...menuItems.length)
		{
			if (rowSwitches[i] == null) continue;
			var key:String = menuItems[i];
			if (key == 'Toggle Practice Mode') rowSwitches[i].on = PlayState.instance.practiceMode;
			else if (key == 'Toggle Botplay') rowSwitches[i].on = PlayState.instance.cpuControlled;
		}
	}

	// ===== 触控 =====
	#if mobile
	// 触控状态机: 未选中行=仅选中; 已选中行=激活; 跳转时间行◀▶/拖扫/抬起应用
	var tId:Int = -1;
	var tRow:Int = -1;
	var tScrub:Bool = false;
	var tLastX:Float = 0;
	var tTotalDx:Float = 0;

	function handleTouch(elapsed:Float):Void
	{
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed)
			{
				tId = touch.touchPointID;
				tRow = -1;
				tScrub = false;
				tTotalDx = 0;
				tLastX = touch.x;

				if (hitSpr(touch, backBtn))
				{
					backend.PerfProbe.log('[暂停] down x=' + Math.round(touch.x) + ' y=' + Math.round(touch.y) + ' 返回钮');
					if (cantUnpause <= 0) onBack();
					continue;
				}

				var hitDesc:String = '无命中';
				for (i in 0...rowCards.length)
				{
					var card:FlxSprite = rowCards[i];
					if (touch.x >= card.x && touch.x <= card.x + card.width && touch.y >= card.y && touch.y <= card.y + card.height)
					{
						tRow = i;
						var key:String = menuItems[i];
						hitDesc = '行' + i + ':' + labelOf(key);
						if (curSelected != i)
						{
							selectTo(i);	// 第一触: 仅选中(触控二段确认, 继续行恒选中故单击即续)
							hitDesc += ' (选中)';
						}
						else if (cantUnpause > 0)
						{
							hitDesc += ' (防误触忽略)';
						}
						else if (key == 'Skip Time')
						{
							if (hitSpr(touch, rowDecL[i])) { curTime -= 1000; wrapSkipTime(); updateSkipTimeText(); hitDesc += ' ◀'; }
							else if (hitSpr(touch, rowDecR[i])) { curTime += 1000; wrapSkipTime(); updateSkipTimeText(); hitDesc += ' ▶'; }
							else tScrub = true;	// 行身: 拖=扫秒, 抬起位移<20px=应用
						}
						else
						{
							hitDesc += ' (激活)';
							activateCurrent();
						}
						break;
					}
				}
				backend.PerfProbe.log('[暂停] down x=' + Math.round(touch.x) + ' y=' + Math.round(touch.y) + ' ' + hitDesc);
				continue;
			}

			if (touch.touchPointID != tId) continue;

			if (touch.pressed)
			{
				var dx:Float = touch.x - tLastX;
				tLastX = touch.x;
				tTotalDx += dx;
				if (tScrub)
				{
					curTime += dx * 500;	// 0.5秒/px
					wrapSkipTime();
					updateSkipTimeText();
				}
			}
			else if (touch.justReleased)
			{
				if (tScrub && tRow >= 0 && Math.abs(tTotalDx) < 20)
				{
					backend.PerfProbe.log('[暂停] up 应用跳转 t=' + Math.round(curTime));
					activateCurrent();	// curSelected 已在按下时 selectTo
				}
				tId = -1;
				tRow = -1;
				tScrub = false;
			}
		}

		// 丢失检测(触点被池化回收, 不含justReleased帧)
		if (tId != -1)
		{
			var still:Bool = false;
			for (t in FlxG.touches.list)
				if (t.touchPointID == tId) { still = true; break; }
			if (!still) { tId = -1; tRow = -1; tScrub = false; }
		}
	}

	function hitSpr(touch:FlxTouch, spr:FlxSprite):Bool
	{
		if (spr == null || !spr.visible) return false;
		return touch.x >= spr.x - 6 && touch.x <= spr.x + spr.width + 6
			&& touch.y >= spr.y - 6 && touch.y <= spr.y + spr.height + 6;
	}
	#end
}
