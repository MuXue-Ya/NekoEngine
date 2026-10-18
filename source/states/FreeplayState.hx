package states;

import backend.WeekData;
import backend.Highscore;
import backend.Song;

import objects.HealthIcon;
import objects.MusicPlayer;

import substates.GameplayChangersSubstate;
import substates.ResetScoreSubState;

#if mobile
import mobile.backend.MobileUtil;
import mobile.backend.utils.TouchMenuUtil;
#end

import ui.md3.MD3Rounded;
import ui.md3.MD3Theme;

import flixel.input.touch.FlxTouch;
import flixel.math.FlxMath;

/**
 * 自由游戏 (MD3):
 *   左侧歌曲卡片列表(滚动窗口) + 右侧详情面板(图标/难度分段/个人最佳/试听/清分) + ▶开始
 * 逻辑(周加载/难度/试听/清分/载入流程)与原版一致, 仅重写 UI 层。
 */
class FreeplayState extends MusicBeatState
{
	var songs:Array<SongMetadata> = [];

	// UI布局常量
	var listX:Float = 36;
	var rowH:Float = 56;
	var rowGap:Float = 10;
	var listY:Float = 240;	// 选中卡片的纵向位置(过高压回按钮)
	var _drawDistance:Int = 5;

	private static var curSelected:Int = 0;
	var lerpSelected:Float = 0;
	var curDifficulty:Int = -1;
	private static var lastDifficultyName:String = Difficulty.getDefault();

	// 歌曲行平行数组
	var cards:Array<FlxSprite> = [];
	var icons:Array<HealthIcon> = [];
	var nameTexts:Array<FlxText> = [];
	var bestTexts:Array<FlxText> = [];
	var _lastVisibles:Array<Int> = [];

	// 详情面板
	var panelX:Float = 830;
	var panelW:Float = 414;
	var panelY:Float = 100;
	var iconBig:HealthIcon;
	var songNameText:FlxText;
	var charNameText:FlxText;
	var diffNameText:FlxText;
	var diffLBtn:FlxSprite;
	var diffRBtn:FlxSprite;
	var bestValueText:FlxText;
	var ratingText:FlxText;
	var listenBtn:FlxSprite;
	var resetBtn:FlxSprite;
	var playBtn:FlxSprite;
	var panelCard:FlxSprite;
	var listenText:FlxText;

	var changersText:FlxText;
	var changersBtn:FlxSprite;
	var changersIcon:FlxSprite;
	var panelExtras:Array<FlxText> = [];	// 面板伴生文字(随面板显隐)
	var backBtn:FlxSprite;
	var backIcon:FlxSprite;
	var lerpScore:Int = 0;
	var lerpRating:Float = 0;
	var intendedScore:Int = 0;
	var intendedRating:Float = 0;

	private var instPlaying:Int = -1;
	public static var vocals:FlxSound = null;
	var holdTime:Float = 0;

	var bg:FlxSprite;
	var intendedColor:Int;
	var colorTween:FlxTween;

	var missingTextBG:FlxSprite;
	var missingText:FlxText;

	var player:MusicPlayer;

	override function create()
	{
		persistentUpdate = true;
		PlayState.isStoryMode = false;
		WeekData.reloadWeekFiles(false);

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menus", null);
		#end

		for (i in 0...WeekData.weeksList.length) {
			if(weekIsLocked(WeekData.weeksList[i])) continue;

			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			var leSongs:Array<String> = [];
			var leChars:Array<String> = [];

			for (j in 0...leWeek.songs.length)
			{
				leSongs.push(leWeek.songs[j][0]);
				leChars.push(leWeek.songs[j][1]);
			}

			WeekData.setDirectoryFromWeek(leWeek);
			for (song in leWeek.songs)
			{
				var colors:Array<Int> = song[2];
				if(colors == null || colors.length < 3)
				{
					colors = [146, 113, 253];
				}
				addSong(song[0], i, song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2]));
			}
		}
		Mods.loadTopMod();

		// ===== 背景 + 罩层 =====
		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		add(bg);
		bg.screenCenter();

		var shade:FlxSprite = new FlxSprite().makeGraphic(1, 1, MD3Theme.surface);
		shade.scale.set(FlxG.width + 10, FlxG.height + 10);
		shade.updateHitbox();
		shade.screenCenter();
		shade.scrollFactor.set();
		shade.alpha = 0.65;
		add(shade);

		// 左上角返回按钮(‹): 试听中=停止试听, 否则回主菜单
		backBtn = new FlxSprite(36, 18);
		backBtn.pixels = MD3Rounded.createBitmap(44, 44, 22);
		backBtn.color = MD3Theme.surfaceContainerHigh;
		add(backBtn);
		backIcon = new FlxSprite(backBtn.x + 8, backBtn.y + 8);
		backIcon.pixels = MD3Rounded.createBackArrow(28, 3);
		backIcon.color = 0xFFFFFFFF;
		add(backIcon);

		// ===== 歌曲卡片列表 =====
		for (i in 0...songs.length)
		{
			var cy:Float = listY + i * (rowH + rowGap);

			var card:FlxSprite = new FlxSprite(listX, cy);
			card.pixels = MD3Rounded.createBitmap(764, rowH, 12);
			card.color = MD3Theme.surfaceContainer;
			card.alpha = 0.85;
			card.visible = card.active = false;
			add(card);
			cards.push(card);

			var icon:HealthIcon = new HealthIcon(songs[i].songCharacter);
			icon.setGraphicSize(40, 40);
			icon.updateHitbox();
			icon.setPosition(listX + 8, cy + 8);
			icon.visible = icon.active = false;
			add(icon);
			icons.push(icon);

			var nameT:FlxText = new FlxText(listX + 56, cy + 15, 0, songs[i].songName, 20);
			nameT.setFormat(Paths.font('vcr.ttf'), 20, MD3Theme.onSurface);
			nameT.scale.set(Math.min(1, 558 / Math.max(1, nameT.width)), 1);	// 超宽歌名压缩(原版行为)
			nameT.visible = nameT.active = false;
			add(nameT);
			nameTexts.push(nameT);

			var bestT:FlxText = new FlxText(listX + 764 - 150, cy + 19, 138, '', 14);
			bestT.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onSurfaceVariant, RIGHT);
			bestT.visible = bestT.active = false;
			add(bestT);
			bestTexts.push(bestT);
		}
		WeekData.setDirectoryFromWeek();

		// ===== 右侧详情面板 =====
		panelCard = new FlxSprite(panelX, panelY);
		panelCard.pixels = MD3Rounded.createBitmap(panelW, 584, 22);
		panelCard.color = MD3Theme.surfaceContainer;
		panelCard.alpha = 0.9;
		add(panelCard);

		iconBig = new HealthIcon(songs[curSelected].songCharacter);
		iconBig.setGraphicSize(72, 72);
		iconBig.updateHitbox();
		iconBig.setPosition(panelX + (panelW - 72) / 2, panelY + 22);
		add(iconBig);

		songNameText = new FlxText(panelX + 16, panelY + 104, panelW - 32, songs[curSelected].songName, 26);
		songNameText.setFormat(Paths.font('vcr.ttf'), 26, MD3Theme.onSurface, CENTER);
		add(songNameText);

		charNameText = new FlxText(panelX + 16, panelY + 140, panelW - 32, songs[curSelected].songCharacter, 14);
		charNameText.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onSurfaceVariant, CENTER);
		add(charNameText);

		// 难度分段: ◀ 名称 ▶
		diffLBtn = new FlxSprite(panelX + 48, panelY + 180);
		diffLBtn.pixels = MD3Rounded.createBitmap(44, 44, 12);
		diffLBtn.color = MD3Theme.primaryContainer;
		add(diffLBtn);
		var diffLText:FlxText = new FlxText(0, 0, 0, '<', 22);
		diffLText.setFormat(Paths.font('vcr.ttf'), 22, MD3Theme.onPrimaryContainer, CENTER);
		diffLText.setPosition(diffLBtn.x + (44 - diffLText.width) / 2, diffLBtn.y + 10);
		add(diffLText);
		panelExtras.push(diffLText);

		diffRBtn = new FlxSprite(panelX + panelW - 92, panelY + 180);
		diffRBtn.pixels = MD3Rounded.createBitmap(44, 44, 12);
		diffRBtn.color = MD3Theme.primaryContainer;
		add(diffRBtn);
		var diffRText:FlxText = new FlxText(0, 0, 0, '>', 22);
		diffRText.setFormat(Paths.font('vcr.ttf'), 22, MD3Theme.onPrimaryContainer, CENTER);
		diffRText.setPosition(diffRBtn.x + (44 - diffRText.width) / 2, diffRBtn.y + 10);
		add(diffRText);
		panelExtras.push(diffRText);

		diffNameText = new FlxText(panelX + 100, panelY + 190, panelW - 200, '', 20);
		diffNameText.setFormat(Paths.font('vcr.ttf'), 20, MD3Theme.onSurface, CENTER);
		add(diffNameText);

		var bestLabel:FlxText = new FlxText(panelX + 16, panelY + 252, panelW - 32, '个人最佳', 14);
		bestLabel.setFormat(Paths.font('vcr.ttf'), 14, MD3Theme.onSurfaceVariant, CENTER);
		add(bestLabel);
		panelExtras.push(bestLabel);

		bestValueText = new FlxText(panelX + 16, panelY + 274, panelW - 32, '0', 26);
		bestValueText.setFormat(Paths.font('vcr.ttf'), 26, MD3Theme.onSurface, CENTER);
		add(bestValueText);

		ratingText = new FlxText(panelX + 16, panelY + 310, panelW - 32, '', 16);
		ratingText.setFormat(Paths.font('vcr.ttf'), 16, MD3Theme.onSurfaceVariant, CENTER);
		add(ratingText);

		// 试听 / 清分
		listenBtn = new FlxSprite(panelX + 16, panelY + 344);
		listenBtn.pixels = MD3Rounded.createBitmap((panelW - 48) / 2, 44, 12);
		listenBtn.color = MD3Theme.surfaceContainerHigh;
		add(listenBtn);
		listenText = new FlxText(0, 0, 0, '试听', 18);
		listenText.setFormat(Paths.font('vcr.ttf'), 18, MD3Theme.onSurface, CENTER);
		listenText.setPosition(listenBtn.x + (listenBtn.width - listenText.width) / 2, listenBtn.y + 12);
		add(listenText);
		panelExtras.push(listenText);

		resetBtn = new FlxSprite(panelX + 32 + (panelW - 48) / 2, panelY + 344);
		resetBtn.pixels = MD3Rounded.createBitmap((panelW - 48) / 2, 44, 12);
		resetBtn.color = MD3Theme.surfaceContainerHigh;
		add(resetBtn);
		var resetText:FlxText = new FlxText(0, 0, 0, '清分数', 18);
		resetText.setFormat(Paths.font('vcr.ttf'), 18, MD3Theme.onSurface, CENTER);
		resetText.setPosition(resetBtn.x + (resetBtn.width - resetText.width) / 2, resetBtn.y + 12);
		add(resetText);
		panelExtras.push(resetText);

		// ▶ 开始大按钮
		playBtn = new FlxSprite(panelX + 16, panelY + 504);
		playBtn.pixels = MD3Rounded.createBitmap(panelW - 32, 64, 16);
		playBtn.color = MD3Theme.primary;
		add(playBtn);
		var playText:FlxText = new FlxText(0, 0, 0, '开始', 24);
		playText.setFormat(Paths.font('vcr.ttf'), 24, MD3Theme.onPrimary, CENTER);
		playText.setPosition(playBtn.x + (playBtn.width - playText.width) / 2, playBtn.y + 18);
		add(playText);
		panelExtras.push(playText);

		// 缺文件提示(保留)
		missingTextBG = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		add(missingTextBG);

		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font('vcr.ttf'), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		add(missingText);

		// ⚙ 玩法调整(左下角按钮: 流速/回血量/Botplay/练习模式等)
		changersBtn = new FlxSprite(36, FlxG.height - 70);
		changersBtn.pixels = MD3Rounded.createBitmap(190, 44, 12);
		changersBtn.color = MD3Theme.surfaceContainerHigh;
		add(changersBtn);
		changersIcon = new FlxSprite(changersBtn.x + 12, changersBtn.y + 8);
		changersIcon.pixels = MD3Rounded.createIconSliders(28, 3);
		changersIcon.color = 0xFFFFFFFF;
		add(changersIcon);
		changersText = new FlxText(changersBtn.x + 48, changersBtn.y + 12, 0, '玩法调整', 16);
		changersText.setFormat(Paths.font('vcr.ttf'), 16, MD3Theme.onSurface);
		add(changersText);

		player = new MusicPlayer(this);
		add(player);

		if(curSelected >= songs.length) curSelected = 0;
		bg.color = songs[curSelected].color;
		intendedColor = bg.color;
		lerpSelected = curSelected;

		curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(lastDifficultyName)));

		refreshDetail();
		refreshRowScores();
		changeSelection(0, false);
		updateCards(0);
		super.create();
	}

	override function closeSubState() {
		changeSelection(0, false);
		persistentUpdate = true;
		refreshRowScores();
		super.closeSubState();
	}

	public function addSong(songName:String, weekNum:Int, songCharacter:String, color:Int)
	{
		songs.push(new SongMetadata(songName, weekNum, songCharacter, color));
	}

	function weekIsLocked(name:String):Bool {
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		return (!leWeek.startUnlocked && leWeek.weekBefore.length > 0 && (!StoryMenuState.weekCompleted.exists(leWeek.weekBefore) || !StoryMenuState.weekCompleted.get(leWeek.weekBefore)));
	}

	// ===== 触控按钮(mobile) =====
	#if mobile
	function handlePanelTouch():Void
	{
		if (missingTextBG.visible) return;
		for (touch in FlxG.touches.list)
		{
			if (!touch.justPressed) continue;
			if (hitBtn(touch, diffLBtn) && !player.playingMusic) { changeDiff(-1); _updateSongLastDifficulty(); }
			else if (hitBtn(touch, diffRBtn) && !player.playingMusic) { changeDiff(1); _updateSongLastDifficulty(); }
			else if (hitBtn(touch, listenBtn)) toggleListen();
			else if (hitBtn(touch, resetBtn) && !player.playingMusic) openResetScore();
			else if (hitBtn(touch, playBtn) && !player.playingMusic) startSong();
			else if (hitBtn(touch, changersBtn) && !player.playingMusic) openChangers();
		}
	}

	function hitBtn(touch:FlxTouch, btn:FlxSprite):Bool
	{
		if (btn == null || !btn.visible) return false;
		return touch.x >= btn.x - 8 && touch.x <= btn.x + btn.width + 8
			&& touch.y >= btn.y - 8 && touch.y <= btn.y + btn.height + 8;
	}
	#end

	// ===== 原版逻辑: 触发函数化(供键盘与触控共用) =====

	function openChangers():Void
	{
		persistentUpdate = false;
		openSubState(new GameplayChangersSubstate());
	}

	function toggleListen():Void
	{
		if(instPlaying != curSelected && !player.playingMusic)
		{
			destroyFreeplayVocals();
			FlxG.sound.music.volume = 0;

			Mods.currentModDirectory = songs[curSelected].folder;
			var poop:String = Highscore.formatSong(songs[curSelected].songName.toLowerCase(), curDifficulty);
			PlayState.SONG = Song.loadFromJson(poop, songs[curSelected].songName.toLowerCase());
			if (PlayState.SONG.needsVoices)
			{
				vocals = new FlxSound().loadEmbedded(Paths.voices(PlayState.SONG.song));
				FlxG.sound.list.add(vocals);
				vocals.persist = true;
				vocals.looped = true;
			}
			else if (vocals != null)
			{
				vocals.stop();
				vocals.destroy();
				vocals = null;
			}

			FlxG.sound.playMusic(Paths.inst(PlayState.SONG.song), 0.8);
			if(vocals != null) //Sync vocals to Inst
			{
				vocals.play();
				vocals.volume = 0.8;
			}
			instPlaying = curSelected;

			player.playingMusic = true;
			player.curTime = 0;
			player.switchPlayMusic();
		}
		else if (instPlaying == curSelected && player.playingMusic)
		{
			player.pauseOrResume(player.paused);
		}
	}

	function startSong():Void
	{
		if (player.playingMusic) return;
		persistentUpdate = false;
		var songLowercase:String = Paths.formatToSongPath(songs[curSelected].songName);
		var poop:String = Highscore.formatSong(songLowercase, curDifficulty);
		try
		{
			PlayState.SONG = Song.loadFromJson(poop, songLowercase);
			PlayState.isStoryMode = false;
			PlayState.storyDifficulty = curDifficulty;

			if(colorTween != null) {
				colorTween.cancel();
			}
		}
		catch(e:Dynamic)
		{
			var errorStr:String = e.toString();
			if(errorStr.startsWith('[file_contents,assets/data/')) errorStr = 'Missing file: ' + errorStr.substring(34, errorStr.length-1); //Missing chart
			missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
			missingText.screenCenter(Y);
			missingText.visible = true;
			missingTextBG.visible = true;
			FlxG.sound.play(Paths.sound('cancelMenu'));

			updateCards(0);
			super.update(0);
			return;
		}
		LoadingState.loadAndSwitchState(new PlayState());

		FlxG.sound.music.volume = 0;

		destroyFreeplayVocals();
		#if (MODS_ALLOWED && DISCORD_ALLOWED)
		DiscordClient.loadModRPC();
		#end
	}

	function openResetScore():Void
	{
		persistentUpdate = false;
		openSubState(new ResetScoreSubState(songs[curSelected].songName, curDifficulty, songs[curSelected].songCharacter));
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	function doBack():Void
	{
		if (player.playingMusic)
		{
			// 试听中: 停止试听, 恢复菜单音乐(留在本页)
			FlxG.sound.music.stop();
			destroyFreeplayVocals();
			FlxG.sound.music.volume = 0;
			instPlaying = -1;

			player.playingMusic = false;
			player.switchPlayMusic();

			FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
			FlxTween.tween(FlxG.sound.music, {volume: 1}, 1);
		}
		else
		{
			persistentUpdate = false;
			if(colorTween != null) {
				colorTween.cancel();
			}
			FlxG.sound.play(Paths.sound('cancelMenu'));
			MusicBeatState.switchState(new MainMenuState());
		}
	}

	public static function destroyFreeplayVocals() {
		if(vocals != null) {
			vocals.stop();
			vocals.destroy();
		}
		vocals = null;
	}

	function changeDiff(change:Int = 0)
	{
		if (player.playingMusic)
			return;

		curDifficulty += change;

		if (curDifficulty < 0)
			curDifficulty = Difficulty.list.length-1;
		if (curDifficulty >= Difficulty.list.length)
			curDifficulty = 0;

		#if !switch
		intendedScore = Highscore.getScore(songs[curSelected].songName, curDifficulty);
		intendedRating = Highscore.getRating(songs[curSelected].songName, curDifficulty);
		#end

		lastDifficultyName = Difficulty.getString(curDifficulty);
		diffNameText.text = Difficulty.getString(curDifficulty).toUpperCase();

		refreshDetail();
		refreshRowScores();
		missingText.visible = false;
		missingTextBG.visible = false;
	}

	// ===== 选择(原版逻辑, 视觉部分换新UI) =====

	function changeSelection(change:Int = 0, playSound:Bool = true)
	{
		if (player.playingMusic)
			return;

		_updateSongLastDifficulty();
		if(playSound) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		var lastList:Array<String> = Difficulty.list;
		curSelected += change;

		if (curSelected < 0)
			curSelected = songs.length - 1;
		if (curSelected >= songs.length)
			curSelected = 0;

		var newColor:Int = songs[curSelected].color;
		if(newColor != intendedColor) {
			if(colorTween != null) {
				colorTween.cancel();
			}
			intendedColor = newColor;
			colorTween = FlxTween.color(bg, 1, bg.color, intendedColor, {
				onComplete: function(twn:FlxTween) {
					colorTween = null;
				}
			});
		}

		refreshListVisuals();

		Mods.currentModDirectory = songs[curSelected].folder;
		PlayState.storyWeek = songs[curSelected].week;
		Difficulty.loadFromWeek();

		var savedDiff:String = songs[curSelected].lastDifficulty;
		var lastDiff:Int = Difficulty.list.indexOf(lastDifficultyName);
		if(savedDiff != null && !lastList.contains(savedDiff) && Difficulty.list.contains(savedDiff))
			curDifficulty = Math.round(Math.max(0, Difficulty.list.indexOf(savedDiff)));
		else if(lastDiff > -1)
			curDifficulty = lastDiff;
		else if(Difficulty.list.contains(Difficulty.getDefault()))
			curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(Difficulty.getDefault())));
		else
			curDifficulty = 0;

		changeDiff();
		_updateSongLastDifficulty();
	}

	function refreshListVisuals():Void
	{
		for (i in 0...cards.length)
		{
			var sel:Bool = (i == curSelected);
			cards[i].color = sel ? MD3Theme.primaryContainer : MD3Theme.surfaceContainer;
			cards[i].alpha = sel ? 1 : 0.85;
			nameTexts[i].color = sel ? MD3Theme.onSurface : MD3Theme.onSurfaceVariant;
			icons[i].alpha = sel ? 1 : 0.6;
		}
	}

	inline private function _updateSongLastDifficulty()
	{
		songs[curSelected].lastDifficulty = Difficulty.getString(curDifficulty);
	}

	public function setDetailPanelVisible(v:Bool):Void
	{
		panelCard.visible = v;
		iconBig.visible = v;
		songNameText.visible = v;
		charNameText.visible = v;
		diffLBtn.visible = v;
		diffRBtn.visible = v;
		diffNameText.visible = v;
		bestValueText.visible = v;
		ratingText.visible = v;
		listenBtn.visible = v;
		resetBtn.visible = v;
		playBtn.visible = v;
		for (t in panelExtras)
			t.visible = v;
	}

	function refreshDetail():Void
	{
		iconBig.changeIcon(songs[curSelected].songCharacter);
		iconBig.setGraphicSize(72, 72);
		iconBig.updateHitbox();
		songNameText.text = songs[curSelected].songName;
		charNameText.text = songs[curSelected].songCharacter;
	}

	function refreshRowScores():Void
	{
		for (i in 0...songs.length)
			bestTexts[i].text = Std.string(Highscore.getScore(songs[i].songName, curDifficulty));
	}

	// ===== 滚动窗口(原 updateTexts 的卡片版) =====

	public function updateCards(elapsed:Float = 0.0)
	{
		lerpSelected = FlxMath.lerp(curSelected, lerpSelected, Math.exp(-elapsed * 9.6));
		for (i in _lastVisibles)
			setRowVisible(i, false);
		_lastVisibles = [];

		var min:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected - _drawDistance)));
		var max:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected + _drawDistance)));
		for (i in min...max)
		{
			setRowVisible(i, true);
			var cy:Float = listY + (i - lerpSelected) * (rowH + rowGap);
			cards[i].y = cy;
			icons[i].y = cy + 8;
			nameTexts[i].y = cy + 15;
			bestTexts[i].y = cy + 19;
			_lastVisibles.push(i);
		}
	}

	function setRowVisible(i:Int, v:Bool):Void
	{
		cards[i].visible = cards[i].active = v;
		icons[i].visible = icons[i].active = v;
		nameTexts[i].visible = nameTexts[i].active = v;
		bestTexts[i].visible = bestTexts[i].active = v;
	}

	override function update(elapsed:Float)
	{
		if (FlxG.sound.music.volume < 0.7)
		{
			FlxG.sound.music.volume += 0.5 * FlxG.elapsed;
		}
		lerpScore = Math.floor(FlxMath.lerp(intendedScore, lerpScore, Math.exp(-elapsed * 24)));
		lerpRating = FlxMath.lerp(intendedRating, lerpRating, Math.exp(-elapsed * 12));

		if (Math.abs(lerpScore - intendedScore) <= 10)
			lerpScore = intendedScore;
		if (Math.abs(lerpRating - intendedRating) <= 0.01)
			lerpRating = intendedRating;

		var ratingSplit:Array<String> = Std.string(CoolUtil.floorDecimal(lerpRating * 100, 2)).split('.');
		if(ratingSplit.length < 2) { //No decimals, add an empty space
			ratingSplit.push('');
		}

		while(ratingSplit[1].length < 2) { //Less than 2 decimals in it, add decimals then
			ratingSplit[1] += '0';
		}

		// 试听按钮动态标签: 未播=试听, 播放中=暂停, 已暂停=继续
		var listenLabel:String = (instPlaying == curSelected && player.playingMusic) ? (player.paused ? '继续试听' : '暂停') : '试听';
		if (listenText.text != listenLabel)
		{
			listenText.text = listenLabel;
			listenText.x = listenBtn.x + (listenBtn.width - listenText.width) / 2;
		}

		if (!player.playingMusic)
		{
			bestValueText.text = '' + lerpScore;
			ratingText.text = '准确率 ' + ratingSplit.join('.') + '%';

			if(songs.length > 1)
			{
				if(FlxG.keys.justPressed.HOME)
				{
					curSelected = 0;
					changeSelection();
					holdTime = 0;
				}
				else if(FlxG.keys.justPressed.END)
				{
					curSelected = songs.length - 1;
					changeSelection();
					holdTime = 0;
				}
				if (controls.UI_UP_P)
				{
					changeSelection(-1);
					holdTime = 0;
				}
				if (controls.UI_DOWN_P)
				{
					changeSelection(1);
					holdTime = 0;
				}

				if(controls.UI_DOWN || controls.UI_UP)
				{
					var checkLastHold:Int = Math.floor((holdTime - 0.5) * 10);
					holdTime += elapsed;
					var checkNewHold:Int = Math.floor((holdTime - 0.5) * 10);

					if(holdTime > 0.5 && checkNewHold - checkLastHold > 0)
						changeSelection((checkNewHold - checkLastHold) * (controls.UI_UP ? -1 : 1));
				}

				if(FlxG.mouse.wheel != 0)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
					changeSelection(-FlxG.mouse.wheel, false);
				}
			}

			if (controls.UI_LEFT_P)
			{
				changeDiff(-1);
				_updateSongLastDifficulty();
			}
			else if (controls.UI_RIGHT_P)
			{
				changeDiff(1);
				_updateSongLastDifficulty();
			}
		}

		if (controls.BACK)
			doBack();

		if(FlxG.keys.justPressed.CONTROL && !player.playingMusic)
			openChangers();
		else if(FlxG.keys.justPressed.SPACE)
			toggleListen();
		else if (controls.ACCEPT && !player.playingMusic)
			startSong();
		else if(controls.RESET && !player.playingMusic)
			openResetScore();

		#if mobile
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed
				&& touch.x >= backBtn.x - 8 && touch.x <= backBtn.x + backBtn.width + 8
				&& touch.y >= backBtn.y - 8 && touch.y <= backBtn.y + backBtn.height + 8)
				doBack();
		}
		handlePanelTouch();
		// 屏幕触控选歌: 点卡片=选中, 再点已选中=开始
		TouchMenuUtil.update(cards, curSelected, function(i:Int) changeSelection(i, false), function(i:Int) changeSelection(i - curSelected, false), startSong);
		#end

		updateCards(elapsed);
		super.update(elapsed);
	}

	override function destroy():Void
	{
		super.destroy();

		FlxG.autoPause = ClientPrefs.data.autoPause;
		if (!FlxG.sound.music.playing)
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
	}
}

class SongMetadata
{
	public var songName:String = "";
	public var week:Int = 0;
	public var songCharacter:String = "";
	public var color:Int = -7179779;
	public var folder:String = "";
	public var lastDifficulty:String = null;

	public function new(song:String, week:Int, songCharacter:String, color:Int)
	{
		this.songName = song;
		this.week = week;
		this.songCharacter = songCharacter;
		this.color = color;
		this.folder = Mods.currentModDirectory;
		if(this.folder == null) this.folder = '';
	}
}
