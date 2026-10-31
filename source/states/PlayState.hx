package states;

import backend.Highscore;
import backend.StageData;
import backend.WeekData;
import backend.Song;
import backend.Section;
import backend.Rating;

import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;
import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.animation.FlxAnimationController;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.KeyboardEvent;
import haxe.Json;

import cutscenes.CutsceneHandler;
import cutscenes.DialogueBoxPsych;

import states.StoryMenuState;
import states.FreeplayState;
import states.editors.ChartingState;
import states.editors.CharacterEditorState;

import substates.PauseSubState;
import substates.GameOverSubstate;

#if !flash
import flixel.addons.display.FlxRuntimeShader;
import openfl.filters.ShaderFilter;
#end

#if VIDEOS_ALLOWED
#if (hxCodec >= "3.0.0") import hxcodec.flixel.FlxVideo as VideoHandler;
#elseif (hxCodec >= "2.6.1") import hxcodec.VideoHandler as VideoHandler;
#elseif (hxCodec == "2.6.0") import VideoHandler;
#else import vlc.MP4Handler as VideoHandler; #end
#end

import objects.Note.EventNote;
import objects.*;
import states.stages.objects.*;
#if LUA_ALLOWED
import psychlua.*;
#else
import psychlua.LuaUtils;
import psychlua.HScript;
#end

#if SScript
import tea.SScript;
#end

/**
 * This is where all the Gameplay stuff happens and is managed
 *
 * here's some useful tips if you are making a mod in source:
 *
 * If you want to add your stage to the game, copy states/stages/Template.hx,
 * and put your stage code there, then, on PlayState, search for
 * "switch (curStage)", and add your stage to that list.
 *
 * If you want to code Events, you can either code it on a Stage file or on PlayState, if you're doing the latter, search for:
 *
 * "function eventPushed" - Only called *one time* when the game loads, use it for precaching events that use the same assets, no matter the values
 * "function eventPushedUnique" - Called one time per event, use it for precaching events that uses different assets based on its values
 * "function eventEarlyTrigger" - Used for making your event start a few MILLISECONDS earlier
 * "function triggerEvent" - Called when the song hits your event's timestamp, this is probably what you were looking for
**/
class PlayState extends MusicBeatState
{
	public static var STRUM_X = 42;
	public static var STRUM_X_MIDDLESCROLL = -278;

	public static var ratingStuff:Array<Dynamic> = [
		['You Suck!', 0.2], //From 0% to 19%
		['Shit', 0.4], //From 20% to 39%
		['Bad', 0.5], //From 40% to 49%
		['Bruh', 0.6], //From 50% to 59%
		['Meh', 0.69], //From 60% to 68%
		['Nice', 0.7], //69%
		['Good', 0.8], //From 70% to 79%
		['Great', 0.9], //From 80% to 89%
		['Sick!', 1], //From 90% to 99%
		['Perfect!!', 1] //The value on this one isn't used actually, since Perfect is always "1"
	];

	//event variables
	private var isCameraOnForcedPos:Bool = false;

	public var boyfriendMap:Map<String, Character> = new Map<String, Character>();
	public var dadMap:Map<String, Character> = new Map<String, Character>();
	public var gfMap:Map<String, Character> = new Map<String, Character>();
	public var variables:Map<String, Dynamic> = new Map<String, Dynamic>();

	#if HSCRIPT_ALLOWED
	public var hscriptArray:Array<HScript> = [];
	public var instancesExclude:Array<String> = [];
	#end

	#if LUA_ALLOWED
	public var modchartTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
	public var modchartSprites:Map<String, ModchartSprite> = new Map<String, ModchartSprite>();
	public var modchartTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
	public var modchartSounds:Map<String, FlxSound> = new Map<String, FlxSound>();
	public var modchartTexts:Map<String, FlxText> = new Map<String, FlxText>();
	public var modchartSaves:Map<String, FlxSave> = new Map<String, FlxSave>();
	#end

	public var BF_X:Float = 770;
	public var BF_Y:Float = 100;
	public var DAD_X:Float = 100;
	public var DAD_Y:Float = 100;
	public var GF_X:Float = 400;
	public var GF_Y:Float = 130;

	public var songSpeedTween:FlxTween;
	public var songSpeed(default, set):Float = 1;
	public var songSpeedType:String = "multiplicative";
	public var noteKillOffset:Float = 350;

	public var playbackRate(default, set):Float = 1;

	public var boyfriendGroup:FlxSpriteGroup;
	public var dadGroup:FlxSpriteGroup;
	public var gfGroup:FlxSpriteGroup;
	public static var curStage:String = '';
	public static var stageUI:String = "normal";
	public static var isPixelStage(get, never):Bool;

	@:noCompletion
	static function get_isPixelStage():Bool
		return stageUI == "pixel" || stageUI.endsWith("-pixel");

	public static var SONG:SwagSong = null;
	public static var isStoryMode:Bool = false;
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;

	public var spawnTime:Float = 2000;

	public var inst:FlxSound;
	public var vocals:FlxSound;
	public var opponentVocals:FlxSound;

	public var dad:Character = null;
	public var gf:Character = null;
	public var boyfriend:Character = null;

	public var notes:FlxTypedGroup<Note>;
	public var unspawnNotes:Array<Note> = [];

	// ===== 谱面数据层(窗口化生成): 平铺数据不实例化 Note, 滚动生成 =====
	public var chartTimes:Array<Float> = [];	// 排序后的判定时刻
	public var chartDataI:Array<Int> = [];		// 0-3 方向
	public var chartPress:Array<Bool> = [];		// mustPress
	public var chartSus:Array<Float> = [];		// sustainLength
	public var chartGf:Array<Bool> = [];		// gfNote
	public var chartType:Array<Dynamic> = [];	// noteType(原始 String/Int/null)
	public var chartIdx:Int = 0;			// 下一个待实例化的行
	public var chartStepCrochet:Float = 0;	// 构建期快照: sustain 间距不随中途 BPM/rate 变化(对齐原版全量生成)
	public static inline var CHART_SPAWN_WINDOW:Float = 8000;	// 预生成窗口(ms), 覆盖 playbackRate/multSpeed 最坏情况
	public static inline var CHART_REFILL_CAP:Int = 24;	// 每帧最多实例化的谱面行数: 掉帧后把补帧尖峰摊平(upd尖峰→更深掉帧的恶性循环), 溢出顺延后续帧; 24行/帧@60fps=1440行/s 远超任何谱面密度

	public var eventNotes:Array<EventNote> = [];
	public var evtIdx:Int = 0;			// 下一个待触发的事件行(索引推进, 替代 shift O(n))

	public var camFollow:FlxObject;
	private static var prevCamFollow:FlxObject;
    #if VIDEOS_ALLOWED public var videoSprite:Array<FunkinVideoSprite> = []; #end

	public var strumLineNotes:FlxTypedGroup<StrumNote>;
	public var opponentStrums:FlxTypedGroup<StrumNote>;
	public var playerStrums:FlxTypedGroup<StrumNote>;
	public var grpNoteSplashes:FlxTypedGroup<NoteSplash>;

	public var camZooming:Bool = false;
	public var camZoomingMult:Float = 1;
	public var camZoomingDecay:Float = 1;
	private var curSong:String = "";

	public var gfSpeed:Int = 1;
	public var health(default, set):Float = 1;
	// 平滑血条: 血条显示值缓动追真实 health(开关: 玩法调整-平滑血条; 死亡/判定仍用真实 health)
	public var smoothHealth:Float = 1;
	var smoothHealthOn:Bool = false;	// 平滑血条开关(玩法调整-平滑血条; 旧存档无此键视为开)
	// ===== 图标挤压(源码移植挤压.lua): 按血量三档衰减振荡, miss 静止; x 定位仍由 updateIconsPosition 管理 =====
	// 双振荡器: [0]=玩家 [1]=对手; 对手血量与玩家互补(玩家 100% = 对手 0%), 档位按各自血量取
	public var iconSquashT:Array<Float> = [0, 0];
	public var iconSquashAmp:Array<Float> = [0.3, 0.3];
	public var iconSquashFreq:Array<Float> = [18, 18];
	public var iconSquashDamp:Array<Float> = [7, 7];
	public var iconSwingAmp:Array<Float> = [0, 0];
	public var iconRotAmp:Array<Float> = [0, 0];
	public var iconRotFreq:Array<Float> = [0, 0];
	public var iconRestOffset:Array<Float> = [0, 0];
	public var iconCurRestOffset:Array<Float> = [0, 0];
	public var iconIsSquashing:Array<Bool> = [false, false];
	public var iconIsMissed:Bool = false;	// miss 静止(玩家行为, 双 icon 同停)
	var iconBaseY1:Float = 0;
	var iconBaseY2:Float = 0;
	var iconBaseH1:Float = 0;
	var iconBaseH2:Float = 0;
	public var combo:Int = 0;

	public var healthBar:Bar;
	public var timeBar:Bar;
	var songPercent:Float = 0;

	public var ratingsData:Array<Rating> = Rating.loadDefault();

	private var generatedMusic:Bool = false;
	public var endingSong:Bool = false;
	public var startingSong:Bool = false;
	private var updateTime:Bool = true;
	public static var changedDifficulty:Bool = false;
	public static var chartingMode:Bool = false;

	//Gameplay settings
	public var healthGain:Float = 1;
	public var healthLoss:Float = 1;

	public var guitarHeroSustains:Bool = false;
	public var instakillOnMiss:Bool = false;
	public var cpuControlled:Bool = false;
	public var practiceMode:Bool = false;

	public var botplaySine:Float = 0;
	public var botplayTxt:FlxText;

	public var iconP1:HealthIcon;
	public var iconP2:HealthIcon;
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	public var cameraSpeed:Float = 1;

	public var songScore:Int = 0;
	public var songHits:Int = 0;
	public var songMisses:Int = 0;
	public var scoreTxt:FlxText;
	var timeTxt:FlxText;
	var scoreTxtTween:FlxTween;

	public static var campaignScore:Int = 0;
	public static var campaignMisses:Int = 0;
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;

	public var defaultCamZoom:Float = 1.05;

	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;
	private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	public var inCutscene:Bool = false;
	public var skipCountdown:Bool = false;
	var songLength:Float = 0;

	public var boyfriendCameraOffset:Array<Float> = null;
	public var opponentCameraOffset:Array<Float> = null;
	public var girlfriendCameraOffset:Array<Float> = null;

	#if DISCORD_ALLOWED
	// Discord RPC variables
	var storyDifficultyText:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end

	//Achievement shit
	var keysPressed:Array<Int> = [];
	var boyfriendIdleTime:Float = 0.0;
	var boyfriendIdled:Bool = false;

	// Lua shit
	public static var instance:PlayState;
	#if LUA_ALLOWED public var luaArray:Array<FunkinLua> = []; #end

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	private var luaDebugGroup:FlxTypedGroup<psychlua.DebugLuaText>;
	#end
	public var introSoundsSuffix:String = '';

	// Less laggy controls
	private var keysArray:Array<String>;
	public var songName:String;

	// Callbacks for stages
	public var startCallback:Void->Void = null;
	public var endCallback:Void->Void = null;

	override public function create()
	{
		//trace('Playback Rate: ' + playbackRate);
		Paths.clearStoredMemory();

		startCallback = startCountdown;
		endCallback = endSong;

		// for lua
		instance = this;

		PauseSubState.songName = null; //Reset to default
		playbackRate = ClientPrefs.getGameplaySetting('songspeed');

		keysArray = [
			'note_left',
			'note_down',
			'note_up',
			'note_right'
		];

		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// Gameplay settings
		healthGain = ClientPrefs.getGameplaySetting('healthgain');
		healthLoss = ClientPrefs.getGameplaySetting('healthloss');
		instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
		practiceMode = ClientPrefs.getGameplaySetting('practice');
		cpuControlled = ClientPrefs.getGameplaySetting('botplay');
		guitarHeroSustains = ClientPrefs.data.guitarHeroSustains;

		// var gameCam:FlxCamera = FlxG.camera;
		camGame = initPsychCamera();
		camHUD = new FlxCamera();
		camOther = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;

		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);
		grpNoteSplashes = new FlxTypedGroup<NoteSplash>();

		persistentUpdate = true;
		persistentDraw = true;

		if (SONG == null)
			SONG = Song.loadFromJson('tutorial');

		backend.PerfProbe.loadMark('SONG 就绪(谱面已解析)');
		Conductor.mapBPMChanges(SONG);
		Conductor.bpm = SONG.bpm;


		#if DISCORD_ALLOWED
		// String that contains the mode defined here so it isn't necessary to call changePresence for each mode
		storyDifficultyText = Difficulty.getString();

		if (isStoryMode)
			detailsText = "Story Mode: " + WeekData.getCurrentWeek().weekName;
		else
			detailsText = "Freeplay";

		// String for when the game is paused
		detailsPausedText = "Paused - " + detailsText;
		#end

		GameOverSubstate.resetVariables();
		songName = Paths.formatToSongPath(SONG.song);
		if(SONG.stage == null || SONG.stage.length < 1) {
			SONG.stage = StageData.vanillaSongStage(songName);
		}
		curStage = SONG.stage;

		var stageData:StageFile = StageData.getStageFile(curStage);
		if(stageData == null) { //Stage couldn't be found, create a dummy stage for preventing a crash
			stageData = StageData.dummy();
		}

		defaultCamZoom = stageData.defaultZoom;

		stageUI = "normal";
		if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
			stageUI = stageData.stageUI;
		else {
			if (stageData.isPixelStage)
				stageUI = "pixel";
		}

		BF_X = stageData.boyfriend[0];
		BF_Y = stageData.boyfriend[1];
		GF_X = stageData.girlfriend[0];
		GF_Y = stageData.girlfriend[1];
		DAD_X = stageData.opponent[0];
		DAD_Y = stageData.opponent[1];

		if(stageData.camera_speed != null)
			cameraSpeed = stageData.camera_speed;

		boyfriendCameraOffset = stageData.camera_boyfriend;
		if(boyfriendCameraOffset == null) //Fucks sake should have done it since the start :rolling_eyes:
			boyfriendCameraOffset = [0, 0];

		opponentCameraOffset = stageData.camera_opponent;
		if(opponentCameraOffset == null)
			opponentCameraOffset = [0, 0];

		girlfriendCameraOffset = stageData.camera_girlfriend;
		if(girlfriendCameraOffset == null)
			girlfriendCameraOffset = [0, 0];

		boyfriendGroup = new FlxSpriteGroup(BF_X, BF_Y);
		dadGroup = new FlxSpriteGroup(DAD_X, DAD_Y);
		gfGroup = new FlxSpriteGroup(GF_X, GF_Y);

		switch (curStage)
		{
			case 'stage': new states.stages.StageWeek1(); //Week 1
			case 'spooky': new states.stages.Spooky(); //Week 2
			case 'philly': new states.stages.Philly(); //Week 3
			case 'limo': new states.stages.Limo(); //Week 4
			case 'mall': new states.stages.Mall(); //Week 5 - Cocoa, Eggnog
			case 'mallEvil': new states.stages.MallEvil(); //Week 5 - Winter Horrorland
			case 'school': new states.stages.School(); //Week 6 - Senpai, Roses
			case 'schoolEvil': new states.stages.SchoolEvil(); //Week 6 - Thorns
			case 'tank': new states.stages.Tank(); //Week 7 - Ugh, Guns, Stress
		}

		if(isPixelStage) {
			introSoundsSuffix = '-pixel';
		}

		add(gfGroup);
		add(dadGroup);
		add(boyfriendGroup);

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		luaDebugGroup = new FlxTypedGroup<psychlua.DebugLuaText>();
		luaDebugGroup.cameras = [camOther];
		add(luaDebugGroup);
		#end

		// "GLOBAL" SCRIPTS
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'scripts/'))
			for (file in FileSystem.readDirectory(folder))
			{
				#if LUA_ALLOWED
				if(file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				#end

				#if HSCRIPT_ALLOWED
				if(file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
				#end
			}
		#end

		// STAGE SCRIPTS
		#if LUA_ALLOWED
		startLuasNamed('stages/' + curStage + '.lua');
		#end

		#if HSCRIPT_ALLOWED
		startHScriptsNamed('stages/' + curStage + '.hx');
		#end

		if (!stageData.hide_girlfriend)
		{
			if(SONG.gfVersion == null || SONG.gfVersion.length < 1) SONG.gfVersion = 'gf'; //Fix for the Chart Editor
			gf = new Character(0, 0, SONG.gfVersion);
			startCharacterPos(gf);
			gf.scrollFactor.set(0.95, 0.95);
			gfGroup.add(gf);
			startCharacterScripts(gf.curCharacter);
			backend.PerfProbe.loadMark('角色 gf 构造完');
		}

		dad = new Character(0, 0, SONG.player2);
		startCharacterPos(dad, true);
		dadGroup.add(dad);
		startCharacterScripts(dad.curCharacter);
		backend.PerfProbe.loadMark('角色 dad 构造完');

		boyfriend = new Character(0, 0, SONG.player1, true);
		startCharacterPos(boyfriend);
		boyfriendGroup.add(boyfriend);
		startCharacterScripts(boyfriend.curCharacter);
		backend.PerfProbe.loadMark('角色 bf 构造完');

		var camPos:FlxPoint = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
		if(gf != null)
		{
			camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
			camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
		}

		if(dad.curCharacter.startsWith('gf')) {
			dad.setPosition(GF_X, GF_Y);
			if(gf != null)
				gf.visible = false;
		}
		stagesFunc(function(stage:BaseStage) stage.createPost());

		comboGroup = new FlxSpriteGroup();
		add(comboGroup);
		noteGroup = new FlxTypedGroup<FlxBasic>();
		add(noteGroup);
		uiGroup = new FlxSpriteGroup();
		add(uiGroup);

		Conductor.songPosition = -5000 / Conductor.songPosition;
		var showTime:Bool = (ClientPrefs.data.timeBarType != 'Disabled');
		timeTxt = new FlxText(STRUM_X + (FlxG.width / 2) - 248, 19, 400, "", 32);
		timeTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		timeTxt.scrollFactor.set();
		timeTxt.alpha = 0;
		timeTxt.borderSize = 2;
		timeTxt.visible = updateTime = showTime;
		if(ClientPrefs.data.downScroll) timeTxt.y = FlxG.height - 44;
		if(ClientPrefs.data.timeBarType == 'Song Name') timeTxt.text = SONG.song;

		timeBar = new Bar(0, timeTxt.y + (timeTxt.height / 4), 'timeBar', function() return songPercent, 0, 1);
		timeBar.scrollFactor.set();
		timeBar.screenCenter(X);
		timeBar.alpha = 0;
		timeBar.visible = showTime;
		uiGroup.add(timeBar);
		uiGroup.add(timeTxt);

		strumLineNotes = new FlxTypedGroup<StrumNote>();
		noteGroup.add(strumLineNotes);

		if(ClientPrefs.data.timeBarType == 'Song Name')
		{
			timeTxt.size = 24;
			timeTxt.y += 3;
		}

		var splash:NoteSplash = new NoteSplash(100, 100);
		grpNoteSplashes.add(splash);
		splash.alpha = 0.000001; //cant make it invisible or it won't allow precaching

		opponentStrums = new FlxTypedGroup<StrumNote>();
		playerStrums = new FlxTypedGroup<StrumNote>();

		generateSong(SONG.song);

		noteGroup.add(grpNoteSplashes);

		camFollow = new FlxObject(0, 0, 1, 1);
		camFollow.setPosition(camPos.x, camPos.y);
		camPos.put();

		if (prevCamFollow != null)
		{
			camFollow = prevCamFollow;
			prevCamFollow = null;
		}
		add(camFollow);

		FlxG.camera.follow(camFollow, LOCKON, 0);
		FlxG.camera.zoom = defaultCamZoom;
		FlxG.camera.snapToTarget();

		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
		moveCameraSection();

		healthBar = new Bar(0, FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11), 'healthBar', function() return health, 0, 2);
		healthBar.screenCenter(X);
		healthBar.leftToRight = false;
		healthBar.scrollFactor.set();
		healthBar.visible = !ClientPrefs.data.hideHud;
		healthBar.alpha = ClientPrefs.data.healthBarAlpha;
		reloadHealthBarColors();
		uiGroup.add(healthBar);

		// 平滑血条: Bar.percent 由 valueFunction 驱动(Bar 内部已 bound 0-2), 显示缓动而判定/死亡用真实值
		if (ClientPrefs.data.gameplaySettings.get('smoothhealth') != false)
		{
			healthBar.valueFunction = function() return smoothHealth;
			smoothHealthOn = true;
		}

		iconP1 = new HealthIcon(boyfriend.healthIcon, true);
		iconP1.y = healthBar.y - 75;
		iconP1.visible = !ClientPrefs.data.hideHud;
		iconP1.alpha = ClientPrefs.data.healthBarAlpha;
		uiGroup.add(iconP1);

		iconP2 = new HealthIcon(dad.healthIcon, false);
		iconP2.y = healthBar.y - 75;
		iconP2.visible = !ClientPrefs.data.hideHud;
		iconP2.alpha = ClientPrefs.data.healthBarAlpha;
		uiGroup.add(iconP2);

		// A7: 文本画布 1280→760 并用 OUTLINE_FAST —— 每次重绘从"整宽 9 遍光栅化"降到"约 4 遍小画布"
		scoreTxt = new FlxText(0, healthBar.y + 40, 760, "", 20);
		scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE_FAST, FlxColor.BLACK);
		scoreTxt.scrollFactor.set();
		scoreTxt.screenCenter(X);
		scoreTxt.borderSize = 1.25;
		scoreTxt.visible = !ClientPrefs.data.hideHud;
		updateScore(false);
		uiGroup.add(scoreTxt);

		botplayTxt = new FlxText(400, timeBar.y + 55, FlxG.width - 800, "猫娘替你打喵", 32);
		botplayTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		botplayTxt.scrollFactor.set();
		botplayTxt.borderSize = 1.25;
		botplayTxt.visible = cpuControlled;
		uiGroup.add(botplayTxt);
		if(ClientPrefs.data.downScroll)
			botplayTxt.y = timeBar.y - 78;

		uiGroup.cameras = [camHUD];
		noteGroup.cameras = [camHUD];
		comboGroup.cameras = [camHUD];
		backend.PerfProbe.loadMark('HUD 骨架完');

		startingSong = true;
		
		#if mobile
		var canCreatePause:Bool = true;
	
		#if !ios
		canCreatePause = !ClientPrefs.data.invisibleButtonPause;
		#end
	
		if (canCreatePause)
		{
			var pauseButton = new mobile.backend.PauseButton(0, 0, function()
			{
				var ret:Dynamic = callOnScripts('onPause', null, true);
				if(ret != LuaUtils.Function_Stop) {
					openPauseMenu();
				}
			});
			add(pauseButton);
		}
		
		addMobileControls(false, camOther);	// 复用恒等相机, 省一张全屏画布
		hitbox.visible = false;
		#end

		// ===== 窗口化兼容(旧式 mod 脚本): 带音符类型/事件脚本的谱面按原版全量实例化 =====
		// 旧式脚本在 onCreate 里遍历 unspawnNotes(原版为全量), 窗口化下 create 阶段为空数组,
		// 属性设置全部落空(表现为特殊箭头/事件 lua 失效)。检测到本谱存在此类脚本且谱面行数
		// 在阈值内时, 在脚本加载前一次性全量实例化, 完整复现旧版语义; 无脚本谱面仍走窗口化省内存。
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		if (generatedMusic && chartTimes.length > 0 && chartTimes.length <= 4000)
		{
			var legacyFill:Bool = false;
			#if MODS_ALLOWED
			for (nt in noteTypes)
				if (noteScriptExists('custom_notetypes/' + nt + '.lua') || noteScriptExists('custom_notetypes/' + nt + '.hx'))
				{
					legacyFill = true;
					break;
				}
			if (!legacyFill)
				for (ev in eventsPushed)
					if (noteScriptExists('custom_events/' + ev + '.lua') || noteScriptExists('custom_events/' + ev + '.hx'))
					{
						legacyFill = true;
						break;
					}
			#end
			if (legacyFill)
			{
				while (chartIdx < chartTimes.length)
				{
					makeChartNote(chartIdx);
					chartIdx++;
				}
				unspawnNotes.sort(sortByTime);
			}
		}
		#end
		backend.PerfProbe.loadMark('谱面实例化完(兼容路径按需)');

		#if LUA_ALLOWED
		for (notetype in noteTypes)
			startLuasNamed('custom_notetypes/' + notetype + '.lua');
		for (event in eventsPushed)
			startLuasNamed('custom_events/' + event + '.lua');
		#end

		#if HSCRIPT_ALLOWED
		for (notetype in noteTypes)
			startHScriptsNamed('custom_notetypes/' + notetype + '.hx');
		for (event in eventsPushed)
			startHScriptsNamed('custom_events/' + event + '.hx');
		#end
		noteTypes = null;
		eventsPushed = null;

		if(eventNotes.length > 1)
		{
			for (event in eventNotes) event.strumTime -= eventEarlyTrigger(event);
			eventNotes.sort(sortByTime);
		}

		// SONG SPECIFIC SCRIPTS
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'data/$songName/'))
			for (file in FileSystem.readDirectory(folder))
			{
				#if LUA_ALLOWED
				if(file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				#end

				#if HSCRIPT_ALLOWED
				if(file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
				#end
			}
		#end
		backend.PerfProbe.loadMark('lua 脚本加载完');

		// lua 音效扫描预载: 收集脚本字面量音效键, 后台线程预解码(防打歌中动态解码 1-4s 主线程停顿)
		#if MODS_ALLOWED
		var scanPaths:Array<String> = [];
		for (scanLua in luaArray)
			scanPaths.push(scanLua.scriptName);
		backend.LuaSoundScan.reset();
		backend.LuaSoundScan.start(scanPaths);
		#end

		startCallback();
		RecalculateRating();

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		//PRECACHING THINGS THAT GET USED FREQUENTLY TO AVOID LAGSPIKES
		if(ClientPrefs.data.hitsoundVolume > 0) Paths.sound('hitsound');
		for (i in 1...4) Paths.sound('missnote$i');
		Paths.image('alphabet');

		// 音符溅射图集: 首次击中才加载实测卡 167ms(尖帧 209ms), 提前在加载阶段消化
		// 取法与 NoteSplash.setupNoteSplash 保持一致(自定义 splashSkin 优先, 否则默认皮肤+像素后缀)
		var splashSkin:String = (SONG.splashSkin != null && SONG.splashSkin.length > 0) ? SONG.splashSkin : (NoteSplash.defaultNoteSplash + NoteSplash.getSplashSkinPostfix());
		Paths.getSparrowAtlas(splashSkin);

		if (PauseSubState.songName != null)
			Paths.music(PauseSubState.songName);
		else if(Paths.formatToSongPath(ClientPrefs.data.pauseMusic) != 'none')
			Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic));

		// 退出打歌要放的菜单曲: 不预载实测卡 265ms(尖帧 303ms)
		if (Paths.formatToSongPath(ClientPrefs.data.pauseMusic) != 'freakymenu')
			Paths.music('freakyMenu');

		resetRPC();

		callOnScripts('onCreatePost');

		cacheCountdown();
		cachePopUpScore();
		backend.PerfProbe.loadMark('预载完(音效/字母/暂停曲)');

		super.create();
		Paths.clearUnusedMemory();
		#if cpp
		// 进歌前把 create 阶段产生的临时垃圾清掉: 实测打歌开始 ~2s 时会来一次 422ms 的全量 GC
		// (perf_log: 40.5s GC -142.8MB 帧耗时=422ms), 正好卡在歌曲开头最要命的位置。
		// 这里在倒计时/开唱前主动收一次, 把这 400ms 放进加载阶段(此时本来就在黑屏过渡)。
		openfl.system.System.gc();
		#end
		backend.PerfProbe.loadMark('create 完成(含贴图缓存)');

		if(eventNotes.length < 1) checkEventNote();
	}

	function set_songSpeed(value:Float):Float
	{
		if(generatedMusic)
		{
			var ratio:Float = value / songSpeed; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		songSpeed = value;
		noteKillOffset = Math.max(Conductor.stepCrochet, 350 / songSpeed * playbackRate);
		return value;
	}

	function set_playbackRate(value:Float):Float
	{
		#if FLX_PITCH
		if(generatedMusic)
		{
			vocals.pitch = value;
			opponentVocals.pitch = value;
			FlxG.sound.music.pitch = value;

			var ratio:Float = playbackRate / value; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		playbackRate = value;
		FlxG.animationTimeScale = value;
		Conductor.safeZoneOffset = (ClientPrefs.data.safeFrames / 60) * 1000 * value;
		setOnScripts('playbackRate', playbackRate);
		#else
		playbackRate = 1.0; // ensuring -Crow
		#end
		return playbackRate;
	}

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	public function addTextToDebug(text:String, color:FlxColor) {
		var newText:psychlua.DebugLuaText = luaDebugGroup.recycle(psychlua.DebugLuaText);
		newText.text = text;
		newText.color = color;
		newText.disableTime = 6;
		newText.alpha = 1;
		newText.setPosition(10, 8 - newText.height);

		luaDebugGroup.forEachAlive(function(spr:psychlua.DebugLuaText) {
			spr.y += newText.height + 2;
		});
		luaDebugGroup.add(newText);

		Sys.println(text);
	}
	#end

	public function reloadHealthBarColors() {
		healthBar.setColors(FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]),
			FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]));
	}

	public function addCharacterToList(newCharacter:String, type:Int) {
		switch(type) {
			case 0:
				if(!boyfriendMap.exists(newCharacter)) {
					var newBoyfriend:Character = new Character(0, 0, newCharacter, true);
					boyfriendMap.set(newCharacter, newBoyfriend);
					boyfriendGroup.add(newBoyfriend);
					startCharacterPos(newBoyfriend);
					newBoyfriend.alpha = 0.00001;
					startCharacterScripts(newBoyfriend.curCharacter);
				}

			case 1:
				if(!dadMap.exists(newCharacter)) {
					var newDad:Character = new Character(0, 0, newCharacter);
					dadMap.set(newCharacter, newDad);
					dadGroup.add(newDad);
					startCharacterPos(newDad, true);
					newDad.alpha = 0.00001;
					startCharacterScripts(newDad.curCharacter);
				}

			case 2:
				if(gf != null && !gfMap.exists(newCharacter)) {
					var newGf:Character = new Character(0, 0, newCharacter);
					newGf.scrollFactor.set(0.95, 0.95);
					gfMap.set(newCharacter, newGf);
					gfGroup.add(newGf);
					startCharacterPos(newGf);
					newGf.alpha = 0.00001;
					startCharacterScripts(newGf.curCharacter);
				}
		}
	}

	function startCharacterScripts(name:String)
	{
		// Lua
		#if LUA_ALLOWED
		var doPush:Bool = false;
		var luaFile:String = 'characters/$name.lua';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(luaFile);
		if(FileSystem.exists(replacePath))
		{
			luaFile = replacePath;
			doPush = true;
		}
		else
		{
			luaFile = Paths.getSharedPath(luaFile);
			if(FileSystem.exists(luaFile))
				doPush = true;
		}
		#else
		luaFile = Paths.getSharedPath(luaFile);
		if(Assets.exists(luaFile)) doPush = true;
		#end

		if(doPush)
		{
			for (script in luaArray)
			{
				if(script.scriptName == luaFile)
				{
					doPush = false;
					break;
				}
			}
			if(doPush) new FunkinLua(luaFile);
		}
		#end

		// HScript
		#if HSCRIPT_ALLOWED
		var doPush:Bool = false;
		var scriptFile:String = 'characters/' + name + '.hx';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(scriptFile);
		if(FileSystem.exists(replacePath))
		{
			scriptFile = replacePath;
			doPush = true;
		}
		else
		#end
		{
			scriptFile = Paths.getSharedPath(scriptFile);
			if(FileSystem.exists(scriptFile))
				doPush = true;
		}

		if(doPush)
		{
			if(SScript.global.exists(scriptFile))
				doPush = false;

			if(doPush) initHScript(scriptFile);
		}
		#end
	}

	public function getLuaObject(tag:String, text:Bool=true):FlxSprite {
		#if LUA_ALLOWED
		if(modchartSprites.exists(tag)) return modchartSprites.get(tag);
		if(text && modchartTexts.exists(tag)) return modchartTexts.get(tag);
		if(variables.exists(tag)) return variables.get(tag);
		#end
		return null;
	}

	function startCharacterPos(char:Character, ?gfCheck:Bool = false) {
		if(gfCheck && char.curCharacter.startsWith('gf')) { //IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(GF_X, GF_Y);
			char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0];
		char.y += char.positionArray[1];
	}

	public function startVideo(name:String)
	{
		#if VIDEOS_ALLOWED
		inCutscene = true;

		var filepath:String = Paths.video(name);
		#if sys
		if(!FileSystem.exists(filepath))
		#else
		if(!OpenFlAssets.exists(filepath))
		#end
		{
			FlxG.log.warn('Couldnt find video file: ' + name);
			startAndEnd();
			return;
		}

		var video:VideoHandler = new VideoHandler();
			#if (hxCodec >= "3.0.0")
			// Recent versions
			video.play(filepath);
			video.onEndReached.add(function()
			{
				video.dispose();
				startAndEnd();
				return;
			}, true);
			#else
			// Older versions
			video.playVideo(filepath);
			video.finishCallback = function()
			{
				startAndEnd();
				return;
			}
			#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		return;
		#end
	}

	function startAndEnd()
	{
		if(endingSong)
			endSong();
		else
			startCountdown();
	}

	var dialogueCount:Int = 0;
	public var psychDialogue:DialogueBoxPsych;
	//You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
	public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void
	{
		// TO DO: Make this more flexible, maybe?
		if(psychDialogue != null) return;

		if(dialogueFile.dialogue.length > 0) {
			inCutscene = true;
			psychDialogue = new DialogueBoxPsych(dialogueFile, song);
			psychDialogue.scrollFactor.set();
			if(endingSong) {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					endSong();
				}
			} else {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					startCountdown();
				}
			}
			psychDialogue.nextDialogueThing = startNextDialogue;
			psychDialogue.skipDialogueThing = skipDialogue;
			psychDialogue.cameras = [camHUD];
			add(psychDialogue);
		} else {
			FlxG.log.warn('Your dialogue file is badly formatted!');
			startAndEnd();
		}
	}

	var startTimer:FlxTimer;
	var finishTimer:FlxTimer = null;

	// For being able to mess with the sprites on Lua
	public var countdownReady:FlxSprite;
	public var countdownSet:FlxSprite;
	public var countdownGo:FlxSprite;
	public static var startOnTime:Float = 0;

	function cacheCountdown()
	{
		var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
		var introImagesArray:Array<String> = switch(stageUI) {
			case "pixel": ['${stageUI}UI/ready-pixel', '${stageUI}UI/set-pixel', '${stageUI}UI/date-pixel'];
			case "normal": ["ready", "set" ,"go"];
			default: ['${stageUI}UI/ready', '${stageUI}UI/set', '${stageUI}UI/go'];
		}
		introAssets.set(stageUI, introImagesArray);
		var introAlts:Array<String> = introAssets.get(stageUI);
		for (asset in introAlts) Paths.image(asset);

		Paths.sound('intro3' + introSoundsSuffix);
		Paths.sound('intro2' + introSoundsSuffix);
		Paths.sound('intro1' + introSoundsSuffix);
		Paths.sound('introGo' + introSoundsSuffix);
	}

	public function startCountdown()
	{
	    #if mobile
		hitbox.visible = true;
		#end
		if(startedCountdown) {
			callOnScripts('onStartCountdown');
			return false;
		}

		seenCutscene = true;
		inCutscene = false;
		var ret:Dynamic = callOnScripts('onStartCountdown', null, true);
		if(ret != LuaUtils.Function_Stop) {
			if (skipCountdown || startOnTime > 0) skipArrowStartTween = true;

			generateStaticArrows(0);
			generateStaticArrows(1);
			for (i in 0...playerStrums.length) {
				setOnScripts('defaultPlayerStrumX' + i, playerStrums.members[i].x);
				setOnScripts('defaultPlayerStrumY' + i, playerStrums.members[i].y);
			}
			for (i in 0...opponentStrums.length) {
				setOnScripts('defaultOpponentStrumX' + i, opponentStrums.members[i].x);
				setOnScripts('defaultOpponentStrumY' + i, opponentStrums.members[i].y);
				//if(ClientPrefs.data.middleScroll) opponentStrums.members[i].visible = false;
			}

			startedCountdown = true;
			Conductor.songPosition = -Conductor.crochet * 5;
			setOnScripts('startedCountdown', true);
			callOnScripts('onCountdownStarted', null);

			var swagCounter:Int = 0;
			if (startOnTime > 0) {
				clearNotesBefore(startOnTime);
				setSongTime(startOnTime - 350);
				return true;
			}
			else if (skipCountdown)
			{
				setSongTime(0);
				return true;
			}
			moveCameraSection();

			startTimer = new FlxTimer().start(Conductor.crochet / 1000 / playbackRate, function(tmr:FlxTimer)
			{
				characterBopper(tmr.loopsLeft);

				var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
				var introImagesArray:Array<String> = switch(stageUI) {
					case "pixel": ['${stageUI}UI/ready-pixel', '${stageUI}UI/set-pixel', '${stageUI}UI/date-pixel'];
					case "normal": ["ready", "set" ,"go"];
					default: ['${stageUI}UI/ready', '${stageUI}UI/set', '${stageUI}UI/go'];
				}
				introAssets.set(stageUI, introImagesArray);

				var introAlts:Array<String> = introAssets.get(stageUI);
				var antialias:Bool = (ClientPrefs.data.antialiasing && !isPixelStage);
				var tick:Countdown = THREE;

				switch (swagCounter)
				{
					case 0:
						FlxG.sound.play(Paths.sound('intro3' + introSoundsSuffix), 0.6);
						tick = THREE;
					case 1:
						countdownReady = createCountdownSprite(introAlts[0], antialias);
						FlxG.sound.play(Paths.sound('intro2' + introSoundsSuffix), 0.6);
						tick = TWO;
					case 2:
						countdownSet = createCountdownSprite(introAlts[1], antialias);
						FlxG.sound.play(Paths.sound('intro1' + introSoundsSuffix), 0.6);
						tick = ONE;
					case 3:
						countdownGo = createCountdownSprite(introAlts[2], antialias);
						FlxG.sound.play(Paths.sound('introGo' + introSoundsSuffix), 0.6);
						tick = GO;
					case 4:
						tick = START;
				}

				notes.forEachAlive(function(note:Note) {
					if(ClientPrefs.data.opponentStrums || note.mustPress)
					{
						note.copyAlpha = false;
						note.alpha = note.multAlpha;
						if(ClientPrefs.data.middleScroll && !note.mustPress)
							note.alpha *= 0.35;
					}
				});

				stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, swagCounter));
				callOnLuas('onCountdownTick', [swagCounter]);
				callOnHScript('onCountdownTick', [tick, swagCounter]);

				swagCounter += 1;
			}, 5);
		}
		return true;
	}

	inline private function createCountdownSprite(image:String, antialias:Bool):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(image));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));

		spr.screenCenter();
		spr.antialiasing = antialias;
		insert(members.indexOf(noteGroup), spr);
		FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(twn:FlxTween)
			{
				remove(spr);
				spr.destroy();
			}
		});
		return spr;
	}

	public function addBehindGF(obj:FlxBasic)
	{
		insert(members.indexOf(gfGroup), obj);
	}
	public function addBehindBF(obj:FlxBasic)
	{
		insert(members.indexOf(boyfriendGroup), obj);
	}
	public function addBehindDad(obj:FlxBasic)
	{
		insert(members.indexOf(dadGroup), obj);
	}

	public function clearNotesBefore(time:Float)
	{
		// 数据层同步: 跳过窗口之前尚未实例化的行(它们不再需要生成)
		while (chartIdx < chartTimes.length && chartTimes[chartIdx] - 350 < time)
			chartIdx++;

		var i:Int = unspawnNotes.length - 1;
		while (i >= 0) {
			var daNote:Note = unspawnNotes[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;

				daNote.kill();
				unspawnNotes.remove(daNote);
				daNote.recycle();	// C1: 跳过的时间段音符也回收进池
			}
			--i;
		}

		i = notes.length - 1;
		while (i >= 0) {
			var daNote:Note = notes.members[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;
				invalidateNote(daNote);
			}
			--i;
		}
	}

	// fun fact: Dynamic Functions can be overriden by just doing this
	// `updateScore = function(miss:Bool = false) { ... }
	// its like if it was a variable but its just a function!
	// cool right? -Crow

	// ===== A7: 评分文本限频渲染 =====
	// 每次命中都直接写 scoreTxt.text 会触发 FlxText 全画布重光栅化+纹理上传(约 4 遍描边)。
	// 这里把"拼字符串"留在命中时, "写文本"挪到 update 里限频(80ms), 连打段不再逐 hit 重绘。
	var scoreTxtPending:String = '';
	var scoreTxtDirty:Bool = false;
	var scoreTxtCooldown:Float = 0;
	// B9: 时间文本按秒缓存 —— 秒数没变就不重拼 formatTime
	var lastTimeSec:Int = -9999;

	// ===== B: 每帧脚本同步的变更检测 =====
	// 原本每帧固定 7 轮跨脚本边界写入(5×setOnScripts + 2×callOnScripts), 每轮都遍历全部脚本;
	// 其中 botPlay 整首不变、cameraX/Y 在镜头静止时不变化, 白跑。
	var syncedDecStep:Float = Math.NEGATIVE_INFINITY;
	var syncedDecBeat:Float = Math.NEGATIVE_INFINITY;
	var syncedCamX:Float = Math.NEGATIVE_INFINITY;
	var syncedCamY:Float = Math.NEGATIVE_INFINITY;
	var syncedBotPlay:Bool = false;
	var scriptArgs:Array<Dynamic> = [0.0];	// 复用参数数组(免每帧两次小数组分配)

	public dynamic function updateScore(miss:Bool = false)
	{
		var ret:Dynamic = callOnScripts('preUpdateScore', [miss], true);
		if (ret == LuaUtils.Function_Stop)
			return;

		var str:String = ratingName;
		if(totalPlayed != 0)
		{
			var percent:Float = CoolUtil.floorDecimal(ratingPercent * 100, 2);
			str += ' (${percent}%) - ${ratingFC}';
		}

		var tempScore:String = '得分: ${songScore}'
		+ (!instakillOnMiss ? ' | 失误: ${songMisses}' : "")
		+ ' | 评价: ${str}';
		// "tempScore" variable is used to prevent another memory leak, just in case
		// "\n" here prevents the text from being cut off by beat zooms
		// A7: 先挂起, 由 update() 限频落盘(见 flushScoreText)
		scoreTxtPending = '${tempScore}\n';
		scoreTxtDirty = true;

		if (!miss && !cpuControlled)
			doScoreBop();

		callOnScripts('onUpdateScore', [miss]);
	}

	// A7: 由 update() 每帧调用, 限频把挂起的评分文本写出去
	function flushScoreText(elapsed:Float):Void
	{
		if (!scoreTxtDirty) return;
		scoreTxtCooldown -= elapsed;
		if (scoreTxtCooldown > 0) return;
		scoreTxtCooldown = 0.08;
		scoreTxtDirty = false;
		scoreTxt.text = scoreTxtPending;
	}

	public dynamic function fullComboFunction()
	{
		var sicks:Int = ratingsData[0].hits;
		var goods:Int = ratingsData[1].hits;
		var bads:Int = ratingsData[2].hits;
		var shits:Int = ratingsData[3].hits;

		ratingFC = "";
		if(songMisses == 0)
		{
			if (bads > 0 || shits > 0) ratingFC = 'FC';
			else if (goods > 0) ratingFC = 'GFC';
			else if (sicks > 0) ratingFC = 'SFC';
		}
		else {
			if (songMisses < 10) ratingFC = 'SDCB';
			else ratingFC = 'Clear';
		}
	}

	public function doScoreBop():Void {
		if(!ClientPrefs.data.scoreZoom)
			return;

		if(scoreTxtTween != null)
			scoreTxtTween.cancel();

		scoreTxt.scale.x = 1.075;
		scoreTxt.scale.y = 1.075;
		scoreTxtTween = FlxTween.tween(scoreTxt.scale, {x: 1, y: 1}, 0.2, {
			onComplete: function(twn:FlxTween) {
				scoreTxtTween = null;
			}
		});
	}

	public function setSongTime(time:Float)
	{
		if(time < 0) time = 0;

		FlxG.sound.music.pause();
		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.time = time;
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.play();

		if (Conductor.songPosition <= vocals.length)
		{
			vocals.time = time;
			opponentVocals.time = time;
			#if FLX_PITCH
			vocals.pitch = playbackRate;
			opponentVocals.pitch = playbackRate;
			#end
		}
		vocals.play();
		opponentVocals.play();
		Conductor.songPosition = time;
	}

	public function startNextDialogue() {
		dialogueCount++;
		callOnScripts('onNextDialogue', [dialogueCount]);
	}

	public function skipDialogue() {
		callOnScripts('onSkipDialogue', [dialogueCount]);
	}

	function startSong():Void
	{
		startingSong = false;

		var tPlayStart:Float = haxe.Timer.stamp();
		@:privateAccess
		FlxG.sound.playMusic(inst._sound, 1, false);
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.onComplete = finishSong.bind();
		vocals.play();
		opponentVocals.play();
		var alignWallMs:Float = (haxe.Timer.stamp() - tPlayStart) * 1000;

		// A: 三条音轨是"依次" play() 的, 启动有先后差(本机实测 vocals 恒定落后 inst ~46ms)。
		// 不纠正的话整首人声慢半拍: 听感偏 + 玩家跟着人声打会整体偏晚(实测判定均差 -21ms)。
		// 起播后立刻按伴奏的真实位置对齐一次(此时人声源刚起, 不会听到跳变)。
		// 后端可能来不及报 position(读到 0), 那就用实测的启动耗时兜底。
		var alignTo:Float = FlxG.sound.music.time;
		if (alignTo <= 0) alignTo = alignWallMs;
		if (alignTo > 200) alignTo = 0;	// 异常值保护
		if (vocals.length > 0) vocals.time = alignTo;
		if (opponentVocals.length > 0) opponentVocals.time = alignTo;
		#if mobile
		backend.PerfProbe.log('[音画] 起播对齐 music=' + Math.round(alignTo)
			+ ' 实测启动差=' + Math.round(alignWallMs) + 'ms'
			+ ' vocals=' + Math.round(vocals.time) + ' opp=' + Math.round(opponentVocals.time));
		#end

		if(startOnTime > 0) setSongTime(startOnTime - 500);
		startOnTime = 0;

		if(paused) {
			//trace('Oopsie doopsie! Paused sound');
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		// Song duration in a float, useful for the time left feature
		songLength = FlxG.sound.music.length;
		FlxTween.tween(timeBar, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
		FlxTween.tween(timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence (with Time Left)
		if(autoUpdateRPC) DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength);
		#end
		setOnScripts('songLength', songLength);
		callOnScripts('onSongStart');
	}

	var debugNum:Int = 0;
	private var noteTypes:Array<String> = [];
	private var eventsPushed:Array<String> = [];
	private function generateSong(dataPath:String):Void
	{
		// 进歌起点: 停掉后台预载线程, 音频解码由主线程独占(避免 IO/CPU 竞争拖慢加载)
		backend.AudioPreload.cancel();
		backend.PerfProbe.loadMark('generateSong 开始');
		// FlxG.log.add(ChartParser.parse());
		songSpeed = PlayState.SONG.speed;
		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch(songSpeedType)
		{
			case "multiplicative":
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}

		var songData = SONG;
		Conductor.bpm = songData.bpm;

		curSong = songData.song;

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
		// ===== B1 并行解码: 主线程只解 Inst, vocals 走后台线程纯解码 =====
		// Sound.fromFile 后台线程安全(#94 验证; 教训10: 不碰 Paths 全局缓存即可); 后台解不出的(嵌入资产)回退主线程原路径
		var bgMutex:sys.thread.Mutex = new sys.thread.Mutex();
		var bgDone:Bool = true;
		var bgStarted:Bool = false;
		var bgPlayer:openfl.media.Sound = null;
		var bgPlain:openfl.media.Sound = null;
		var bgOpp:openfl.media.Sound = null;
		if (songData.needsVoices)
		{
			var songKeyB1:String = Paths.formatToSongPath(songData.song);
			var playerPostfix:String = (boyfriend.vocalsFile == null || boyfriend.vocalsFile.length < 1) ? 'Player' : boyfriend.vocalsFile;
			var oppPostfix:String = (dad.vocalsFile == null || dad.vocalsFile.length < 1) ? 'Opponent' : dad.vocalsFile;
			var bgFiles:Array<String> = [];
			var bgRoles:Array<Int> = [];	// 0=玩家声 1=无后缀兜底 2=对手声
			var fP:String = Paths.songSoundFile(songKeyB1 + '/Voices-' + playerPostfix);
			if (fP != null) { bgFiles.push(fP); bgRoles.push(0); }
			else
			{
				var fPlain:String = Paths.songSoundFile(songKeyB1 + '/Voices');
				if (fPlain != null) { bgFiles.push(fPlain); bgRoles.push(1); }
			}
			var fO:String = Paths.songSoundFile(songKeyB1 + '/Voices-' + oppPostfix);
			if (fO != null) { bgFiles.push(fO); bgRoles.push(2); }

			if (bgFiles.length > 0)
			{
				bgStarted = true;
				bgDone = false;
				sys.thread.Thread.create(function() {
					for (i in 0...bgFiles.length)
					{
						var s:openfl.media.Sound = null;
						try { s = openfl.media.Sound.fromFile(bgFiles[i]); }
						catch (eBg:Dynamic) { s = null; }
						bgMutex.acquire();
						switch (bgRoles[i]) { case 0: bgPlayer = s; case 1: bgPlain = s; default: bgOpp = s; }
						bgMutex.release();
					}
					bgMutex.acquire();
					bgDone = true;
					bgMutex.release();
				});
			}
		}

		// 主线程解 Inst —— 与后台 vocals 解码并行
		inst = new FlxSound();
		try {
			inst.loadEmbedded(Paths.inst(songData.song));
		}
		catch(e:Dynamic) {}

		// 等 vocals 后台解码完再挂载(通常此刻已就绪); 槽位为空回退主线程 Paths.voices(嵌入资产/解析分歧)
		try
		{
			if (songData.needsVoices)
			{
				if (bgStarted)
				{
					while (true)
					{
						bgMutex.acquire();
						var d:Bool = bgDone;
						bgMutex.release();
						if (d) break;
						Sys.sleep(0.002);
					}
					bgMutex.acquire();
					var pv:openfl.media.Sound = bgPlayer != null ? bgPlayer : bgPlain;
					var ov:openfl.media.Sound = bgOpp;
					bgMutex.release();
					if (pv == null) pv = Paths.voices(songData.song, (boyfriend.vocalsFile == null || boyfriend.vocalsFile.length < 1) ? 'Player' : boyfriend.vocalsFile);
					vocals.loadEmbedded(pv != null ? pv : Paths.voices(songData.song));
					if (ov == null) ov = Paths.voices(songData.song, (dad.vocalsFile == null || dad.vocalsFile.length < 1) ? 'Opponent' : dad.vocalsFile);
					if (ov != null) opponentVocals.loadEmbedded(ov);
				}
				else
				{
					// 后台没活干(嵌入资产歌曲): 主线程原路径
					var playerVocals = Paths.voices(songData.song, (boyfriend.vocalsFile == null || boyfriend.vocalsFile.length < 1) ? 'Player' : boyfriend.vocalsFile);
					vocals.loadEmbedded(playerVocals != null ? playerVocals : Paths.voices(songData.song));
					var oppVocals = Paths.voices(songData.song, (dad.vocalsFile == null || dad.vocalsFile.length < 1) ? 'Opponent' : dad.vocalsFile);
					if(oppVocals != null) opponentVocals.loadEmbedded(oppVocals);
				}
			}
		}
		catch(e:Dynamic) {}

		#if FLX_PITCH
		vocals.pitch = playbackRate;
		opponentVocals.pitch = playbackRate;
		#end
		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);

		FlxG.sound.list.add(inst);
		backend.PerfProbe.loadMark('inst/voices 解码完');

		notes = new FlxTypedGroup<Note>();
		noteGroup.add(notes);

		var noteData:Array<SwagSection>;

		// NEW SHIT
		noteData = songData.notes;

		var file:String = Paths.json(songName + '/events');
		#if MODS_ALLOWED
		if (FileSystem.exists(Paths.modsJson(songName + '/events')) || FileSystem.exists(file))
		#else
		if (OpenFlAssets.exists(file))
		#end
		{
			var eventsData:Array<Dynamic> = Song.loadFromJson('events', songName).events;
			for (event in eventsData) //Event Notes
				for (i in 0...event[1].length)
					makeEvent(event, i);
		}
		backend.PerfProbe.loadMark('事件加载完');

		// ===== 窗口化谱面: 数据层平铺(不实例化 Note), 按时间排序后滚动生成 =====
		chartStepCrochet = Conductor.stepCrochet;	// 构建期快照(原版全量生成时即此值)
		for (section in noteData)
		{
			for (songNotes in section.sectionNotes)
			{
				var daStrumTime:Float = songNotes[0];
				var daNoteData:Int = Std.int(songNotes[1] % 4);
				var gottaHitNote:Bool = section.mustHitSection;
				if (songNotes[1] > 3) gottaHitNote = !section.mustHitSection;

				chartTimes.push(daStrumTime);
				chartDataI.push(daNoteData);
				chartPress.push(gottaHitNote);
				chartSus.push(songNotes[2]);
				chartGf.push(section.gfSection && (songNotes[1] < 4));
				var nt:Dynamic = songNotes[3];
				if (!Std.isOfType(nt, String)) nt = ChartingState.noteTypeList[nt]; //Backward compatibility + compatibility with Week 7 charts
				chartType.push(nt);
				if (!noteTypes.contains(nt)) noteTypes.push(nt);
			}
		}
		backend.PerfProbe.loadMark('谱面平铺完');
		{
			var n:Int = chartTimes.length;
			var order:Array<Int> = new Array<Int>();
			for (i in 0...n) order.push(i);
			order.sort(function(a:Int, b:Int):Int {
				var ta:Float = chartTimes[a]; var tb:Float = chartTimes[b];
				return ta < tb ? -1 : (ta > tb ? 1 : 0);
			});
			var t2:Array<Float> = []; var d2:Array<Int> = []; var p2:Array<Bool> = [];
			var s2:Array<Float> = []; var g2:Array<Bool> = []; var ty2:Array<Dynamic> = [];
			for (i in 0...n) {
				var k:Int = order[i];
				t2.push(chartTimes[k]); d2.push(chartDataI[k]); p2.push(chartPress[k]);
				s2.push(chartSus[k]); g2.push(chartGf[k]); ty2.push(chartType[k]);
			}
			chartTimes = t2; chartDataI = d2; chartPress = p2;
			chartSus = s2; chartGf = g2; chartType = ty2;
		}
		backend.PerfProbe.log('[谱面] 数据行=' + chartTimes.length + ' 窗口化生成开启');
		backend.PerfProbe.loadMark('谱面数据构建完');
		for (event in songData.events) //Event Notes
			for (i in 0...event[1].length)
				makeEvent(event, i);

		generatedMusic = true;
	}

	// 窗口化生成: 把数据行实例化为 Note(含 sustain 链) —— 逻辑=原全量构建的逐行版本
	function makeChartNote(idx:Int):Void
	{
		var daStrumTime:Float = chartTimes[idx];
		var daNoteData:Int = chartDataI[idx];
		var gottaHitNote:Bool = chartPress[idx];

		var oldNote:Note = null;
		if (unspawnNotes.length > 0)
			oldNote = unspawnNotes[unspawnNotes.length - 1];

		// C1: 从对象池取音符(池空时才 new), 避免每音符构造/销毁的 GC 抖动
		var swagNote:Note = Note.obtain(daStrumTime, daNoteData, oldNote);
		swagNote.mustPress = gottaHitNote;
		swagNote.sustainLength = chartSus[idx];
		swagNote.gfNote = chartGf[idx];
		swagNote.noteType = chartType[idx];
		swagNote.scrollFactor.set();

		unspawnNotes.push(swagNote);

		final susLength:Float = swagNote.sustainLength / chartStepCrochet;
		final floorSus:Int = Math.floor(susLength);

		if(floorSus > 0) {
			for (susNote in 0...floorSus + 1)
			{
				oldNote = unspawnNotes[unspawnNotes.length - 1];

				var sustainNote:Note = Note.obtain(daStrumTime + (chartStepCrochet * susNote), daNoteData, oldNote, true);
				sustainNote.mustPress = gottaHitNote;
				sustainNote.gfNote = chartGf[idx];
				sustainNote.noteType = swagNote.noteType;
				sustainNote.scrollFactor.set();
				sustainNote.parent = swagNote;
				unspawnNotes.push(sustainNote);
				swagNote.tail.push(sustainNote);

				sustainNote.correctionOffset = swagNote.height / 2;
				if(!PlayState.isPixelStage)
				{
					if(oldNote.isSustainNote)
					{
						oldNote.scale.y *= Note.SUSTAIN_SIZE / oldNote.frameHeight;
						oldNote.scale.y /= playbackRate;
						oldNote.updateHitbox();
					}

					if(ClientPrefs.data.downScroll)
						sustainNote.correctionOffset = 0;
				}
				else if(oldNote.isSustainNote)
				{
					oldNote.scale.y /= playbackRate;
					oldNote.updateHitbox();
				}

				if (sustainNote.mustPress) sustainNote.x += FlxG.width / 2; // general offset
				else if(ClientPrefs.data.middleScroll)
				{
					sustainNote.x += 310;
					if(daNoteData > 1) //Up and Right
						sustainNote.x += FlxG.width / 2 + 25;
				}
			}
		}

		if (swagNote.mustPress)
		{
			swagNote.x += FlxG.width / 2; // general offset
		}
		else if(ClientPrefs.data.middleScroll)
		{
			swagNote.x += 310;
			if(daNoteData > 1) //Up and Right
			{
				swagNote.x += FlxG.width / 2 + 25;
			}
		}
	}

	// called only once per different event (Used for precaching)
	function eventPushed(event:EventNote) {
		eventPushedUnique(event);
		if(eventsPushed.contains(event.event)) {
			return;
		}

		stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
		eventsPushed.push(event.event);
	}

	// called by every event with the same name
	function eventPushedUnique(event:EventNote) {
		switch(event.event) {
			case "Change Character":
				var charType:Int = 0;
				switch(event.value1.toLowerCase()) {
					case 'gf' | 'girlfriend' | '1':
						charType = 2;
					case 'dad' | 'opponent' | '0':
						charType = 1;
					default:
						var val1:Int = Std.parseInt(event.value1);
						if(Math.isNaN(val1)) val1 = 0;
						charType = val1;
				}

				var newCharacter:String = event.value2;
				addCharacterToList(newCharacter, charType);

			case 'Play Sound':
				Paths.sound(event.value1); //Precache sound
		}
		stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
	}

	function eventEarlyTrigger(event:EventNote):Float {
		var returnedValue:Null<Float> = callOnScripts('eventEarlyTrigger', [event.event, event.value1, event.value2, event.strumTime], true, [], [0]);
		if(returnedValue != null && returnedValue != 0 && returnedValue != LuaUtils.Function_Continue) {
			return returnedValue;
		}

		switch(event.event) {
			case 'Kill Henchmen': //Better timing so that the kill sound matches the beat intended
				return 280; //Plays 280ms before the actual position
		}
		return 0;
	}

	public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);

	function makeEvent(event:Array<Dynamic>, i:Int)
	{
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2]
		};
		eventNotes.push(subEvent);
		eventPushed(subEvent);
		callOnScripts('onEventPushed', [subEvent.event, subEvent.value1 != null ? subEvent.value1 : '', subEvent.value2 != null ? subEvent.value2 : '', subEvent.strumTime]);
	}

	public var skipArrowStartTween:Bool = false; //for lua
	private function generateStaticArrows(player:Int):Void
	{
		var strumLineX:Float = ClientPrefs.data.middleScroll ? STRUM_X_MIDDLESCROLL : STRUM_X;
		var strumLineY:Float = ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50;
		for (i in 0...4)
		{
			// FlxG.log.add(i);
			var targetAlpha:Float = 1;
			if (player < 1)
			{
				if(!ClientPrefs.data.opponentStrums) targetAlpha = 0;
				else if(ClientPrefs.data.middleScroll) targetAlpha = 0.35;
			}

			var babyArrow:StrumNote = new StrumNote(strumLineX, strumLineY, i, player);
			babyArrow.downScroll = ClientPrefs.data.downScroll;
			if (!isStoryMode && !skipArrowStartTween)
			{
				//babyArrow.y -= 10;
				babyArrow.alpha = 0;
				FlxTween.tween(babyArrow, {/*y: babyArrow.y + 10,*/ alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * i)});
			}
			else
				babyArrow.alpha = targetAlpha;

			if (player == 1)
				playerStrums.add(babyArrow);
			else
			{
				if(ClientPrefs.data.middleScroll)
				{
					babyArrow.x += 310;
					if(i > 1) { //Up and Right
						babyArrow.x += FlxG.width / 2 + 25;
					}
				}
				opponentStrums.add(babyArrow);
			}

			strumLineNotes.add(babyArrow);
			babyArrow.postAddedToGroup();
		}
	}

	override function openSubState(SubState:FlxSubState)
	{
		stagesFunc(function(stage:BaseStage) stage.openSubState(SubState));
		if (paused)
		{
			if (FlxG.sound.music != null)
			{
				FlxG.sound.music.pause();
				vocals.pause();
				opponentVocals.pause();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if(!tmr.finished) tmr.active = false);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if(!twn.finished) twn.active = false);
		}

		super.openSubState(SubState);
	}

	override function closeSubState()
	{
		super.closeSubState();
		
		stagesFunc(function(stage:BaseStage) stage.closeSubState());
		if (paused)
		{
			if (FlxG.sound.music != null && !startingSong)
			{
				resyncVocals();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if(!tmr.finished) tmr.active = true);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if(!twn.finished) twn.active = true);

			#if VIDEOS_ALLOWED
			if(videoSprite.length > 0)
			for(video in videoSprite)
				if(video.exists)
				video.paused = false;
			#end

			paused = false;
			callOnScripts('onResume');
			resetRPC(startTimer != null && startTimer.finished);
		}
	}

	override public function onFocus():Void
	{
		if (health > 0 && !paused) resetRPC(Conductor.songPosition > 0.0);
		super.onFocus();
	}

	override public function onFocusLost():Void
	{
		#if DISCORD_ALLOWED
		if (health > 0 && !paused && autoUpdateRPC) DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end

		super.onFocusLost();
	}

	// Updating Discord Rich Presence.
	public var autoUpdateRPC:Bool = true; //performance setting for custom RPC things
	function resetRPC(?showTime:Bool = false)
	{
		#if DISCORD_ALLOWED
		if(!autoUpdateRPC) return;

		if (showTime)
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength - Conductor.songPosition - ClientPrefs.data.noteOffset);
		else
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function resyncVocals():Void
	{
		if(finishTimer != null) return;

		// 诊断: 记录每次重同步的偏差, 用于验证"人声卡"是否由高频 resync 引起
		#if mobile
		resyncCount++;
		backend.PerfProbe.log('[音画] resync #' + resyncCount
			+ ' music=' + Math.round(FlxG.sound.music.time)
			+ ' song=' + Math.round(Conductor.songPosition)
			+ ' vocals=' + Math.round(vocals.time)
			+ ' opp=' + Math.round(opponentVocals.time));
		#end

		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.play();
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		Conductor.songPosition = FlxG.sound.music.time;
		if (Conductor.songPosition <= vocals.length)
		{
			vocals.time = Conductor.songPosition;
			#if FLX_PITCH vocals.pitch = playbackRate; #end
		}

		if (Conductor.songPosition <= opponentVocals.length)
		{
			opponentVocals.time = Conductor.songPosition;
			#if FLX_PITCH opponentVocals.pitch = playbackRate; #end
		}
		vocals.play();
		opponentVocals.play();
	}

	public var paused:Bool = false;
	public var canReset:Bool = true;
	var startedCountdown:Bool = false;
	var canPause:Bool = true;
	var freezeCamera:Bool = false;
	var allowDebugKeys:Bool = true;

	override public function update(elapsed:Float)
	{
		if(!inCutscene && !paused && !freezeCamera) {
			FlxG.camera.followLerp = 2.4 * cameraSpeed * playbackRate;
			if(!startingSong && !endingSong && boyfriend.getAnimationName().startsWith('idle')) {
				boyfriendIdleTime += elapsed;
				if(boyfriendIdleTime >= 0.15) { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
					boyfriendIdled = true;
				}
			} else {
				boyfriendIdleTime = 0;
			}
		}
		else FlxG.camera.followLerp = 0;
		// B: 复用参数数组, 免每帧 [elapsed] 小数组分配
		scriptArgs[0] = elapsed;
		callOnScripts('onUpdate', scriptArgs);

		super.update(elapsed);

		// 粘性弹出超时: 停手后淡出(连打时不断刷新不清场; 暂停时 songPosition 冻结→弹出同步冻结)
		if ((ratingSticky != null || comboSticky != null || numSticky.length > 0)
			&& Conductor.songPosition >= stickyExpireAt)
			stickyStartFade();

		flushScoreText(elapsed);	// A7: 评分文本限频落盘

		// B: 值没变就不跨脚本边界写(暂停时这两个值完全冻结, 原本每帧仍要遍历所有脚本)
		if (curDecStep != syncedDecStep)
		{
			syncedDecStep = curDecStep;
			setOnScripts('curDecStep', curDecStep);
		}
		if (curDecBeat != syncedDecBeat)
		{
			syncedDecBeat = curDecBeat;
			setOnScripts('curDecBeat', curDecBeat);
		}

		if(botplayTxt != null && botplayTxt.visible) {
			botplaySine += 180 * elapsed;
			botplayTxt.alpha = 1 - Math.sin((Math.PI * botplaySine) / 180);
		}

		if (controls.PAUSE #if android || FlxG.android.justReleased.BACK #end && startedCountdown && canPause)
		{
			var ret:Dynamic = callOnScripts('onPause', null, true);
			if(ret != LuaUtils.Function_Stop) {
				openPauseMenu();
			}
		}

		if(!endingSong && !inCutscene && allowDebugKeys)
		{
			if (controls.justPressed('debug_1'))
				openChartEditor();
			else if (controls.justPressed('debug_2'))
				openCharacterEditor();
		}

		if (healthBar.bounds.max != null && health > healthBar.bounds.max)
			health = healthBar.bounds.max;

		updateIconsScale(elapsed);	// 动态钩子保留(mod 可覆盖); 引擎内 beat 弹跳已被图标挤压替代
		updateIconsPosition();
		updateIconsSquashFx(elapsed);

		// 平滑血条追踪(smoothHealthBar 脚本公式移植; ratio 超出部分由 Bar.bound 兜住, 此处仅防除零/NaN)
		if (smoothHealthOn)
		{
			if (smoothHealth <= 0.001 || Math.isNaN(smoothHealth)) smoothHealth = health;
			else smoothHealth = FlxMath.lerp(smoothHealth, health, (health / smoothHealth) * (elapsed * 8) * playbackRate);
		}

		if (startedCountdown && !paused)
		{
			Conductor.songPosition += FlxG.elapsed * 1000 * playbackRate;

			// 音画对齐: 由"积分到 ±25ms 再硬贴"改为"每帧向音频时钟软收敛"。
			// 硬贴会形成锯齿(perf_log 实测 |drift| 被夹在 15~25ms 且 >25ms 样本为 0),
			// 而 stepHit 用 20ms 判据判重同步 → 持续触发 resyncVocals()(vocals.pause()+play()),
			// 听感就是人声每 ~1s 断一次。软收敛稳态误差 <5ms, 既不会触发 resync, 判定时钟也更贴音频。
			if (!startingSong && FlxG.sound.music != null && FlxG.sound.music.playing)
			{
				var audioPos:Float = FlxG.sound.music.time;
				var clockDiff:Float = audioPos - Conductor.songPosition;
				if (Math.abs(clockDiff) > 200)	// 大跳(seek/恢复/严重掉帧)才硬贴
					Conductor.songPosition = audioPos;
				else
					Conductor.songPosition += clockDiff * 0.15;	// 软收敛, 时间常数约 0.1s

				// 人声跟随: 三条音轨是依次 play() 的, 起播后实测人声会稳定领先 36ms
				// (perf_log: v=+36ms 从 34s 一直持续到 53s), 而 stepHit 的重同步判据是 120ms, 根本修不到。
				// 起播 10s 内按 35ms 判据修(起播偏差是常数), 之后只修 >70ms 的明显错位,
				// 并限制总修正次数 + 冷却, 避免后端 position 回报滞后时反复 seek 打断人声。
				vocalsFollowTimer += FlxG.elapsed;
				var vTol:Float = (Conductor.songPosition < 10000) ? VOCALS_FOLLOW_TOL : 70;
				var vCooldown:Float = (Conductor.songPosition < 10000) ? 0.5 : 2.0;
				if (vocalsFollowTimer >= vCooldown && vocalsFixCount < 16)
				{
					vocalsFollowTimer = 0;
					if (vocals != null && vocals.length > 0)
					{
						var vDiff:Float = vocals.time - audioPos;
						// 大跳(歌曲结束 music.time 归零/seek)不是漂移, 硬修会把结尾人声拽没
						if (Math.abs(vDiff) > 3000) vDiff = 0;
						if (Math.abs(vDiff) > vTol)
						{
							vocals.time = audioPos;
							vocalsFixCount++;
							if (vocalsFixCount <= 8) backend.PerfProbe.log('[音画] 人声跟随 修正=' + Math.round(vDiff) + 'ms');
						}
					}
					if (opponentVocals != null && opponentVocals.length > 0)
					{
						var oDiff:Float = opponentVocals.time - audioPos;
						if (Math.abs(oDiff) > vTol && Math.abs(oDiff) < 3000) opponentVocals.time = audioPos;
					}
				}
			}
		}

		if (startingSong)
		{
			if (startedCountdown && Conductor.songPosition >= 0)
				startSong();
			else if(!startedCountdown)
				Conductor.songPosition = -Conductor.crochet * 5;
		}
		else if (!paused && updateTime)
		{
			var curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
			songPercent = (curTime / songLength);

			var songCalc:Float = (songLength - curTime);
			if(ClientPrefs.data.timeBarType == 'Time Elapsed') songCalc = curTime;

			var secondsTotal:Int = Math.floor(songCalc / 1000);
			if(secondsTotal < 0) secondsTotal = 0;

			// B9: 秒数没变就不重拼 formatTime/不写 .text
			if(ClientPrefs.data.timeBarType != 'Song Name' && secondsTotal != lastTimeSec)
			{
				lastTimeSec = secondsTotal;
				timeTxt.text = FlxStringUtil.formatTime(secondsTotal, false);
			}
		}

		if (camZooming)
		{
			FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
			camHUD.zoom = FlxMath.lerp(1, camHUD.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
		}

		// D4: 纯调试监视, 正式包无 debugger 时无意义
		#if debug
		FlxG.watch.addQuick("secShit", curSection);
		FlxG.watch.addQuick("beatShit", curBeat);
		FlxG.watch.addQuick("stepShit", curStep);
		#end

		// RESET = Quick Game Over Screen
		if (!ClientPrefs.data.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong)
		{
			health = 0;
			trace("RESET = True");
		}
		doDeathCheck();

		// ===== 窗口化: 把接近的数据行实例化进 unspawnNotes(保持队列短小) =====
		if (generatedMusic && chartIdx < chartTimes.length)
		{
			var preTime:Float = spawnTime * playbackRate + CHART_SPAWN_WINDOW;
			if (songSpeed < 1) preTime /= songSpeed;
			var filled:Int = 0;
			while (chartIdx < chartTimes.length && chartTimes[chartIdx] - Conductor.songPosition < preTime)
			{
				makeChartNote(chartIdx);
				chartIdx++;
				filled++;
				if (filled >= CHART_REFILL_CAP) break;	// 每帧行数上限: 防掉帧后补帧风暴(掉帧→一次性实例化更多行→更卡), 溢出顺延到后续帧
			}
			// 批量生成后按时间排序: sustain 链 piece 的 strumTime 会跨越后续行的本体时间,
			// 不排序则 spawn 队列头被"未来"的 piece 卡住, 后续行延迟出现(长箭头之间出现断缝)
			// 对齐原版: 全量生成后也有 unspawnNotes.sort(sortByTime)
			// B1: 只在本帧真的新增了行时才排序 —— 队列顺序只在增删时变化, 没新增时每帧全排是纯浪费
			if (filled > 0) unspawnNotes.sort(sortByTime);
		}

		if (unspawnNotes[0] != null)
		{
			var time:Float = spawnTime * playbackRate;
			if(songSpeed < 1) time /= songSpeed;
			if(unspawnNotes[0].multSpeed < 1) time /= unspawnNotes[0].multSpeed;

			while (unspawnNotes.length > 0 && unspawnNotes[0].strumTime - Conductor.songPosition < time)
			{
				var dunceNote:Note = unspawnNotes[0];
				notes.insert(0, dunceNote);
				dunceNote.spawned = true;

				callOnLuas('onSpawnNote', [notes.members.indexOf(dunceNote), dunceNote.noteData, dunceNote.noteType, dunceNote.isSustainNote, dunceNote.strumTime]);
				callOnHScript('onSpawnNote', [dunceNote]);

				var index:Int = (unspawnNotes[0] == dunceNote) ? 0 : unspawnNotes.indexOf(dunceNote);
				unspawnNotes.splice(index, 1);
			}
		}

		if (generatedMusic)
		{
			if(!inCutscene)
			{
				if(!cpuControlled)
					keysCheck();
				else
					playerDance();

				if(notes.length > 0)
				{
					// B3: 手写循环替代 forEachAlive(闭包) —— 每帧省两个闭包分配与回调间接开销
					// 语义对齐 flixel: 遍历 members 活元素; invalidateNote 在遍历中 remove 的行为与原版一致
					var noteMembers:Array<Note> = notes.members;
					if(startedCountdown)
					{
						var fakeCrochet:Float = (60 / SONG.bpm) * 1000;
						for (i in 0...noteMembers.length)
						{
							var daNote:Note = noteMembers[i];
							if(daNote == null || !daNote.alive) continue;

							var strumGroup:FlxTypedGroup<StrumNote> = playerStrums;
							if(!daNote.mustPress) strumGroup = opponentStrums;

							var strum:StrumNote = strumGroup.members[daNote.noteData];
							daNote.followStrumNote(strum, fakeCrochet, songSpeed / playbackRate);

							if(daNote.mustPress)
							{
								if(cpuControlled && !daNote.blockHit && daNote.canBeHit && (daNote.isSustainNote || daNote.strumTime <= Conductor.songPosition))
									goodNoteHit(daNote);
							}
							else if (daNote.wasGoodHit && !daNote.hitByOpponent && !daNote.ignoreNote)
								opponentNoteHit(daNote);

							if(daNote.isSustainNote && strum.sustainReduce) daNote.clipToStrumNote(strum);

							// Kill extremely late notes and cause misses
							if (Conductor.songPosition - daNote.strumTime > noteKillOffset)
							{
								if (daNote.mustPress && !cpuControlled && !daNote.ignoreNote && !endingSong && (daNote.tooLate || !daNote.wasGoodHit))
									noteMiss(daNote);

								daNote.active = daNote.visible = false;
								invalidateNote(daNote);
							}
						}
					}
					else
					{
						for (i in 0...noteMembers.length)
						{
							var daNote:Note = noteMembers[i];
							if(daNote == null || !daNote.alive) continue;
							daNote.canBeHit = false;
							daNote.wasGoodHit = false;
						}
					}
				}
			}
			checkEventNote();
		}

		#if debug
		if(!endingSong && !startingSong) {
			if (FlxG.keys.justPressed.ONE) {
				KillNotes();
				FlxG.sound.music.onComplete();
			}
			if(FlxG.keys.justPressed.TWO) { //Go 10 seconds into the future :O
				setSongTime(Conductor.songPosition + 10000);
				clearNotesBefore(Conductor.songPosition);
			}
		}
		#end

		// B: 变更检测 —— 镜头静止/机器人开关不变时不再每帧遍历所有脚本写全局
		if (camFollow.x != syncedCamX)
		{
			syncedCamX = camFollow.x;
			setOnScripts('cameraX', camFollow.x);
		}
		if (camFollow.y != syncedCamY)
		{
			syncedCamY = camFollow.y;
			setOnScripts('cameraY', camFollow.y);
		}
		if (cpuControlled != syncedBotPlay)
		{
			syncedBotPlay = cpuControlled;
			setOnScripts('botPlay', cpuControlled);
		}
		scriptArgs[0] = elapsed;
		callOnScripts('onUpdatePost', scriptArgs);
	}

	// Health icon updaters
	public dynamic function updateIconsScale(elapsed:Float)
	{
		// 原版 beat 弹跳已被图标挤压(updateIconsSquashFx)替代; 保留动态钩子供 mod 脚本覆盖
	}

	public dynamic function updateIconsPosition()
	{
		var iconOffset:Int = 26;
		iconP1.x = healthBar.barCenter + (150 * iconP1.scale.x - 150) / 2 - iconOffset;
		iconP2.x = healthBar.barCenter - (150 * iconP2.scale.x) / 2 - iconOffset * 2;
	}

	// ===== 图标挤压: 源码移植挤压.lua =====

	function startIconSquash(idx:Int, a:Float, f:Float, d:Float, sw:Float, rot:Float, rotF:Float, rest:Float):Void
	{
		iconSquashAmp[idx] = a; iconSquashFreq[idx] = f; iconSquashDamp[idx] = d;
		iconSwingAmp[idx] = sw; iconRotAmp[idx] = rot; iconRotFreq[idx] = rotF;
		iconRestOffset[idx] = rest;
		iconIsSquashing[idx] = true;
		iconSquashT[idx] = 0;
	}

	function startIconSquashByHp(idx:Int):Void
	{
		// 玩家血量 0-100; 对手血量与玩家互补(玩家 100% = 对手 0%), 档位按各自血量取
		var hp:Float = (idx == 0) ? health * 50 : 100 - health * 50;
		if (hp > 80) startIconSquash(idx, 0.35, 22, 5, 0, 12, 14, -3);
		else if (hp < 20) startIconSquash(idx, 0.50, 5, 12, 1.5, 0, 0, 7);
		else startIconSquash(idx, 0.30, 18, 7, 0, 0, 0, 0);
	}

	function resetIconsSquash():Void
	{
		iconP1.scale.set(1, 1);
		iconP1.angle = 0;
		iconP1.y = iconBaseY1 + iconCurRestOffset[0];
		iconP2.scale.set(1, 1);
		iconP2.angle = 0;
		iconP2.y = iconBaseY2 + iconCurRestOffset[1];
	}

	// 在 updateIconsPosition 之后调用: x 已被原版定位重置, swing 直接叠加不累积
	public dynamic function updateIconsSquashFx(elapsed:Float):Void
	{
		// 基准懒抓(首帧所有初始化已完成, scale=1)
		if (iconBaseH1 <= 0)
		{
			iconBaseY1 = iconP1.y; iconBaseH1 = iconP1.height;
			iconBaseY2 = iconP2.y; iconBaseH2 = iconP2.height;
		}

		if (iconIsMissed)
		{
			// miss 静止期间持续检查血量, 玩家血量掉破 20% 立刻解除
			if (health * 50 < 20) { iconIsMissed = false; startIconSquashByHp(0); startIconSquashByHp(1); }
			else
			{
				iconP1.scale.set(1, 1); iconP1.angle = 0; iconP1.y = iconBaseY1;
				iconP2.scale.set(1, 1); iconP2.angle = 0; iconP2.y = iconBaseY2;
				return;
			}
		}

		// B5: 两次直接调用替代每帧 [iconP1, iconP2] 数组分配
		applyIconSquash(iconP1, 0, elapsed, iconBaseY1, iconBaseH1);
		applyIconSquash(iconP2, 1, elapsed, iconBaseY2, iconBaseH2);
	}

	// 单个血条图标的挤压/静止偏移计算(从 updateIconsSquashFx 的循环体拆出)
	function applyIconSquash(spr:FlxSprite, i:Int, elapsed:Float, baseY:Float, baseH:Float):Void
	{
		// 静止偏移缓动(低血下坠/满血上浮), 两组各自独立
		iconCurRestOffset[i] += (iconRestOffset[i] - iconCurRestOffset[i]) * Math.min(1, 6 * elapsed);

		if (!iconIsSquashing[i])
		{
			spr.scale.set(1, 1); spr.angle = 0;
			spr.y = baseY + iconCurRestOffset[i];
			return;
		}

		iconSquashT[i] += elapsed;
		var env:Float = Math.exp(-iconSquashDamp[i] * iconSquashT[i]);
		var osc:Float = Math.cos(iconSquashFreq[i] * iconSquashT[i]);
		var mult:Float = 1 - iconSquashAmp[i] * env * osc;

		var off:Float = baseH * (1 - mult) * 0.5;
		var swing:Float = (iconSwingAmp[i] > 0) ? Math.sin(iconSquashT[i] * 80) * iconSwingAmp[i] * env : 0;
		var rot:Float = (iconRotAmp[i] > 0) ? Math.sin(iconSquashT[i] * iconRotFreq[i]) * iconRotAmp[i] * env : 0;

		spr.scale.set(1, mult);
		spr.updateHitbox();
		spr.x += swing;
		spr.y = baseY + off + iconCurRestOffset[i];
		spr.angle = (i == 0) ? rot : -rot;	// 角度对称

		if (env < 0.01)
		{
			iconIsSquashing[i] = false;
			spr.scale.set(1, 1); spr.angle = 0;
		}
	}

	var iconsAnimations:Bool = true;
	function set_health(value:Float):Float // You can alter how icon animations work here
	{
		if(!iconsAnimations || healthBar == null || !healthBar.enabled || healthBar.valueFunction == null)
		{
			health = value;
			return health;
		}

		// update health bar
		health = value;
		var newPercent:Null<Float> = FlxMath.remapToRange(FlxMath.bound(healthBar.valueFunction(), healthBar.bounds.min, healthBar.bounds.max), healthBar.bounds.min, healthBar.bounds.max, 0, 100);
		healthBar.percent = (newPercent != null ? newPercent : 0);

		iconP1.animation.curAnim.curFrame = (healthBar.percent < 20) ? 1 : 0; //If health is under 20%, change player icon to frame 1 (losing icon), otherwise, frame 0 (normal)
		iconP2.animation.curAnim.curFrame = (healthBar.percent > 80) ? 1 : 0; //If health is over 80%, change opponent icon to frame 1 (losing icon), otherwise, frame 0 (normal)
		return health;
	}

	function openPauseMenu()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		#if VIDEOS_ALLOWED
		if(videoSprite.length > 0)
			for(video in videoSprite)
				if(video.exists)
					video.paused = true;
		#end

		if(FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}
		if(!cpuControlled)
		{
			for (note in playerStrums)
				if(note.animation.curAnim != null && note.animation.curAnim.name != 'static')
				{
					note.playAnim('static');
					note.resetAnim = 0;
				}
		}
		openSubState(new PauseSubState());

		#if DISCORD_ALLOWED
		if(autoUpdateRPC) DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	public function openChartEditor()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();
		chartingMode = true;

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Chart Editor", null, null, true);
		DiscordClient.resetClientID();
		#end

		MusicBeatState.switchState(new ChartingState());
	}

	function openCharacterEditor()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();
		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
		MusicBeatState.switchState(new CharacterEditorState(SONG.player2));
	}

	public var isDead:Bool = false; //Don't mess with this on Lua!!!
	function doDeathCheck(?skipHealthCheck:Bool = false) {
		if (((skipHealthCheck && instakillOnMiss) || health <= 0) && !practiceMode && !isDead)
		{
			var ret:Dynamic = callOnScripts('onGameOver', null, true);
			if(ret != LuaUtils.Function_Stop) {
				FlxG.animationTimeScale = 1;
				boyfriend.stunned = true;
				deathCounter++;

				paused = true;

				vocals.stop();
				opponentVocals.stop();
				FlxG.sound.music.stop();

				persistentUpdate = false;
				persistentDraw = false;
				FlxTimer.globalManager.clear();
				FlxTween.globalManager.clear();
				#if LUA_ALLOWED
				modchartTimers.clear();
				modchartTweens.clear();
				#end

				#if VIDEOS_ALLOWED
				if(videoSprite.length > 0)
					for(video in videoSprite)
						removeVideoSprite(video);
				#end

				openSubState(new GameOverSubstate());

				// MusicBeatState.switchState(new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

				#if DISCORD_ALLOWED
				// Game Over doesn't get his its variable because it's only used here
				if(autoUpdateRPC) DiscordClient.changePresence("Game Over - " + detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
				#end
				isDead = true;
				return true;
			}
		}
		return false;
	}

	// 事件索引推进: 与谱面窗口化同模式, 事件多时避免每帧 shift 搬移 O(n)
	public function checkEventNote() {
		while(evtIdx < eventNotes.length) {
			var leStrumTime:Float = eventNotes[evtIdx].strumTime;
			if(Conductor.songPosition < leStrumTime) {
				return;
			}

			var value1:String = '';
			if(eventNotes[evtIdx].value1 != null)
				value1 = eventNotes[evtIdx].value1;

			var value2:String = '';
			if(eventNotes[evtIdx].value2 != null)
				value2 = eventNotes[evtIdx].value2;

			triggerEvent(eventNotes[evtIdx].event, value1, value2, leStrumTime);
			evtIdx++;
		}
	}

	public function triggerEvent(eventName:String, value1:String, value2:String, strumTime:Float) {
		// C: 事件打点(每首只有个位数到几十个) —— 用于把打歌中的大冻结/尖帧和具体事件对上
		#if mobile
		backend.PerfProbe.log('[事件] ' + eventName + ' | ' + value1 + ' | ' + value2 + ' @' + Math.round(strumTime) + 'ms');
		#end
		var flValue1:Null<Float> = Std.parseFloat(value1);
		var flValue2:Null<Float> = Std.parseFloat(value2);
		if(Math.isNaN(flValue1)) flValue1 = null;
		if(Math.isNaN(flValue2)) flValue2 = null;

		switch(eventName) {
			case 'Hey!':
				var value:Int = 2;
				switch(value1.toLowerCase().trim()) {
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}

				if(flValue2 == null || flValue2 <= 0) flValue2 = 0.6;

				if(value != 0) {
					if(dad.curCharacter.startsWith('gf')) { //Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						dad.playAnim('cheer', true);
						dad.specialAnim = true;
						dad.heyTimer = flValue2;
					} else if (gf != null) {
						gf.playAnim('cheer', true);
						gf.specialAnim = true;
						gf.heyTimer = flValue2;
					}
				}
				if(value != 1) {
					boyfriend.playAnim('hey', true);
					boyfriend.specialAnim = true;
					boyfriend.heyTimer = flValue2;
				}

			case 'Set GF Speed':
				if(flValue1 == null || flValue1 < 1) flValue1 = 1;
				gfSpeed = Math.round(flValue1);

			case 'Add Camera Zoom':
				if(ClientPrefs.data.camZooms && FlxG.camera.zoom < 1.35) {
					if(flValue1 == null) flValue1 = 0.015;
					if(flValue2 == null) flValue2 = 0.03;

					FlxG.camera.zoom += flValue1;
					camHUD.zoom += flValue2;
				}

			case 'Play Animation':
				//trace('Anim to play: ' + value1);
				var char:Character = dad;
				switch(value2.toLowerCase().trim()) {
					case 'bf' | 'boyfriend':
						char = boyfriend;
					case 'gf' | 'girlfriend':
						char = gf;
					default:
						if(flValue2 == null) flValue2 = 0;
						switch(Math.round(flValue2)) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.playAnim(value1, true);
					char.specialAnim = true;
				}

			case 'Camera Follow Pos':
				if(camFollow != null)
				{
					isCameraOnForcedPos = false;
					if(flValue1 != null || flValue2 != null)
					{
						isCameraOnForcedPos = true;
						if(flValue1 == null) flValue1 = 0;
						if(flValue2 == null) flValue2 = 0;
						camFollow.x = flValue1;
						camFollow.y = flValue2;
					}
				}

			case 'Alt Idle Animation':
				var char:Character = dad;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						char = gf;
					case 'boyfriend' | 'bf':
						char = boyfriend;
					default:
						var val:Int = Std.parseInt(value1);
						if(Math.isNaN(val)) val = 0;

						switch(val) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}

			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [camGame, camHUD];
				for (i in 0...targetsArray.length) {
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if(split[0] != null) duration = Std.parseFloat(split[0].trim());
					if(split[1] != null) intensity = Std.parseFloat(split[1].trim());
					if(Math.isNaN(duration)) duration = 0;
					if(Math.isNaN(intensity)) intensity = 0;

					if(duration > 0 && intensity != 0) {
						targetsArray[i].shake(intensity, duration);
					}
				}


			case 'Change Character':
				var charType:Int = 0;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						charType = Std.parseInt(value1);
						if(Math.isNaN(charType)) charType = 0;
				}

				switch(charType) {
					case 0:
						if(boyfriend.curCharacter != value2) {
							if(!boyfriendMap.exists(value2)) {
								addCharacterToList(value2, charType);
							}

							var lastAlpha:Float = boyfriend.alpha;
							boyfriend.alpha = 0.00001;
							boyfriend = boyfriendMap.get(value2);
							boyfriend.alpha = lastAlpha;
							iconP1.changeIcon(boyfriend.healthIcon);
						}
						setOnScripts('boyfriendName', boyfriend.curCharacter);

					case 1:
						if(dad.curCharacter != value2) {
							if(!dadMap.exists(value2)) {
								addCharacterToList(value2, charType);
							}

							var wasGf:Bool = dad.curCharacter.startsWith('gf-') || dad.curCharacter == 'gf';
							var lastAlpha:Float = dad.alpha;
							dad.alpha = 0.00001;
							dad = dadMap.get(value2);
							if(!dad.curCharacter.startsWith('gf-') && dad.curCharacter != 'gf') {
								if(wasGf && gf != null) {
									gf.visible = true;
								}
							} else if(gf != null) {
								gf.visible = false;
							}
							dad.alpha = lastAlpha;
							iconP2.changeIcon(dad.healthIcon);
						}
						setOnScripts('dadName', dad.curCharacter);

					case 2:
						if(gf != null)
						{
							if(gf.curCharacter != value2)
							{
								if(!gfMap.exists(value2)) {
									addCharacterToList(value2, charType);
								}

								var lastAlpha:Float = gf.alpha;
								gf.alpha = 0.00001;
								gf = gfMap.get(value2);
								gf.alpha = lastAlpha;
							}
							setOnScripts('gfName', gf.curCharacter);
						}
				}
				reloadHealthBarColors();

			case 'Change Scroll Speed':
				if (songSpeedType != "constant")
				{
					if(flValue1 == null) flValue1 = 1;
					if(flValue2 == null) flValue2 = 0;

					var newValue:Float = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
					if(flValue2 <= 0)
						songSpeed = newValue;
					else
						songSpeedTween = FlxTween.tween(this, {songSpeed: newValue}, flValue2 / playbackRate, {ease: FlxEase.linear, onComplete:
							function (twn:FlxTween)
							{
								songSpeedTween = null;
							}
						});
				}

			case 'Set Property':
				try
				{
					var split:Array<String> = value1.split('.');
					if(split.length > 1) {
						LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1], value2);
					} else {
						LuaUtils.setVarInArray(this, value1, value2);
					}
				}
				catch(e:Dynamic)
				{
					var len:Int = e.message.indexOf('\n') + 1;
					if(len <= 0) len = e.message.length;
					#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
					addTextToDebug('ERROR ("Set Property" Event) - ' + e.message.substr(0, len), FlxColor.RED);
					#else
					FlxG.log.warn('ERROR ("Set Property" Event) - ' + e.message.substr(0, len));
					#end
				}

			case 'Play Sound':
				if(flValue2 == null) flValue2 = 1;
				FlxG.sound.play(Paths.sound(value1), flValue2);
		}

		stagesFunc(function(stage:BaseStage) stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime));
		callOnScripts('onEvent', [eventName, value1, value2, strumTime]);
	}

	function moveCameraSection(?sec:Null<Int>):Void {
		if(sec == null) sec = curSection;
		if(sec < 0) sec = 0;

		if(SONG.notes[sec] == null) return;

		if (gf != null && SONG.notes[sec].gfSection)
		{
			camFollow.setPosition(gf.getMidpoint().x, gf.getMidpoint().y);
			camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
			camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
			tweenCamIn();
			callOnScripts('onMoveCamera', ['gf']);
			return;
		}

		var isDad:Bool = (SONG.notes[sec].mustHitSection != true);
		moveCamera(isDad);
		callOnScripts('onMoveCamera', [isDad ? 'dad' : 'boyfriend']);
	}

	var cameraTwn:FlxTween;
	public function moveCamera(isDad:Bool)
	{
		if(isDad)
		{
			camFollow.setPosition(dad.getMidpoint().x + 150, dad.getMidpoint().y - 100);
			camFollow.x += dad.cameraPosition[0] + opponentCameraOffset[0];
			camFollow.y += dad.cameraPosition[1] + opponentCameraOffset[1];
			tweenCamIn();
		}
		else
		{
			camFollow.setPosition(boyfriend.getMidpoint().x - 100, boyfriend.getMidpoint().y - 100);
			camFollow.x -= boyfriend.cameraPosition[0] - boyfriendCameraOffset[0];
			camFollow.y += boyfriend.cameraPosition[1] + boyfriendCameraOffset[1];

			if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1)
			{
				cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
					function (twn:FlxTween)
					{
						cameraTwn = null;
					}
				});
			}
		}
	}

	public function tweenCamIn() {
		if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1.3) {
			cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
				function (twn:FlxTween) {
					cameraTwn = null;
				}
			});
		}
	}

	public function finishSong(?ignoreNoteOffset:Bool = false):Void
	{
		updateTime = false;
		FlxG.sound.music.volume = 0;

		vocals.volume = 0;
		vocals.pause();
		opponentVocals.volume = 0;
		opponentVocals.pause();

		if(ClientPrefs.data.noteOffset <= 0 || ignoreNoteOffset) {
			endCallback();
		} else {
			finishTimer = new FlxTimer().start(ClientPrefs.data.noteOffset / 1000, function(tmr:FlxTimer) {
				endCallback();
			});
		}
	}


	public var transitioning = false;
	public function endSong()
	{
		//Should kill you if you tried to cheat
		if(!startingSong) {
			notes.forEach(function(daNote:Note) {
				if(daNote.strumTime < songLength - Conductor.safeZoneOffset) {
					health -= 0.05 * healthLoss;
				}
			});
			for (daNote in unspawnNotes) {
				if(daNote.strumTime < songLength - Conductor.safeZoneOffset) {
					health -= 0.05 * healthLoss;
				}
			}
			// 数据层: 尚未实例化的行同样参与结束扣血判定
			var ci:Int = chartIdx;
			while (ci < chartTimes.length) {
				if (chartTimes[ci] < songLength - Conductor.safeZoneOffset)
					health -= 0.05 * healthLoss;
				ci++;
			}

			if(doDeathCheck()) {
				return false;
			}
		}
		
		#if mobile
		hitbox.visible = false;
		#end

		timeBar.visible = false;
		timeTxt.visible = false;
		canPause = false;
		endingSong = true;
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		deathCounter = 0;
		seenCutscene = false;

		#if ACHIEVEMENTS_ALLOWED
		var weekNoMiss:String = WeekData.getWeekFileName() + '_nomiss';
		checkForAchievement([weekNoMiss, 'ur_bad', 'ur_good', 'hype', 'two_keys', 'toastie', 'debugger']);
		#end

		var ret:Dynamic = callOnScripts('onEndSong', null, true);
		if(ret != LuaUtils.Function_Stop && !transitioning)
		{
			#if !switch
			var percent:Float = ratingPercent;
			if(Math.isNaN(percent)) percent = 0;
			Highscore.saveScore(SONG.song, songScore, storyDifficulty, percent);
			#end
			playbackRate = 1;

			if (chartingMode)
			{
				openChartEditor();
				return false;
			}

			if (isStoryMode)
			{
				campaignScore += songScore;
				campaignMisses += songMisses;

				storyPlaylist.remove(storyPlaylist[0]);

				if (storyPlaylist.length <= 0)
				{
					Mods.loadTopMod();
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

					MusicBeatState.switchState(new StoryMenuState());

					// if ()
					if(!ClientPrefs.getGameplaySetting('practice') && !ClientPrefs.getGameplaySetting('botplay')) {
						StoryMenuState.weekCompleted.set(WeekData.weeksList[storyWeek], true);
						Highscore.saveWeekScore(WeekData.getWeekFileName(), campaignScore, storyDifficulty);

						FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
						FlxG.save.flush();
					}
					changedDifficulty = false;
				}
				else
				{
					var difficulty:String = Difficulty.getFilePath();

					trace('LOADING NEXT SONG');
					trace(Paths.formatToSongPath(PlayState.storyPlaylist[0]) + difficulty);

					FlxTransitionableState.skipNextTransIn = true;
					FlxTransitionableState.skipNextTransOut = true;
					prevCamFollow = camFollow;

					backend.PerfProbe.loadMarkReset();
					PlayState.SONG = Song.loadFromJson(PlayState.storyPlaylist[0] + difficulty, PlayState.storyPlaylist[0]);
					backend.PerfProbe.loadMark('story 下一首 JSON解析完');
					FlxG.sound.music.stop();

					LoadingState.loadAndSwitchState(new PlayState());
				}
			}
			else
			{
				trace('WENT BACK TO FREEPLAY??');
				Mods.loadTopMod();
				#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

				MusicBeatState.switchState(new FreeplayState());
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
				changedDifficulty = false;
			}
			transitioning = true;
		}
		return true;
	}

	public function KillNotes() {
		while(notes.length > 0) {
			var daNote:Note = notes.members[0];
			daNote.active = false;
			daNote.visible = false;
			invalidateNote(daNote);
		}
		// C1: 未生成的音符也回收进池(旧实现直接丢引用, 这些对象只能等 GC)
		while (unspawnNotes.length > 0)
		{
			var daNote:Note = unspawnNotes.pop();
			if (daNote != null) daNote.recycle();
		}
		eventNotes = [];
		evtIdx = 0;
		// C1 诊断: 新建/复用计数, 下次日志可直接确认对象池是否生效
		backend.PerfProbe.log('[池] 音符 新建=' + Note.createdCount + ' 复用=' + Note.reusedCount + ' 池=' + Note.pool.length);
	}

	public var totalPlayed:Int = 0;
	public var totalNotesHit:Float = 0.0;

	public var showCombo:Bool = false;
	public var showComboNum:Bool = true;
	public var showRating:Bool = true;

	// Stores Ratings and Combo Sprites in a group
	public var comboGroup:FlxSpriteGroup;
	// Stores HUD Objects in a Group
	public var uiGroup:FlxSpriteGroup;
	// Stores Note Objects in a Group
	public var noteGroup:FlxTypedGroup<FlxBasic>;

	private function cachePopUpScore()
	{
		var uiPrefix:String = '';
		var uiSuffix:String = '';
		if (stageUI != "normal")
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
		}

		for (rating in ratingsData)
			Paths.image(uiPrefix + rating.image + uiSuffix);
		for (i in 0...10)
			Paths.image(uiPrefix + 'num' + i + uiSuffix);
	}

	// ===== popUpScore 对象池: 弹出精灵(rating/combo 文字/数字)复用, 击中不再 new/destroy(削 GC 分配) =====
	public var popupPool:Array<FlxSprite> = [];

	// 本 port 的 flixel 无 FlxTween.killTweensOf: 弹出 tween 自行登记, 回收/复用时逐个 cancel
	var popupTweens:Map<FlxSprite, Array<FlxTween>> = [];

	function regPopupTween(spr:FlxSprite, t:FlxTween):FlxTween
	{
		var arr:Array<FlxTween> = popupTweens.get(spr);
		if (arr == null) { arr = []; popupTweens.set(spr, arr); }
		arr.push(t);
		return t;
	}

	function killPopupTweens(spr:FlxSprite):Void
	{
		var arr:Array<FlxTween> = popupTweens.get(spr);
		if (arr == null) return;
		for (t in arr)
			if (t != null && t.active) t.cancel();	// 只 cancel 活跃 tween; 已完成的不动(防回调内重入)
		popupTweens.remove(spr);
	}

	function takePopupSprite():FlxSprite
	{
		var spr:FlxSprite = popupPool.pop();
		if (spr == null) spr = new FlxSprite();
		killPopupTweens(spr);				// 清掉上一轮残留的淡出/回弹 tween(含延迟中的, 防旧回调误回收)
		spr.revive();
		spr.scale.set(1, 1);				// 清残留缩放: 否则上一轮 Q 弹的 scale 会污染 setGraphicSize 的基准(越用越小)
		spr.alpha = 1;
		spr.angle = 0;
		spr.velocity.set(0, 0);
		spr.acceleration.set(0, 0);
		return spr;
	}

	function recyclePopupSprite(spr:FlxSprite):Void
	{
		killPopupTweens(spr);
		spr.velocity.set(0, 0);
		spr.acceleration.set(0, 0);
		spr.kill();
		comboGroup.remove(spr);
		popupPool.push(spr);
	}

	// ===== 粘性弹出(comboStacking=开): 击中原地刷新, 停手超时淡出; 暂停时随 songPosition 冻结 =====
	var ratingSticky:FlxSprite = null;
	var comboSticky:FlxSprite = null;
	var numSticky:Array<FlxSprite> = [];
	var stickyExpireAt:Float = 0;
	var stickyTimeoutMs:Float = 600;	// 停手多久开始淡出(可调 400-1000)

	function clearSticky():Void
	{
		if (ratingSticky != null) { var s:FlxSprite = ratingSticky; ratingSticky = null; recyclePopupSprite(s); }
		if (comboSticky != null) { var s:FlxSprite = comboSticky; comboSticky = null; recyclePopupSprite(s); }
		while (numSticky.length > 0)
		{
			var s:FlxSprite = numSticky.pop();
			if (s != null) recyclePopupSprite(s);
		}
	}

	function stickyStartFade():Void
	{
		var group:Array<FlxSprite> = [];
		if (ratingSticky != null) group.push(ratingSticky);
		if (comboSticky != null) group.push(comboSticky);
		for (tmpS in numSticky) if (tmpS != null) group.push(tmpS);
		ratingSticky = null; comboSticky = null; numSticky = [];
		for (tmpS in group)
		{
			var s:FlxSprite = tmpS;	// 循环体内重新声明, 闭包按次捕获
			regPopupTween(s, FlxTween.tween(s, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(t:FlxTween)
				{
					recyclePopupSprite(s);
				}
			}));
		}
	}

	private function popUpScore(note:Note = null):Void
	{
		var __allocH:Float = backend.PerfProbe.heapMB();	// C: 分配归因
		// 判定直方图: 带符号偏差(正=按早, 负=按晚), 除以速率与判定窗口同尺度; botplay 不计
		if (!cpuControlled)
			backend.PerfProbe.onJudge((note.strumTime - Conductor.songPosition) / playbackRate, false);
		var noteDiff:Float = Math.abs(note.strumTime - Conductor.songPosition + ClientPrefs.data.ratingOffset);
		vocals.volume = 1;

		var stickyMode:Bool = ClientPrefs.data.comboStacking;
		if (stickyMode)
			clearSticky();		// 粘性模式: 旧的立即回池, 原地刷新(任何时刻每类至多 1 个, 鬼影堆叠根除)
		else if (comboGroup.members.length > 0) {
			var ci:Int = comboGroup.members.length - 1;
			while (ci >= 0) {
				var spr:FlxSprite = cast comboGroup.members[ci];
				if (spr != null) recyclePopupSprite(spr);
				ci--;
			}
		}

		var placement:Float = FlxG.width * 0.35;
		var rating:FlxSprite = takePopupSprite();
		var score:Int = 350;

		//tryna do MS based judgment due to popular demand
		var daRating:Rating = Conductor.judgeNote(ratingsData, noteDiff / playbackRate);

		totalNotesHit += daRating.ratingMod;
		note.ratingMod = daRating.ratingMod;
		if(!note.ratingDisabled) daRating.hits++;
		note.rating = daRating.name;
		score = daRating.score;

		if(daRating.noteSplash && !note.noteSplashData.disabled)
			spawnNoteSplashOnNote(note);

		if(!practiceMode && !cpuControlled) {
			songScore += score;
			if(!note.ratingDisabled)
			{
				songHits++;
				totalPlayed++;
				RecalculateRating(false);
			}
		}

		var uiPrefix:String = "";
		var uiSuffix:String = '';
		var antialias:Bool = ClientPrefs.data.antialiasing;

		if (stageUI != "normal")
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
			antialias = !isPixelStage;
		}

		rating.loadGraphic(Paths.image(uiPrefix + daRating.image + uiSuffix));
		rating.screenCenter();
		rating.x = placement - 40;
		rating.y -= 60;
		if (!stickyMode)
		{
			rating.acceleration.y = 550 * playbackRate * playbackRate;
			rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;
			rating.velocity.x -= FlxG.random.int(0, 10) * playbackRate;
		}	// 粘性模式: 停住不动(take 已归零速度/重力), 击中刷新+Q弹, 停手超时淡出
		rating.visible = (!ClientPrefs.data.hideHud && showRating);
		rating.x += ClientPrefs.data.comboOffset[0];
		rating.y -= ClientPrefs.data.comboOffset[1];
		rating.antialiasing = antialias;

		var comboSpr:FlxSprite = takePopupSprite();
		comboSpr.loadGraphic(Paths.image(uiPrefix + 'combo' + uiSuffix));
		comboSpr.screenCenter();
		comboSpr.x = placement;
		if (!stickyMode)
		{
			comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
			comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
		}
		comboSpr.visible = (!ClientPrefs.data.hideHud && showCombo);
		comboSpr.x += ClientPrefs.data.comboOffset[0];
		comboSpr.y -= ClientPrefs.data.comboOffset[1];
		comboSpr.antialiasing = antialias;
		comboSpr.y += 60;
		if (!stickyMode)
			comboSpr.velocity.x += FlxG.random.int(1, 10) * playbackRate;
		comboGroup.add(rating);

		if (!PlayState.isPixelStage)
		{
			rating.setGraphicSize(Std.int(rating.width * 0.7));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * 0.7));
		}
		else
		{
			rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.85));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * daPixelZoom * 0.85));
		}

		comboSpr.updateHitbox();
		rating.updateHitbox();

		// Q弹: 随机初倾 + 果冻起手(横拉纵压), 弹性回正; 数字保持原版不倾斜
		var rbX:Float = rating.scale.x;
		var rbY:Float = rating.scale.y;
		rating.angle = FlxG.random.float(-10, 10);
		rating.scale.set(rbX * 1.3, rbY * 0.8);
		regPopupTween(rating, FlxTween.tween(rating, {angle: 0}, 0.5 / playbackRate, {ease: FlxEase.elasticOut}));
		regPopupTween(rating, FlxTween.tween(rating.scale, {x: rbX, y: rbY}, 0.45 / playbackRate, {ease: FlxEase.backOut}));

		var cbX:Float = comboSpr.scale.x;
		var cbY:Float = comboSpr.scale.y;
		comboSpr.angle = FlxG.random.float(-10, 10);
		comboSpr.scale.set(cbX * 1.3, cbY * 0.8);
		regPopupTween(comboSpr, FlxTween.tween(comboSpr, {angle: 0}, 0.5 / playbackRate, {ease: FlxEase.elasticOut}));
		regPopupTween(comboSpr, FlxTween.tween(comboSpr.scale, {x: cbX, y: cbY}, 0.45 / playbackRate, {ease: FlxEase.backOut}));

		var seperatedScore:Array<Int> = [];

		if(combo >= 1000) {
			seperatedScore.push(Math.floor(combo / 1000) % 10);
		}
		seperatedScore.push(Math.floor(combo / 100) % 10);
		seperatedScore.push(Math.floor(combo / 10) % 10);
		seperatedScore.push(combo % 10);

		var daLoop:Int = 0;
		var xThing:Float = 0;
		if (showCombo)
			comboGroup.add(comboSpr);

		for (i in seperatedScore)
		{
			var numScore:FlxSprite = takePopupSprite();
			numScore.loadGraphic(Paths.image(uiPrefix + 'num' + Std.int(i) + uiSuffix));
			numScore.screenCenter();
			numScore.x = placement + (43 * daLoop) - 90 + ClientPrefs.data.comboOffset[2];
			numScore.y += 80 - ClientPrefs.data.comboOffset[3];

			if (!PlayState.isPixelStage) numScore.setGraphicSize(Std.int(numScore.width * 0.5));
			else numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
			numScore.updateHitbox();

			if (!stickyMode)
			{
				numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
				numScore.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
				numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
			}
			numScore.visible = !ClientPrefs.data.hideHud;
			numScore.antialiasing = antialias;

			//if (combo >= 10 || combo == 0)
			if(showComboNum)
				comboGroup.add(numScore);

			if (stickyMode)
				numSticky.push(numScore);	// 粘性: 停住常驻, 超时统一淡出
			else
			{
				regPopupTween(numScore, FlxTween.tween(numScore, {alpha: 0}, 0.2 / playbackRate, {
					onComplete: function(tween:FlxTween)
					{
						recyclePopupSprite(numScore);
					},
					startDelay: Conductor.crochet * 0.002 / playbackRate
				}));
			}

			daLoop++;
			if(numScore.x > xThing) xThing = numScore.x;
		}
		comboSpr.x = xThing + 50;
		if (stickyMode)
		{
			// 登记粘性实例 + 超时点: 停手 stickyTimeoutMs 后由 update 触发淡出
			ratingSticky = rating;
			comboSticky = comboSpr;
			stickyExpireAt = Conductor.songPosition + stickyTimeoutMs / playbackRate;
		}
		else
		{
			regPopupTween(rating, FlxTween.tween(rating, {alpha: 0}, 0.2 / playbackRate, {
				startDelay: Conductor.crochet * 0.001 / playbackRate
			}));

			regPopupTween(comboSpr, FlxTween.tween(comboSpr, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					recyclePopupSprite(comboSpr);
					recyclePopupSprite(rating);
				},
				startDelay: Conductor.crochet * 0.002 / playbackRate
			}));
		}
		backend.PerfProbe.addAlloc('弹窗', __allocH);	// C: 分配归因
	}

	public var strumsBlocked:Array<Bool> = [];
	private function onKeyPress(event:KeyboardEvent):Void
	{

		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);

		if (!controls.controllerMode)
		{
			#if debug
			//Prevents crash specifically on debug without needing to try catch shit
			@:privateAccess if (!FlxG.keys._keyListMap.exists(eventKey)) return;
			#end

			if(FlxG.keys.checkStatus(eventKey, JUST_PRESSED)) keyPressed(key);
		}
	}

	private function keyPressed(key:Int)
	{
		if(cpuControlled || paused || inCutscene || key < 0 || key >= playerStrums.length || !generatedMusic || endingSong || boyfriend.stunned) return;

		var ret:Dynamic = callOnScripts('onKeyPressPre', [key]);
		if(ret == LuaUtils.Function_Stop) return;

		// more accurate hit time for the ratings?
		var lastTime:Float = Conductor.songPosition;
		if(Conductor.songPosition >= 0)
		{
			// 判定补偿: 按压发生在本帧内的某个时刻, 判定时间回扣本帧时长的一半(按回放速率换算成歌曲时间)
			// (60fps 稳态 -8.3ms; 掉帧 33ms 时 -16.7ms, 把采样误差上限从整帧降到半帧)
			var comp:Float = ClientPrefs.data.judgeCompensation ? FlxG.elapsed * 500 * playbackRate : 0;
			Conductor.songPosition = FlxG.sound.music.time - comp;
		}

		// obtain notes that the player can hit
		// B8: 单遍扫描维护最优两枚(替代 filter 造数组+闭包 再 sort), 排序规则与 sortHitNotes 一致
		var best:Note = null;
		var second:Note = null;
		var noteMembers:Array<Note> = notes.members;
		for (i in 0...noteMembers.length)
		{
			var n:Note = noteMembers[i];
			if (n == null || n.isSustainNote || n.noteData != key) continue;
			if (strumsBlocked[n.noteData] || !n.canBeHit || !n.mustPress || n.tooLate || n.wasGoodHit || n.blockHit) continue;

			if (best == null || notePrecedes(n, best))
			{
				second = best;
				best = n;
			}
			else if (second == null || notePrecedes(n, second))
			{
				second = n;
			}
		}

		var shouldMiss:Bool = !ClientPrefs.data.ghostTapping;

		if (best != null) {
			var funnyNote:Note = best; // front note

			if (second != null) {
				var doubleNote:Note = second;

				if (doubleNote.noteData == funnyNote.noteData) {
					// if the note has a 0ms distance (is on top of the current note), kill it
					if (Math.abs(doubleNote.strumTime - funnyNote.strumTime) < 1.0)
						invalidateNote(doubleNote);
					else if (doubleNote.strumTime < funnyNote.strumTime)
					{
						// replace the note if its ahead of time (or at least ensure "doubleNote" is ahead)
						funnyNote = doubleNote;
					}
				}
			}
			goodNoteHit(funnyNote);
		}
		else if(shouldMiss)
		{
			callOnScripts('onGhostTap', [key]);
			noteMissPress(key);
		}

		// Needed for the  "Just the Two of Us" achievement.
		//									- Shadow Mario
		if(!keysPressed.contains(key)) keysPressed.push(key);

		//more accurate hit time for the ratings? part 2 (Now that the calculations are done, go back to the time it was before for not causing a note stutter)
		Conductor.songPosition = lastTime;

		var spr:StrumNote = playerStrums.members[key];
		if(strumsBlocked[key] != true && spr != null && spr.animation.curAnim.name != 'confirm')
		{
			spr.playAnim('pressed');
			spr.resetAnim = 0;
		}
		callOnScripts('onKeyPress', [key]);
	}

	public static function sortHitNotes(a:Note, b:Note):Int
	{
		if (a.lowPriority && !b.lowPriority)
			return 1;
		else if (!a.lowPriority && b.lowPriority)
			return -1;

		return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
	}

	// B8: 与 sortHitNotes 同规则的"a 是否应排在 b 前"(非 lowPriority 优先, 再按 strumTime 升序)
	static function notePrecedes(a:Note, b:Note):Bool
	{
		if (a.lowPriority != b.lowPriority) return !a.lowPriority;
		return a.strumTime < b.strumTime;
	}

	private function onKeyRelease(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		if(!controls.controllerMode && key > -1) keyReleased(key);
	}

	private function keyReleased(key:Int)
	{
		if(cpuControlled || !startedCountdown || paused || key < 0 || key >= playerStrums.length) return;

		var ret:Dynamic = callOnScripts('onKeyReleasePre', [key]);
		if(ret == LuaUtils.Function_Stop) return;

		var spr:StrumNote = playerStrums.members[key];
		if(spr != null)
		{
			spr.playAnim('static');
			spr.resetAnim = 0;
		}
		callOnScripts('onKeyRelease', [key]);
	}

	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int
	{
		if(key != NONE)
		{
			for (i in 0...arr.length)
			{
				var note:Array<FlxKey> = Controls.instance.keyboardBinds[arr[i]];
				for (noteKey in note)
					if(key == noteKey)
						return i;
			}
		}
		return -1;
	}

	// Hold notes
	// B4: 定长状态数组(类字段复用, 免每帧 3 个数组分配) + 布尔聚合替代 contains(true)
	var holdStates:Array<Bool> = [false, false, false, false];
	var pressStates:Array<Bool> = [false, false, false, false];
	var releaseStates:Array<Bool> = [false, false, false, false];

	private function keysCheck():Void
	{
		// HOLDING
		var anyHeld:Bool = false;
		var anyPressed:Bool = false;
		var anyReleased:Bool = false;
		for (i in 0...keysArray.length)
		{
			var key:String = keysArray[i];
			holdStates[i] = controls.pressed(key);
			if(holdStates[i]) anyHeld = true;
			if(controls.controllerMode)
			{
				pressStates[i] = controls.justPressed(key);
				releaseStates[i] = controls.justReleased(key);
				if(pressStates[i]) anyPressed = true;
				if(releaseStates[i]) anyReleased = true;
			}
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if(controls.controllerMode && anyPressed)
			for (i in 0...keysArray.length)
				if(pressStates[i] && strumsBlocked[i] != true)
					keyPressed(i);

		if (startedCountdown && !inCutscene && !boyfriend.stunned && generatedMusic)
		{
			if (notes.length > 0) {
				// 索引遍历替代迭代器(免每次迭代器对象分配), 空元素行为与原版一致
				var noteMembers:Array<Note> = notes.members;
				for (j in 0...noteMembers.length) {
					var n:Note = noteMembers[j];
					if (n == null) continue;
					var canHit:Bool = (!strumsBlocked[n.noteData] && n.canBeHit
						&& n.mustPress && !n.tooLate && !n.wasGoodHit && !n.blockHit);

					if (guitarHeroSustains)
						canHit = canHit && n.parent != null && n.parent.wasGoodHit;

					if (canHit && n.isSustainNote) {
						var released:Bool = !holdStates[n.noteData];

						if (!released)
							goodNoteHit(n);
					}
				}
			}

			if (!anyHeld || endingSong)
				playerDance();

			#if ACHIEVEMENTS_ALLOWED
			else checkForAchievement(['oversinging']);
			#end
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if((controls.controllerMode || strumsBlocked.contains(true)) && anyReleased)
			for (i in 0...keysArray.length)
				if(releaseStates[i] || strumsBlocked[i] == true)
					keyReleased(i);
	}

	function noteMiss(daNote:Note):Void { //You didn't hit the key and let it go offscreen, also used by Hurt Notes
		//Dupe note remove
		notes.forEachAlive(function(note:Note) {
			if (daNote != note && daNote.mustPress && daNote.noteData == note.noteData && daNote.isSustainNote == note.isSustainNote && Math.abs(daNote.strumTime - note.strumTime) < 1)
				invalidateNote(note);
		});

		noteMissCommon(daNote.noteData, daNote);
		var result:Dynamic = callOnLuas('noteMiss', [notes.members.indexOf(daNote), daNote.noteData, daNote.noteType, daNote.isSustainNote]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('noteMiss', [daNote]);
	}

	function noteMissPress(direction:Int = 1):Void //You pressed a key when there was no notes to press for this key
	{
		if(ClientPrefs.data.ghostTapping) return; //fuck it

		noteMissCommon(direction);
		FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
		callOnScripts('noteMissPress', [direction]);
	}

	function noteMissCommon(direction:Int, note:Note = null)
	{
		if (!cpuControlled) backend.PerfProbe.onJudge(0, true);	// 判定直方图: miss 计数

		// 图标挤压: miss 静止(lua noteMiss); 玩家低血量(<20%)不静止, 挤压继续
		if (health * 50 >= 20)
		{
			iconIsSquashing[0] = false;
			iconIsSquashing[1] = false;
			iconIsMissed = true;
			iconSquashT[0] = 0;
			iconSquashT[1] = 0;
			iconRestOffset[0] = 0;
			iconRestOffset[1] = 0;
			iconCurRestOffset[0] = 0;
			iconCurRestOffset[1] = 0;
			resetIconsSquash();
		}
		// score and data
		var subtract:Float = 0.05;
		if(note != null) subtract = note.missHealth;

		// GUITAR HERO SUSTAIN CHECK LOL!!!!
		if (note != null && guitarHeroSustains && note.parent == null) {
			if(note.tail.length > 0) {
				note.alpha = 0.35;
				for(childNote in note.tail) {
					childNote.alpha = note.alpha;
					childNote.missed = true;
					childNote.canBeHit = false;
					childNote.ignoreNote = true;
					childNote.tooLate = true;
				}
				note.missed = true;
				note.canBeHit = false;

				//subtract += 0.385; // you take more damage if playing with this gameplay changer enabled.
				// i mean its fair :p -Crow
				subtract *= note.tail.length + 1;
				// i think it would be fair if damage multiplied based on how long the sustain is -Tahir
			}

			if (note.missed)
				return;
		}
		if (note != null && guitarHeroSustains && note.parent != null && note.isSustainNote) {
			if (note.missed)
				return;

			var parentNote:Note = note.parent;
			if (parentNote.wasGoodHit && parentNote.tail.length > 0) {
				for (child in parentNote.tail) if (child != note) {
					child.missed = true;
					child.canBeHit = false;
					child.ignoreNote = true;
					child.tooLate = true;
				}
			}
		}

		if(instakillOnMiss)
		{
			vocals.volume = 0;
			opponentVocals.volume = 0;
			doDeathCheck(true);
		}

		var lastCombo:Int = combo;
		combo = 0;

		health -= subtract * healthLoss;
		if(!practiceMode) songScore -= 10;
		if(!endingSong) songMisses++;
		totalPlayed++;
		RecalculateRating(true);

		// play character anims
		var char:Character = boyfriend;
		if((note != null && note.gfNote) || (SONG.notes[curSection] != null && SONG.notes[curSection].gfSection)) char = gf;

		if(char != null && (note == null || !note.noMissAnimation) && char.hasMissAnimations)
		{
			var suffix:String = '';
			if(note != null) suffix = note.animSuffix;

			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, direction)))] + 'miss' + suffix;
			char.playAnim(animToPlay, true);

			if(char != gf && lastCombo > 5 && gf != null && gf.animOffsets.exists('sad'))
			{
				gf.playAnim('sad');
				gf.specialAnim = true;
			}
		}
		vocals.volume = 0;
	}

	function opponentNoteHit(note:Note):Void
	{
		var result:Dynamic = callOnLuas('opponentNoteHitPre', [notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('opponentNoteHitPre', [note]);

		if (songName != 'tutorial')
			camZooming = true;

		if(note.noteType == 'Hey!' && dad.animOffsets.exists('hey')) {
			dad.playAnim('hey', true);
			dad.specialAnim = true;
			dad.heyTimer = 0.6;
		} else if(!note.noAnimation) {
			var altAnim:String = note.animSuffix;

			if (SONG.notes[curSection] != null)
				if (SONG.notes[curSection].altAnim && !SONG.notes[curSection].gfSection)
					altAnim = '-alt';

			var char:Character = dad;
			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))] + altAnim;
			if(note.gfNote) char = gf;

			if(char != null)
			{
				char.playAnim(animToPlay, true);
				char.holdTimer = 0;
			}
		}

		if(opponentVocals.length <= 0) vocals.volume = 1;
		strumPlayAnim(true, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
		note.hitByOpponent = true;
		
		var result:Dynamic = callOnLuas('opponentNoteHit', [notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('opponentNoteHit', [note]);

		if (!note.isSustainNote) invalidateNote(note);
	}

	public function goodNoteHit(note:Note):Void
	{
		if(note.wasGoodHit) return;
		if(cpuControlled && note.ignoreNote) return;

		// 图标挤压: 接住箭头解除 miss 静止(lua goodNoteHit)
		if (iconIsMissed) { iconIsMissed = false; startIconSquashByHp(0); startIconSquashByHp(1); }

		var isSus:Bool = note.isSustainNote; //GET OUT OF MY HEAD, GET OUT OF MY HEAD, GET OUT OF MY HEAD
		var leData:Int = Math.round(Math.abs(note.noteData));
		var leType:String = note.noteType;

		var result:Dynamic = callOnLuas('goodNoteHitPre', [notes.members.indexOf(note), leData, leType, isSus]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('goodNoteHitPre', [note]);

		note.wasGoodHit = true;

		if (ClientPrefs.data.hitsoundVolume > 0 && !note.hitsoundDisabled)
			FlxG.sound.play(Paths.sound(note.hitsound), ClientPrefs.data.hitsoundVolume);

		if(note.hitCausesMiss) {
			if(!note.noMissAnimation) {
				switch(note.noteType) {
					case 'Hurt Note': //Hurt note
						if(boyfriend.animOffsets.exists('hurt')) {
							boyfriend.playAnim('hurt', true);
							boyfriend.specialAnim = true;
						}
				}
			}

			noteMiss(note);
			if(!note.noteSplashData.disabled && !note.isSustainNote) spawnNoteSplashOnNote(note);
			if(!note.isSustainNote) invalidateNote(note);
			return;
		}

		if(!note.noAnimation) {
			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))];

			var char:Character = boyfriend;
			var animCheck:String = 'hey';
			if(note.gfNote)
			{
				char = gf;
				animCheck = 'cheer';
			}

			if(char != null)
			{
				char.playAnim(animToPlay + note.animSuffix, true);
				char.holdTimer = 0;

				if(note.noteType == 'Hey!') {
					if(char.animOffsets.exists(animCheck)) {
						char.playAnim(animCheck, true);
						char.specialAnim = true;
						char.heyTimer = 0.6;
					}
				}
			}
		}

		if(!cpuControlled)
		{
			var spr = playerStrums.members[note.noteData];
			if(spr != null) spr.playAnim('confirm', true);
		}
		else strumPlayAnim(false, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
		vocals.volume = 1;

		if (!note.isSustainNote)
		{
			combo++;
			if(combo > 9999) combo = 9999;
			popUpScore(note);
		}
		var gainHealth:Bool = true; // prevent health gain, *if* sustains are treated as a singular note
		if (guitarHeroSustains && note.isSustainNote) gainHealth = false;
		if (gainHealth) health += note.hitHealth * healthGain;

		var result:Dynamic = callOnLuas('goodNoteHit', [notes.members.indexOf(note), leData, leType, isSus]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('goodNoteHit', [note]);

		if(!note.isSustainNote) invalidateNote(note);
	}

	#if VIDEOS_ALLOWED
	public function removeVideoSprite(video:FunkinVideoSprite):Void {
		if(members.contains(video))
			remove(video, true);
		else {
			forEachOfType(FlxSpriteGroup, function(group:FlxSpriteGroup){
				if(group.members.contains(video))
					group.remove(video, true);
			});
		}
		video.altDestroy();
	}
	#end

	public function invalidateNote(note:Note):Void {
		note.kill();
		notes.remove(note, true);
		note.recycle();	// C1: 回收进对象池(替代 destroy, 免每音符堆分配)
	}

	public function spawnNoteSplashOnNote(note:Note) {
		if(note != null) {
			var strum:StrumNote = playerStrums.members[note.noteData];
			if(strum != null)
				spawnNoteSplash(strum.x, strum.y, note.noteData, note);
		}
	}

	public function spawnNoteSplash(x:Float, y:Float, data:Int, ?note:Note = null) {
		var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
		splash.setupNoteSplash(x, y, data, note);
		grpNoteSplashes.add(splash);
	}

	override function destroy() {
		// C1: 状态销毁前把剩余音符回收进池(旧实现随 group 一起 destroy), 下一首歌/重开可直接复用
		if (notes != null)
		{
			while (notes.length > 0)
			{
				var daNote:Note = notes.members[0];
				daNote.active = false;
				daNote.visible = false;
				notes.remove(daNote, true);
				daNote.recycle();
			}
		}
		if (unspawnNotes != null)
		{
			while (unspawnNotes.length > 0)
			{
				var daNote:Note = unspawnNotes.pop();
				if (daNote != null) daNote.recycle();
			}
		}
		// C1 诊断: 一趟打歌结束后新建/复用计数, 用于确认对象池生效
		backend.PerfProbe.log('[池] 音符 新建=' + Note.createdCount + ' 复用=' + Note.reusedCount + ' 池=' + Note.pool.length);

		#if LUA_ALLOWED
		for (lua in luaArray)
		{
			lua.call('onDestroy', []);
			lua.stop();
		}
		luaArray = [];
		FunkinLua.customFunctions.clear();
		#end

		#if HSCRIPT_ALLOWED
		for (script in hscriptArray)
			if(script != null)
			{
				script.call('onDestroy');
				script.destroy();
			}

		while (hscriptArray.length > 0)
			hscriptArray.pop();
		#end

		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
		FlxG.animationTimeScale = 1;
		#if FLX_PITCH FlxG.sound.music.pitch = 1; #end
		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();
		// 音频对象挂在全局 FlxG.sound.list 上, 不随状态销毁 —— 显式释放(PCM/AL缓冲)
		if (vocals != null) { FlxG.sound.list.remove(vocals); vocals.destroy(); }
		if (opponentVocals != null) { FlxG.sound.list.remove(opponentVocals); opponentVocals.destroy(); }
		if (inst != null) { FlxG.sound.list.remove(inst); inst.destroy(); }
		instance = null;
		super.destroy();
	}

	var lastStepHit:Int = -1;
	var resyncCount:Int = 0;	// 诊断: resync 次数写入 perf_log, 用来验证"人声卡"是否消失
	var vocalsFollowTimer:Float = 0;						// 人声跟随: 检查间隔计时
	var vocalsFixCount:Int = 0;								// 修正次数(上限 16, 只写前 8 次日志)
	static inline var VOCALS_FOLLOW_TOL:Float = 35;			// 人声与伴奏偏差超过 35ms 才 seek
	override function stepHit()
	{
		if (SONG.needsVoices && FlxG.sound.music.time >= -ClientPrefs.data.noteOffset)
		{
			var timeSub:Float = Conductor.songPosition - Conductor.offset;
			// 阈值 20ms → 120ms: 20ms 判据与 update 的 25ms 死区重叠, 实测 |drift| 长期贴着 15~25ms,
			// 等于每 step 都可能判重同步; 而 resyncVocals() = vocals.pause()+time+play(), 每次都会打断人声流
			// (每秒 1 次以上即可闻"卡卡的")。人耳对音画不同步可容忍 ~100ms, 对音频中断零容忍,
			// 因此只在真正漂移时修, 放宽到 120ms。
			var syncTime:Float = Math.max(120, 120 * playbackRate);
			if (Math.abs(FlxG.sound.music.time - timeSub) > syncTime ||
			(vocals.length > 0 && Math.abs(vocals.time - timeSub) > syncTime) ||
			(opponentVocals.length > 0 && Math.abs(opponentVocals.time - timeSub) > syncTime))
			{
				resyncVocals();
			}
		}

		super.stepHit();

		if(curStep == lastStepHit) {
			return;
		}

		lastStepHit = curStep;
		setOnScripts('curStep', curStep);
		callOnScripts('onStepHit');
	}

	var lastBeatHit:Int = -1;

	override function beatHit()
	{
		if(lastBeatHit >= curBeat) {
			//trace('BEAT HIT: ' + curBeat + ', LAST HIT: ' + lastBeatHit);
			return;
		}

		if (generatedMusic)
			notes.sort(FlxSort.byY, ClientPrefs.data.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);

		// 图标挤压: 每拍按各自血量起振(玩家/对手互补档位; miss 静止期间跳过; 原版 beat 弹跳已替代)
		if (!iconIsMissed) { startIconSquashByHp(0); startIconSquashByHp(1); }

		characterBopper(curBeat);

		super.beatHit();
		lastBeatHit = curBeat;

		setOnScripts('curBeat', curBeat);
		callOnScripts('onBeatHit');
	}

	public function characterBopper(beat:Int):Void
	{
		if (gf != null && beat % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && !gf.getAnimationName().startsWith('sing') && !gf.stunned)
			gf.dance();
		if (boyfriend != null && beat % boyfriend.danceEveryNumBeats == 0 && !boyfriend.getAnimationName().startsWith('sing') && !boyfriend.stunned)
			boyfriend.dance();
		if (dad != null && beat % dad.danceEveryNumBeats == 0 && !dad.getAnimationName().startsWith('sing') && !dad.stunned)
			dad.dance();
	}

	public function playerDance():Void
	{
		var anim:String = boyfriend.getAnimationName();
		if(boyfriend.holdTimer > Conductor.stepCrochet * (0.0011 #if FLX_PITCH / FlxG.sound.music.pitch #end) * boyfriend.singDuration && anim.startsWith('sing') && !anim.endsWith('miss'))
			boyfriend.dance();
	}

	override function sectionHit()
	{
		if (SONG.notes[curSection] != null)
		{
			if (generatedMusic && !endingSong && !isCameraOnForcedPos)
				moveCameraSection();

			if (camZooming && FlxG.camera.zoom < 1.35 && ClientPrefs.data.camZooms)
			{
				FlxG.camera.zoom += 0.015 * camZoomingMult;
				camHUD.zoom += 0.03 * camZoomingMult;
			}

			if (SONG.notes[curSection].changeBPM)
			{
				Conductor.bpm = SONG.notes[curSection].bpm;
				setOnScripts('curBpm', Conductor.bpm);
				setOnScripts('crochet', Conductor.crochet);
				setOnScripts('stepCrochet', Conductor.stepCrochet);
			}
			setOnScripts('mustHitSection', SONG.notes[curSection].mustHitSection);
			setOnScripts('altAnim', SONG.notes[curSection].altAnim);
			setOnScripts('gfSection', SONG.notes[curSection].gfSection);
		}
		super.sectionHit();

		setOnScripts('curSection', curSection);
		callOnScripts('onSectionHit');
	}

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	public function noteScriptExists(relPath:String):Bool
	{
		#if MODS_ALLOWED
		var p:String = Paths.modFolders(relPath);
		if (!FileSystem.exists(p)) p = Paths.getSharedPath(relPath);
		return FileSystem.exists(p);
		#else
		return OpenFlAssets.exists(Paths.getSharedPath(relPath));
		#end
	}
	#end

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String)
	{
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if(!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getSharedPath(luaFile);

		if(FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getSharedPath(luaFile);
		if(OpenFlAssets.exists(luaToLoad))
		#end
		{
			for (script in luaArray)
				if(script.scriptName == luaToLoad) return false;

			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}
	#end

	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String)
	{
		#if MODS_ALLOWED
		var scriptToLoad:String = Paths.modFolders(scriptFile);
		if(!FileSystem.exists(scriptToLoad))
			scriptToLoad = Paths.getSharedPath(scriptFile);
		#else
		var scriptToLoad:String = Paths.getSharedPath(scriptFile);
		#end

		if(FileSystem.exists(scriptToLoad))
		{
			if (SScript.global.exists(scriptToLoad)) return false;

			initHScript(scriptToLoad);
			return true;
		}
		return false;
	}

	public function initHScript(file:String)
	{
		try
		{
			var newScript:HScript = new HScript(null, file);
			if(newScript.parsingException != null)
			{
				addTextToDebug('ERROR ON LOADING: ${newScript.parsingException.message}', FlxColor.RED);
				newScript.destroy();
				return;
			}

			hscriptArray.push(newScript);
			if(newScript.exists('onCreate'))
			{
				var callValue = newScript.call('onCreate');
				if(!callValue.succeeded)
				{
					for (e in callValue.exceptions)
					{
						if (e != null)
						{
							var len:Int = e.message.indexOf('\n') + 1;
							if(len <= 0) len = e.message.length;
								addTextToDebug('ERROR ($file: onCreate) - ${e.message.substr(0, len)}', FlxColor.RED);
						}
					}

					newScript.destroy();
					hscriptArray.remove(newScript);
					trace('failed to initialize tea interp!!! ($file)');
				}
				else trace('initialized tea interp successfully: $file');
			}

		}
		catch(e)
		{
			var len:Int = e.message.indexOf('\n') + 1;
			if(len <= 0) len = e.message.length;
			addTextToDebug('ERROR - ' + e.message.substr(0, len), FlxColor.RED);
			var newScript:HScript = cast (SScript.global.get(file), HScript);
			if(newScript != null)
			{
				newScript.destroy();
				hscriptArray.remove(newScript);
			}
		}
	}
	#end

	public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		// B2: 无脚本时零开销短路(每帧 2 次以上的调用原本仍会分配 3 个默认数组)
		if (hasNoScripts()) return returnVal;
		if(args == null) args = [];
		if(exclusions == null) exclusions = EMPTY_EXCLUSIONS;
		if(excludeValues == null) excludeValues = [LuaUtils.Function_Continue];

		var result:Dynamic = callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
		if(result == null || excludeValues.contains(result)) result = callOnHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);
		return result;
	}

	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		#if LUA_ALLOWED
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [LuaUtils.Function_Continue];

		var arr:Array<FunkinLua> = [];
		for (script in luaArray)
		{
			if(script.closed)
			{
				arr.push(script);
				continue;
			}

			if(exclusions.contains(script.scriptName))
				continue;

			var myValue:Dynamic = script.call(funcToCall, args);
			if((myValue == LuaUtils.Function_StopLua || myValue == LuaUtils.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
			{
				returnVal = myValue;
				break;
			}

			if(myValue != null && !excludeValues.contains(myValue))
				returnVal = myValue;

			if(script.closed) arr.push(script);
		}

		if(arr.length > 0)
			for (script in arr)
				luaArray.remove(script);
		#end
		return returnVal;
	}

	public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;

		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = new Array();
		if(excludeValues == null) excludeValues = new Array();
		excludeValues.push(LuaUtils.Function_Continue);

		var len:Int = hscriptArray.length;
		if (len < 1)
			return returnVal;
		for(i in 0...len) {
			var script:HScript = hscriptArray[i];
			if(script == null || !script.exists(funcToCall) || exclusions.contains(script.origin))
				continue;

			var myValue:Dynamic = null;
			try {
				var callValue = script.call(funcToCall, args);
				if(!callValue.succeeded)
				{
					var e = callValue.exceptions[0];
					if(e != null)
					{
						var len:Int = e.message.indexOf('\n') + 1;
						if(len <= 0) len = e.message.length;
						addTextToDebug('ERROR (${callValue.calledFunction}) - ' + e.message.substr(0, len), FlxColor.RED);
					}
				}
				else
				{
					myValue = callValue.returnValue;
					if((myValue == LuaUtils.Function_StopHScript || myValue == LuaUtils.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
					{
						returnVal = myValue;
						break;
					}

					if(myValue != null && !excludeValues.contains(myValue))
						returnVal = myValue;
				}
			}
		}
		#end

		return returnVal;
	}

	// B2: 共享空排除表(exclusions 在全部调用链里只读, 不含 mutate), 免每帧反复 new []
	static var EMPTY_EXCLUSIONS:Array<String> = [];

	// B2: 是否无任何脚本(条件编译兼容只开 LUA/HSCRIPT 其一的配置)
	function hasNoScripts():Bool
	{
		#if LUA_ALLOWED
			#if HSCRIPT_ALLOWED
			return luaArray.length == 0 && hscriptArray.length == 0;
			#else
			return luaArray.length == 0;
			#end
		#else
			#if HSCRIPT_ALLOWED
			return hscriptArray.length == 0;
			#else
			return true;
			#end
		#end
	}

	public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		// B2: 无脚本时零开销短路(每帧 5 次调用, 无脚本时原本仍各分配一次数组)
		if (hasNoScripts()) return;
		if(exclusions == null) exclusions = EMPTY_EXCLUSIONS;
		setOnLuas(variable, arg, exclusions);
		setOnHScript(variable, arg, exclusions);
	}

	public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if LUA_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in luaArray) {
			if(exclusions.contains(script.scriptName))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in hscriptArray) {
			if(exclusions.contains(script.origin))
				continue;

			if(!instancesExclude.contains(variable))
				instancesExclude.push(variable);
			script.set(variable, arg);
		}
		#end
	}

	function strumPlayAnim(isDad:Bool, id:Int, time:Float) {
		var spr:StrumNote = null;
		if(isDad) {
			spr = opponentStrums.members[id];
		} else {
			spr = playerStrums.members[id];
		}

		if(spr != null) {
			spr.playAnim('confirm', true);
			spr.resetAnim = time;
		}
	}

	public var ratingName:String = '?';
	public var ratingPercent:Float;
	public var ratingFC:String;
	public function RecalculateRating(badHit:Bool = false) {
		setOnScripts('score', songScore);
		setOnScripts('misses', songMisses);
		setOnScripts('hits', songHits);
		setOnScripts('combo', combo);

		var ret:Dynamic = callOnScripts('onRecalculateRating', null, true);
		if(ret != LuaUtils.Function_Stop)
		{
			ratingName = '?';
			if(totalPlayed != 0) //Prevent divide by 0
			{
				// Rating Percent
				ratingPercent = Math.min(1, Math.max(0, totalNotesHit / totalPlayed));
				//trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

				// Rating Name
				ratingName = ratingStuff[ratingStuff.length-1][0]; //Uses last string
				if(ratingPercent < 1)
					for (i in 0...ratingStuff.length-1)
						if(ratingPercent < ratingStuff[i][1])
						{
							ratingName = ratingStuff[i][0];
							break;
						}
			}
			fullComboFunction();
		}
		updateScore(badHit); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce
		setOnScripts('rating', ratingPercent);
		setOnScripts('ratingName', ratingName);
		setOnScripts('ratingFC', ratingFC);
	}

	#if ACHIEVEMENTS_ALLOWED
	private function checkForAchievement(achievesToCheck:Array<String> = null)
	{
		if(chartingMode) return;

		var usedPractice:Bool = (ClientPrefs.getGameplaySetting('practice') || ClientPrefs.getGameplaySetting('botplay'));
		if(cpuControlled) return;

		for (name in achievesToCheck) {
			if(!Achievements.exists(name)) continue;

			var unlock:Bool = false;
			if (name != WeekData.getWeekFileName() + '_nomiss') // common achievements
			{
				switch(name)
				{
					case 'ur_bad':
						unlock = (ratingPercent < 0.2 && !practiceMode);

					case 'ur_good':
						unlock = (ratingPercent >= 1 && !usedPractice);

					case 'oversinging':
						unlock = (boyfriend.holdTimer >= 10 && !usedPractice);

					case 'hype':
						unlock = (!boyfriendIdled && !usedPractice);

					case 'two_keys':
						unlock = (!usedPractice && keysPressed.length <= 2);

					case 'toastie':
						unlock = (!ClientPrefs.data.cacheOnGPU && !ClientPrefs.data.shaders && ClientPrefs.data.lowQuality && !ClientPrefs.data.antialiasing);

					case 'debugger':
						unlock = (songName == 'test' && !usedPractice);
				}
			}
			else // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
			{
				if(isStoryMode && campaignMisses + songMisses < 1 && Difficulty.getString().toUpperCase() == 'HARD'
					&& storyPlaylist.length <= 1 && !changedDifficulty && !usedPractice)
					unlock = true;
			}

			if(unlock) Achievements.unlock(name);
		}
	}
	#end

	#if (!flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	public function createRuntimeShader(name:String):FlxRuntimeShader
	{
		if(!ClientPrefs.data.shaders) return new FlxRuntimeShader();

		#if (!flash && MODS_ALLOWED && sys)
		if(!runtimeShaders.exists(name) && !initLuaShader(name))
		{
			FlxG.log.warn('Shader $name is missing!');
			return new FlxRuntimeShader();
		}

		var arr:Array<String> = runtimeShaders.get(name);
		return new FlxRuntimeShader(arr[0], arr[1]);
		#else
		FlxG.log.warn("Platform unsupported for Runtime Shaders!");
		return null;
		#end
	}

	public function initLuaShader(name:String, ?glslVersion:Int = 120)
	{
		if(!ClientPrefs.data.shaders) return false;

		#if (MODS_ALLOWED && !flash && sys)
		if(runtimeShaders.exists(name))
		{
			FlxG.log.warn('Shader $name was already initialized!');
			return true;
		}

		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'shaders/'))
		{
			var frag:String = folder + name + '.frag';
			var vert:String = folder + name + '.vert';
			var found:Bool = false;
			if(FileSystem.exists(frag))
			{
				frag = File.getContent(frag);
				found = true;
			}
			else frag = null;

			if(FileSystem.exists(vert))
			{
				vert = File.getContent(vert);
				found = true;
			}
			else vert = null;

			if(found)
			{
				runtimeShaders.set(name, [frag, vert]);
				//trace('Found shader $name!');
				return true;
			}
		}
			#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
			addTextToDebug('Missing shader $name .frag AND .vert files!', FlxColor.RED);
			#else
			FlxG.log.warn('Missing shader $name .frag AND .vert files!');
			#end
		#else
		FlxG.log.warn('This platform doesn\'t support Runtime Shaders!');
		#end
		return false;
	}
	#end
}
