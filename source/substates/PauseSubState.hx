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
 * 暂停 (MD3 双面板): 左=菜单列表(继续/重开/难度/打谱/设置/退出), 右=歌曲信息+计数+评分。
 * 输入: 触控(点按菜单行/开关/◀▶/左下返回按钮, Run#69) + Android返回键 + 键盘; 虚拟按键已移除
 *      (Run#68 手柄贴图被 ASTC 误压: excludes 路径少 images/ 层, 贴图直读失败)。
 * 关键修复: 子状态内 sprites 默认仍渲染在 camGame(游戏相机,带滚动/缩放)上,
 *          必须显式把每个成员挂到 camOther(恒等相机) —— applyCamAll(), 否则面板跟随相机偏移。
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
	var pageCam:FlxCamera;
	var bg:FlxSprite;
	var titleText:FlxText;
	var badgeText:FlxText;
	var hintText:FlxText;

	var rowCards:Array<FlxSprite> = [];
	var rowLabels:Array<FlxText> = [];
	var rowValues:Array<FlxText> = [];
	var rowSwitches:Array<MD3Switch> = [];
	var rowDecL:Array<FlxSprite> = [];
	var rowDecR:Array<FlxSprite> = [];
	var allRowMembers:Array<FlxBasic> = [];

	// 右侧信息面板
	var infoValues:Array<FlxText> = [];

	var missingTextBG:FlxSprite;
	var missingText:FlxText;

	public static var songName:String = null;

	override function create()
	{
		pageCam = FlxG.cameras.list[FlxG.cameras.list.length - 1];	// camOther(恒等,透明) —— 必须在加虚拟按键相机之前取

		// 保险: 强制主状态进入暂停(万一有路径绕过 openPauseMenu 的设置)
		if (PlayState.instance != null)
		{
			PlayState.instance.persistentUpdate = false;
			PlayState.instance.paused = true;
			if (FlxG.sound.music != null && FlxG.sound.music.playing) FlxG.sound.music.pause();
			if (PlayState.instance.vocals != null) PlayState.instance.vocals.pause();
			if (PlayState.instance.opponentVocals != null) PlayState.instance.opponentVocals.pause();
		}
		backend.PerfProbe.log('[暂停] open persistentUpdate=' + FlxG.state.persistentUpdate
			+ ' paused=' + (PlayState.instance != null && PlayState.instance.paused)
			+ ' musicPlaying=' + (FlxG.sound.music != null && FlxG.sound.music.playing));

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
		FlxTween.tween(bg, {alpha: 0.88}, 0.25, {ease: FlxEase.quartOut});

		titleText = new FlxText(0, 14, FlxG.width, '已暂停', 28);
		titleText.setFormat(Paths.font('vcr.ttf'), 28, MD3Theme.onSurface, CENTER);
		add(titleText);

		badgeText = new FlxText(0, 20, FlxG.width - 36, '', 15);
		badgeText.setFormat(Paths.font('vcr.ttf'), 15, MD3Theme.primary, RIGHT);
		badgeText.visible = false;
		add(badgeText);
		updateBadge();

		// ===== 左面板: 菜单 =====
		var leftPanel:FlxSprite = new FlxSprite(36, 80);
		leftPanel.pixels = MD3Rounded.createBitmap(520, 360, 18);
		leftPanel.color = MD3Theme.surfaceContainer;
		add(leftPanel);
		var leftCap:FlxText = new FlxText(56, 92, 0, '菜单', 14);
		leftCap.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onSurfaceVariant);
		add(leftCap);

		// ===== 右面板: 歌曲信息/计数/评分 =====
		var rightPanel:FlxSprite = new FlxSprite(572, 80);
		rightPanel.pixels = MD3Rounded.createBitmap(672, 360, 18);
		rightPanel.color = MD3Theme.surfaceContainer;
		add(rightPanel);
		var rightCap:FlxText = new FlxText(600, 92, 0, '歌曲信息', 14);
		rightCap.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onSurfaceVariant);
		add(rightCap);
		buildInfoPanel();

		hintText = new FlxText(0, 688, FlxG.width, '点按菜单项操作 · Android返回键/左下按钮 = 返回', 14);
		hintText.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onSurfaceVariant, CENTER);
		add(hintText);

		// 谱面加载失败浮层(原版语义, 加在面板之上)
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

		#if mobile
		// 触控返回按钮(左下角): 虚拟手柄已移除(Run#68 ASTC 误压手柄贴图), 暂停页改纯触控
		backTouchBtn = new FlxSprite(36, 682);
		backTouchBtn.pixels = MD3Rounded.createBitmap(120, 36, 10);
		backTouchBtn.color = MD3Theme.surfaceContainerHigh;
		add(backTouchBtn);
		backTouchText = new FlxText(0, 0, 0, '返回', 15);
		backTouchText.setFormat(Paths.font('vcr.ttf'), 15, MD3Theme.onSurface, CENTER);
		backTouchText.setPosition(backTouchBtn.x + (backTouchBtn.width - backTouchText.width) / 2,
			backTouchBtn.y + (backTouchBtn.height - backTouchText.height) / 2);
		add(backTouchText);
		#end

		// 关键: 本子状态所有成员显式挂到恒等相机(默认会落在 camGame 上跟随相机偏移)
		applyCamAll();
		cameras = [pageCam];

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
		// 预选当前难度(而非第一行), 避免误按即刻换难度重开
		if (PlayState.storyDifficulty >= 0 && PlayState.storyDifficulty < menuItems.length - 1)
		{
			curSelected = PlayState.storyDifficulty;
			recolorRows();
		}
	}
	function goChartList():Void { curPage = 2; menuItems = chartChoices; regenMenu(); }

	function onBack():Void
	{
		if (curPage != 0) { FlxG.sound.play(Paths.sound('cancelMenu')); backend.PerfProbe.log('[暂停] back->主列表'); goMainList(); return; }
		backend.PerfProbe.log('[暂停] close 原因=BACK/继续');
		close();
	}

	var holdTime:Float = 0;
	var cantUnpause:Float = 0.1;
	var heartbeatT:Float = 0;
	override function update(elapsed:Float)
	{
		heartbeatT += elapsed;
		if (heartbeatT >= 1)
		{
			heartbeatT = 0;
			backend.PerfProbe.log('[暂停] 心跳 persistentUpdate=' + FlxG.state.persistentUpdate
				+ ' paused=' + (PlayState.instance != null && PlayState.instance.paused)
				+ ' songPos=' + Math.round(Conductor.songPosition)
				+ ' musicPlaying=' + (FlxG.sound.music != null && FlxG.sound.music.playing));
		}

		cantUnpause -= elapsed;
		if (pauseMusic.volume < 0.5)
			pauseMusic.volume += 0.01 * elapsed;

		super.update(elapsed);

		#if mobile
		handleTouch(elapsed);
		#end

		#if android
		if (FlxG.android.justReleased.BACK) { onBack(); return; }
		#end
		if (controls.BACK) { onBack(); return; }

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

	// ===== 动作(键盘ACCEPT/虚拟按键共用; 语义=原版) =====

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
				backend.PerfProbe.log('[暂停] close 原因=继续');
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
				updateInfoPanel();
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
				updateInfoPanel();
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

	function recolorRows():Void
	{
		for (j in 0...rowCards.length)
			rowCards[j].color = (j == curSelected) ? MD3Theme.primaryContainer : MD3Theme.surfaceContainerHigh;
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

		// 行几何: 左面板(36,80,520,360)内 x=56 w=480 h=40 pitch=44 首行 y=118
		for (i in 0...menuItems.length)
		{
			var key:String = menuItems[i];
			var cy:Float = 118 + i * 44;

			var card:FlxSprite = new FlxSprite(56, cy);
			card.pixels = MD3Rounded.createBitmap(480, 40, 10);
			card.color = MD3Theme.surfaceContainerHigh;
			add(card);
			allRowMembers.push(card);
			rowCards.push(card);

			// 难度子页: 原始难度名 + 返回; 其余页: labelOf 中文
			var labelText:String = (curPage == 1 && key != 'BACK') ? key : labelOf(key);
			var label:FlxText = new FlxText(76, cy + 9, 0, labelText, 17);
			label.setFormat(Paths.font('vcr.ttf'), 17, MD3Theme.onSurface);
			add(label);
			allRowMembers.push(label);
			rowLabels.push(label);

			if (key == 'Toggle Practice Mode' || key == 'Toggle Botplay')
			{
				var sw:MD3Switch = new MD3Switch(456, cy + 4,
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
				var valT:FlxText = new FlxText(200, cy + 11, 150, '', 15);
				valT.setFormat(Paths.font('vcr.ttf'), 15, MD3Theme.onSurfaceVariant, RIGHT);
				add(valT);
				allRowMembers.push(valT);
				rowValues.push(valT);

				var decL:FlxSprite = new FlxSprite(360, cy + 4);
				decL.pixels = MD3Rounded.createBitmap(32, 32, 8);
				decL.color = MD3Theme.primaryContainer;
				add(decL);
				allRowMembers.push(decL);
				rowDecL.push(decL);
				var decLText:FlxText = new FlxText(0, 0, 0, '<', 14);
				decLText.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onPrimaryContainer, CENTER);
				decLText.setPosition(decL.x + (32 - decLText.width) / 2, decL.y + 7);
				add(decLText);
				allRowMembers.push(decLText);

				var decR:FlxSprite = new FlxSprite(398, cy + 4);
				decR.pixels = MD3Rounded.createBitmap(32, 32, 8);
				decR.color = MD3Theme.primaryContainer;
				add(decR);
				allRowMembers.push(decR);
				rowDecR.push(decR);
				var decRText:FlxText = new FlxText(0, 0, 0, '>', 14);
				decRText.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onPrimaryContainer, CENTER);
				decRText.setPosition(decR.x + (32 - decRText.width) / 2, decR.y + 7);
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
		applyCamAll();
	}

	// ===== 右侧信息面板 =====

	function buildInfoPanel():Void
	{
		var labels:Array<String> = ['曲名', '难度', '进度', '得分', '失误', '死亡次数', '评分', '模式'];
		for (i in 0...labels.length)
		{
			var ly:Float = 120 + i * 39;
			var l:FlxText = new FlxText(600, ly, 0, labels[i], 16);
			l.setFormat(Paths.font('vcr.ttf'), 16, MD3Theme.onSurfaceVariant);
			add(l);

			var v:FlxText = new FlxText(760, ly, 456, '', 16);
			v.setFormat(Paths.font('vcr.ttf'), 16, MD3Theme.onSurface, RIGHT);
			add(v);
			infoValues.push(v);
		}
		updateInfoPanel();
	}

	function updateInfoPanel():Void
	{
		if (infoValues.length < 8 || PlayState.instance == null) return;
		infoValues[0].text = PlayState.SONG.song;
		infoValues[1].text = Difficulty.getString();
		infoValues[2].text = FlxStringUtil.formatTime(Math.max(0, Math.floor(Conductor.songPosition / 1000)), false)
			+ ' / ' + FlxStringUtil.formatTime(Math.max(0, Math.floor(FlxG.sound.music.length / 1000)), false);
		infoValues[3].text = Std.string(PlayState.instance.songScore);
		infoValues[4].text = Std.string(PlayState.instance.songMisses);
		infoValues[5].text = Std.string(PlayState.deathCounter);
		if (PlayState.instance.totalPlayed > 0)
			infoValues[6].text = PlayState.instance.ratingName + ' ' + CoolUtil.floorDecimal(PlayState.instance.ratingPercent * 100, 2) + '%';
		else
			infoValues[6].text = '—';
		var modeStr:String = '';
		if (PlayState.chartingMode) modeStr += '打谱:开 ';
		modeStr += '练习:' + (PlayState.instance.practiceMode ? '开' : '关');
		modeStr += ' 猫娘替你打喵:' + (PlayState.instance.cpuControlled ? '开' : '关');
		infoValues[7].text = modeStr;
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

	// ===== 触控(点按式; 子状态成员都挂恒等 pageCam, 成员坐标=屏幕坐标, 可直接与 touch.x/y 比对) =====

	#if mobile
	var backTouchBtn:FlxSprite;
	var backTouchText:FlxText;
	var tHoldId:Int = -1;	// 按住 ◀▶ 连续调时间的触点
	var tHoldDir:Int = 0;	// -1=◀ +1=▶

	inline function inSpr(touch:FlxTouch, s:FlxSprite):Bool
	{
		if (s == null) return false;
		return touch.x >= s.x && touch.x <= s.x + s.width && touch.y >= s.y && touch.y <= s.y + s.height;
	}

	function handleTouch(elapsed:Float):Void
	{
		// 按住 ◀▶ 连续调时间(对齐键盘 UI_LEFT/RIGHT 的 holdTime 逻辑)
		if (tHoldId != -1)
		{
			var still:Bool = false;
			var cx:Float = 0, cy:Float = 0;
			for (touch in FlxG.touches.list)
				if (touch.touchPointID == tHoldId && (touch.pressed || touch.justPressed)) { still = true; cx = touch.x; cy = touch.y; break; }
			var btn:FlxSprite = (skipRowIdx >= 0) ? (tHoldDir < 0 ? rowDecL[skipRowIdx] : rowDecR[skipRowIdx]) : null;
			if (!still || btn == null || !inSprPoint(cx, cy, btn))
			{
				tHoldId = -1; tHoldDir = 0;
			}
			else
			{
				holdTime += elapsed;
				curTime += 45000 * elapsed * tHoldDir;
				wrapSkipTime();
				updateSkipTimeText();
			}
		}

		for (touch in FlxG.touches.list)
		{
			if (!touch.justPressed) continue;
			var desc:String = '无命中';
			if (inSpr(touch, backTouchBtn))
			{
				desc = '返回按钮';
				backend.PerfProbe.log('[暂停触控] down ' + desc);
				onBack();
				continue;
			}

			if (cantUnpause > 0) continue;	// 进暂停瞬间的残留触点不响应

			for (i in 0...rowCards.length)
			{
				var card:FlxSprite = rowCards[i];
				if (!(touch.x >= card.x && touch.x <= card.x + card.width && touch.y >= card.y && touch.y <= card.y + card.height))
					continue;

				var key:String = menuItems[i];
				desc = '行' + i + ':' + labelOf(key);
				if (i == skipRowIdx)
				{
					// Skip Time 行: 点◀▶调时间(支持按住连调), 点行其他区域仅选中(防误触跳转)
					curSelected = i;
					recolorRows();
					if (inSpr(touch, rowDecL[i]))
					{
						FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
						curTime -= 1000; holdTime = 0;
						tHoldId = touch.touchPointID; tHoldDir = -1;
						desc += ' ◀';
					}
					else if (inSpr(touch, rowDecR[i]))
					{
						FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
						curTime += 1000; holdTime = 0;
						tHoldId = touch.touchPointID; tHoldDir = 1;
						desc += ' ▶';
					}
					wrapSkipTime();
					updateSkipTimeText();
				}
				else
				{
					// 普通行/开关行: 点击=选中并执行(开关行整行都是切换热区, 好点)
					curSelected = i;
					recolorRows();
					desc += ' 激活';
					activateCurrent();
				}
				break;
			}
			backend.PerfProbe.log('[暂停触控] down x=' + Math.round(touch.x) + ' y=' + Math.round(touch.y) + ' ' + desc);
		}
	}

	inline function inSprPoint(px:Float, py:Float, s:FlxSprite):Bool
	{
		if (s == null) return false;
		return px >= s.x && px <= s.x + s.width && py >= s.y && py <= s.y + s.height;
	}
	#end

	// ===== 相机修复: 子状态成员默认渲染在 camGame 上(带滚动/缩放) —— 显式挂到恒等相机 =====

	function applyCamAll():Void
	{
		for (m in members)
		{
			if (m == null) continue;
			applyCam(m);
		}
	}

	function applyCam(m:FlxBasic):Void
	{
		m.cameras = [pageCam];
		if ((m is FlxSpriteGroup))
		{
			var g:FlxSpriteGroup = cast m;
			for (child in g.members)
				if (child != null) child.cameras = [pageCam];
		}
	}
}
