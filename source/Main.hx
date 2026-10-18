package;

import debug.FPSCounter;
import flixel.graphics.FlxGraphic;
import flixel.FlxGame;
import flixel.FlxState;
import haxe.io.Path;
import openfl.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import lime.app.Application;
#if mobile
import mobile.backend.MobileUtil;
#end
import states.TitleState;
#if linux
import lime.graphics.Image;
#end
// crash handler stuff
#if CRASH_HANDLER
import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.io.Path;
#end

#if linux
@:cppInclude('./external/gamemode_client.h')
@:cppFileCode('
	#define GAMEMODE_AUTO
')
#end
class Main extends Sprite
{
	var game = {
		width: 1280, // WINDOW width
		height: 720, // WINDOW height
		initialState: TitleState, // initial game state
		zoom: -1.0, // game state bounds
		framerate: 60, // default framerate
		skipSplash: true, // if the default flixel splash screen should be skipped
		startFullscreen: false // if the game should start at fullscreen mode
	};

	public static var fpsVar:FPSCounter;

	// You can pretty much ignore everything from here on - your code should go in your states.

	public static function main():Void
	{
		Lib.current.addChild(new Main());
	}

	public function new()
	{
		super();

		#if cpp
		// GC 调优: 让 GC 保留 30% 空闲堆(默认约12.5%), 降低回收频率, 用少量内存换流畅
		cpp.vm.Gc.setTargetFreeSpacePercentage(30);
		// 最小空闲堆 16MB: 攒够更多垃圾才回收一次, 大幅减少回收次数(一首歌从数百次降到两位数)
		cpp.vm.Gc.setMinimumFreeSpace(16 * 1024 * 1024);
		#end

        #if mobile
		StorageSystem.getPermissions();
		var __dataDir:String = StorageSystem.getDirectory();
		try
		{
			if (!FileSystem.exists(__dataDir)) FileSystem.createDirectory(__dataDir);
			Sys.setCwd(__dataDir);
		}
		catch (e:Dynamic)
		{
			PopUp.showAlert("Storage Error", "Cannot access storage. Please grant permission and restart the game.", "OK");
			lime.system.System.exit(0);
		}
		FlxG.signals.preUpdate.add(function()
		{
			MobileUtil.updateInputMethod();
		});

		// 性能探测点: 更新/绘制分段计时 + 尖帧/GC/状态切换调试日志
		backend.PerfProbe.init();
		FlxG.signals.preUpdate.add(function() { backend.PerfProbe.onPreUpdate(); });
		FlxG.signals.postUpdate.add(function() { backend.PerfProbe.onPostUpdate(); });
		FlxG.signals.preDraw.add(function() { backend.PerfProbe.onPreDraw(); });
		FlxG.signals.postDraw.add(function() { backend.PerfProbe.onPostDraw(); });
		#end

		if (stage != null)
		{
			init();
		}
		else
		{
			addEventListener(Event.ADDED_TO_STAGE, init);
		}
	}

	private function init(?E:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
		{
			removeEventListener(Event.ADDED_TO_STAGE, init);
		}

		setupGame();
	}

	private function setupGame():Void
	{
		#if desktop
		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;

		if (game.zoom == -1.0)
		{
			var ratioX:Float = stageWidth / game.width;
			var ratioY:Float = stageHeight / game.height;
			game.zoom = Math.min(ratioX, ratioY);
			game.width = Math.ceil(stageWidth / game.zoom);
			game.height = Math.ceil(stageHeight / game.zoom);
		}
		#end

		#if LUA_ALLOWED Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(psychlua.CallbackHandler.call)); #end
		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end
		addChild(new FlxGame(game.width, game.height, game.initialState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate,
			game.skipSplash, game.startFullscreen));

		fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
		addChild(fpsVar);
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		if (fpsVar != null)
		{
			fpsVar.visible = ClientPrefs.data.showFPS;
		}

		#if linux
		var icon = Image.fromFile("icon.png");
		Lib.current.stage.window.setIcon(icon);
		#end

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end

		#if android
		FlxG.android.preventDefaultKeys = [BACK];
		#end

		#if CRASH_HANDLER
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);
		#end

		#if DISCORD_ALLOWED
		DiscordClient.prepare();
		#end

		// shader coords fix
		FlxG.signals.gameResized.add(function(w, h)
		{
			if (FlxG.cameras != null)
			{
				for (cam in FlxG.cameras.list)
				{
					if (cam != null && cam.filters != null)
						resetSpriteCache(cam.flashSprite);
				}
			}

			if (FlxG.game != null)
				resetSpriteCache(FlxG.game);
		});
	}

	static function resetSpriteCache(sprite:Sprite):Void
	{
		@:privateAccess {
			sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
		}
	}

	// Code was entirely made by sqirra-rng for their fnf engine named "Izzy Engine", big props to them!!!
	// very cool person for real they don't get enough credit for their work
	#if CRASH_HANDLER
	function onCrash(e:UncaughtErrorEvent):Void
	{
		var errMsg:String = "";
		var path:String;
		var callStack:Array<StackItem> = CallStack.exceptionStack(true);
		var dateNow:String = Date.now().toString();

		dateNow = dateNow.replace(" ", "_");
		dateNow = dateNow.replace(":", "'");

		path = "crash/" + "NekoEngine_" + dateNow + ".txt";

		var errorStr:String = Std.string(e.error);
		var firstStack:String = '';
		var stackStr:String = '';

		for (stackItem in callStack)
		{
			switch (stackItem)
			{
				case FilePos(si, file, line, column):
					var prefix:String = '';
					if (si != null)
						prefix = Std.string(si) + " / ";
					var lineStr:String = "  at " + prefix + file + " (line " + line + ")";
					var lineStr:String = "  at " + prefix + file + " (line " + line + ")";
					stackStr += lineStr + "\n";
					if (firstStack == '') firstStack = prefix + file + " (line " + line + ")";
				default:
					Sys.println(stackItem);
			}
		}

		errMsg += "====== NekoEngine 崩溃报告 / Crash Report ======\n\n";
		errMsg += "时间 / Time: " + Date.now().toString() + "\n";
		errMsg += "版本 / Version: NekoEngine v0.01 (based on Psych Engine 0.7.3 Mobile)\n";

		#if mobile
		// 设备信息(读系统属性, 失败则跳过)
		var devModel:String = '';
		var devAndroid:String = '';
		try {
			var inp = sys.io.File.read("/system/build.prop", false);
			var line:String = "";
			while (true)
			{
				if (devModel == '' && StringTools.startsWith(line, "ro.product.model="))
					devModel = line.substr("ro.product.model=".length).trim();
				else if (devAndroid == '' && StringTools.startsWith(line, "ro.build.version.release="))
					devAndroid = line.substr("ro.build.version.release=".length).trim();
			}
			inp.close();
		} catch (devE:Dynamic) {}
		errMsg += "设备 / Device: " + (devModel != '' ? devModel : 'unknown');
		if (devAndroid != '') errMsg += " (Android " + devAndroid + ")";
		errMsg += "\n";
		#end

		try {
			errMsg += "当前界面 / Current State: " + Type.getClassName(Type.getClass(FlxG.state)) + "\n";
			if (FlxG.state.subState != null)
				errMsg += "子界面 / Substate: " + Type.getClassName(Type.getClass(FlxG.state.subState)) + "\n";
		} catch (stE:Dynamic) {}
		try {
			if (Main.fpsVar != null)
				errMsg += "帧数 / FPS: " + Main.fpsVar.currentFPS
					+ " | 内存 / Memory: " + flixel.util.FlxStringUtil.formatBytes(Main.fpsVar.memoryMegas) + "\n";
		} catch (fpsE:Dynamic) {}
		#if MODS_ALLOWED
		try {
			var enabledMods:Array<String> = [];
			for (m in Mods.parseList().enabled) enabledMods.push(m);
			if (enabledMods.length > 0)
				errMsg += "已启用Mod / Enabled Mods: " + enabledMods.join(', ') + "\n";
		} catch (modE:Dynamic) {}
		#end

		errMsg += "\n错误 / Error: " + errorStr + "\n";
		errMsg += "堆栈 / Stack:\n" + stackStr;

		errMsg += "\n---------- 中文说明 ----------\n";
		errMsg += "游戏遇到了严重错误，已经崩溃关闭。\n";
		errMsg += "本日志已保存，可发送给开发者帮助定位问题。\n";
		errMsg += "日志位置 / Log path: " + (#if mobile StorageSystem.getDirectory() + #end "crash/") + "\n";

		errMsg += "\n---------- English ----------\n";
		errMsg += "The game has encountered a fatal error and crashed.\n";
		errMsg += "This log has been saved — please send it to the developer to help fix the issue.\n";
		errMsg += "Report it on GitHub: https://github.com/MuXue-Ya/NekoEngine\n";
		errMsg += "\n> Crash Handler written by: sqirra-rng | Enhanced by NekoEngine";

		if (!FileSystem.exists(#if mobile StorageSystem.getDirectory() + #end "crash"))
			FileSystem.createDirectory(#if mobile StorageSystem.getDirectory() + #end "crash");

		File.saveContent(#if mobile StorageSystem.getDirectory() + #end path, errMsg + "\n");

		Sys.println(errMsg);
		Sys.println("Crash dump saved in " + Path.normalize(path));

		// 弹窗只显示简短摘要(完整内容在日志文件里)
		var shortMsg:String = "";
		shortMsg += "中文：游戏遇到严重错误，即将关闭。\n";
		if (firstStack != '') shortMsg += "错误 / Error: " + errorStr + "\n位置 / At: " + firstStack + "\n";
		else shortMsg += "错误 / Error: " + errorStr + "\n";
		shortMsg += "详细日志 / Full log:\n" + (#if mobile StorageSystem.getDirectory() + #end "crash/") + "\n\n";
		shortMsg += "English: A fatal error occurred. The game will close.\n";
		shortMsg += "See the log file above for full details.";

		#if mobile
		PopUp.showAlert("NekoEngine 崩溃 / Crash", shortMsg, "确定 / Close");
		#else
		Application.current.window.alert(shortMsg, "NekoEngine 崩溃 / Crash");
		#end
		#if DISCORD_ALLOWED
		DiscordClient.shutdown();
		#end
		Sys.exit(1);
	}
	#end
}
