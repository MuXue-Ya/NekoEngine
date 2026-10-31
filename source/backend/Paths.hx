package backend;

import flixel.graphics.frames.FlxFrame.FlxFrameAngle;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.FlxGraphic;
import flixel.math.FlxRect;

import openfl.display.BitmapData;
import openfl.display3D.textures.RectangleTexture;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import openfl.geom.Rectangle;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

#if ASTC_SUPPORT
import backend.astcsupport.openfl.display.ASTCBitmapData;
#end

import lime.utils.Assets;
import flash.media.Sound;

import haxe.Json;


#if MODS_ALLOWED
import backend.Mods;
#end

class Paths
{
	inline public static var SOUND_EXT = #if web "mp3" #else "ogg" #end;
	inline public static var VIDEO_EXT = "mp4";

	public static var pathCache:Map<String, String> = new Map();
	public static var fileExistsCache:Map<String, Bool> = new Map();

	public static function excludeAsset(key:String) {
		if (!dumpExclusions.contains(key))
			dumpExclusions.push(key);
	}

	public static var dumpExclusions:Array<String> = ['assets/shared/music/freakyMenu.$SOUND_EXT'];
	
	public static function clearUnusedMemory() {
		// clear non local assets in the tracked assets list
		for (key in currentTrackedAssets.keys()) {
			// if it is not currently contained within the used local assets
			if (!localTrackedAssets.exists(key) && !dumpExclusions.contains(key)) {
				var obj = currentTrackedAssets.get(key);
				@:privateAccess
				if (obj != null) {
					// remove the key from all cache maps
					FlxG.bitmap._cache.remove(key);
					openfl.Assets.cache.removeBitmapData(key);
					currentTrackedAssets.remove(key);

					// and get rid of the object
					obj.persist = false; // make sure the garbage collector actually clears it up
					obj.destroyOnNoUse = true;
					obj.destroy();
				}
			}
		}

		pathCache.clear();
		fileExistsCache.clear();

		// 注: 不再强制 System.gc() —— 本机实测单次 GC 0.4~1.1s(见 Main.hx 注释),
		// 每次切界面都白送一次长暂停; 改由 setMinimumFreeSpace(48MB) 按需自然触发
	}

	// ===== 引擎底层(阶段 L): 纹理驻留管家(显存预算 + LRU) =====
	// 依据(第五轮 perf_log): 曲2 打歌 rss 1.9~2.6GB, 其中 30 张 GPU 化 mod 图集是大头。
	// 而 Paths.cacheBitmap 所有图都是 persist=true / destroyOnNoUse=false → 只能等切状态才释放;
	// 一首 5 分钟的歌里, 换掉的角色图集 / 没再用过的舞台变体就一直白占显存。
	// 策略(保守): ① 只看 Paths 自己记账的图 ② 只动 >=4MB ③ useCount==0(sprite 没在用, 反射读, 读不到就不动)
	// ④ 至少 5s 没被请求 ⑤ 显存超过 texBudgetMB 才动手, 按"最久没用"顺序释放到预算以内 ⑥ 同一张图 90s 内不重复回收(防抖动)
	public static var texLastUseMs:Map<String, Float> = new Map();
	public static var texEvictedMs:Map<String, Float> = new Map();
	public static var texMinMB:Float = 4;
	public static var texIdleSec:Float = 5;				// 至少闲置这么久才允许回收
	public static var texBudgetMB:Float = 800;			// 显存预算(超过就按 LRU 释放)
	public static var texCooldownSec:Float = 90;		// 同一张图两次回收的最小间隔(防抖动)
	public static var texSweptMB:Float = 0;				// 累计回收(仅日志)
	public static var texSweepEnabled:Bool = true;
	static var texTickMs:Float = -100000;

	public static function texTouch(file:String):Void
	{
		texLastUseMs.set(file, haxe.Timer.stamp() * 1000);
	}

	// 返回一行日志(空串=没动作); 由 MusicBeatState.update 每帧调, 内部 5s 节流
	public static function texHousekeeping(nowMs:Float):String
	{
		#if (cpp && mobile)
		if (!texSweepEnabled) return '';
		if (nowMs - texTickMs < 5000) return '';
		texTickMs = nowMs;

		var gpuTotalMB:Float = 0;
		var keys:Array<String> = [];
		@:privateAccess
		for (k in FlxG.bitmap._cache.keys())
		{
			var g:FlxGraphic = FlxG.bitmap._cache.get(k);
			if (g == null || g.bitmap == null) continue;
			if (!g.bitmap.readable) gpuTotalMB += g.bitmap.width * g.bitmap.height * 4 / 1048576;
			keys.push(k);
		}
		if (gpuTotalMB <= texBudgetMB) return '';		// 没超预算: 什么都不做(不打搅画面)

		// 候选: 大图 + 有记账 + 闲置够久 + 没被 sprite 引用 + 不在冷却期, 按最近使用时间升序(最老先走)
		var cands:Array<{k:String, mb:Float, last:Float}> = [];
		for (k in keys)
		{
			var g:FlxGraphic = currentTrackedAssets.get(k);
			if (g == null || g.bitmap == null) continue;
			var mb:Float = g.bitmap.width * g.bitmap.height * 4 / 1048576;
			if (mb < texMinMB) continue;
			if (!texLastUseMs.exists(k)) continue;
			var last:Float = texLastUseMs.get(k);
			if (nowMs - last < texIdleSec * 1000) continue;
			if (texEvictedMs.exists(k) && nowMs - texEvictedMs.get(k) < texCooldownSec * 1000) continue;
			var uc:Dynamic = Reflect.getProperty(g, 'useCount');
			if (uc == null) return '';					// 拿不到引用计数 → 这轮不回收(保守)
			if (Std.int(uc) > 0) continue;				// 还有 sprite 在用
			cands.push({k: k, mb: mb, last: last});
		}
		if (cands.length == 0) return '';
		cands.sort(function(a, b) return (a.last < b.last) ? -1 : ((a.last > b.last) ? 1 : 0));

		var freed:Int = 0;
		var freedMB:Float = 0;
		var total:Float = gpuTotalMB;
		for (c in cands)
		{
			if (total <= texBudgetMB || freed >= 8) break;
			var g:FlxGraphic = currentTrackedAssets.get(c.k);
			if (g == null) continue;
			FlxG.bitmap._cache.remove(c.k);
			OpenFlAssets.cache.removeBitmapData(c.k);
			currentTrackedAssets.remove(c.k);
			texLastUseMs.remove(c.k);
			texEvictedMs.set(c.k, nowMs);
			g.persist = false;
			g.destroyOnNoUse = true;
			g.destroy();
			freed++;
			freedMB += c.mb;
			total -= c.mb;
		}

		if (freed <= 0) return '';
		texSweptMB += freedMB;
		return '[纹理] 回收 ' + freed + ' 张/' + Math.round(freedMB) + 'MB 显存=' + Math.round(gpuTotalMB)
			+ '→' + Math.round(total) + 'MB (预算=' + Math.round(texBudgetMB) + 'MB 累计=' + Math.round(texSweptMB) + 'MB)';
		#else
		return '';
		#end
	}

	// define the locally tracked assets
	// 改为 Map 去重: 旧 Array 每次 push 无判重, 一首歌能堆上万条重复项,
	// 而清理侧 contains() 是线性扫 → O(资产数×条目数) 的字符串比较雪崩
	public static var localTrackedAssets:Map<String, Bool> = new Map<String, Bool>();
	public static function clearStoredMemory() {
		// 先重置跟踪表: 否则上一状态的 Inst/Voices 等声音因 key 在表内而永远清不掉
		localTrackedAssets.clear();

		// clear anything not in the tracked assets list
		@:privateAccess
		for (key in FlxG.bitmap._cache.keys())
		{
			var obj = FlxG.bitmap._cache.get(key);
			if (obj != null && !currentTrackedAssets.exists(key))
			{
				openfl.Assets.cache.removeBitmapData(key);
				FlxG.bitmap._cache.remove(key);
				obj.destroy();
			}
		}

		// clear all sounds that are cached
		for (key => asset in currentTrackedSounds)
		{
			if (!localTrackedAssets.exists(key) && !dumpExclusions.contains(key) && asset != null)
			{
				Assets.cache.clear(key);
				currentTrackedSounds.remove(key);
			}
		}

		pathCache.clear();
		fileExistsCache.clear();

		#if !html5 openfl.Assets.cache.clear("songs"); #end
	}

	static public var currentLevel:String;
	static public function setCurrentLevel(name:String)
	{
		currentLevel = name.toLowerCase();
	}

	public static function getPath(file:String, ?type:AssetType = TEXT, ?library:Null<String> = null, ?modsAllowed:Bool = false):String
	{
		#if MODS_ALLOWED
		if(modsAllowed)
		{
			var customFile:String = file;
			if (library != null)
				customFile = '$library/$file';

			var modded:String = modFolders(customFile);
			if(FileSystem.exists(modded)) return modded;
		}
		#end

		if (library != null)
			return getLibraryPath(file, library);

		if (currentLevel != null)
		{
			var levelPath:String = '';
			if(currentLevel != 'shared') {
				levelPath = getLibraryPathForce(file, 'week_assets', currentLevel);
				if (OpenFlAssets.exists(levelPath, type))
					return levelPath;
			}
		}

		return getSharedPath(file);
	}

	static public function getLibraryPath(file:String, library = "shared")
	{
		return if (library == "shared") getSharedPath(file); else getLibraryPathForce(file, library);
	}

	inline static function getLibraryPathForce(file:String, library:String, ?level:String)
	{
		if(level == null) level = library;
		var returnPath = '$library:assets/$level/$file';
		return returnPath;
	}

	inline public static function getSharedPath(file:String = '')
	{
		return 'assets/shared/$file';
	}

	inline static public function txt(key:String, ?library:String)
	{
		return getPath('data/$key.txt', TEXT, library);
	}

	inline static public function xml(key:String, ?library:String)
	{
		return getPath('data/$key.xml', TEXT, library);
	}

	inline static public function json(key:String, ?library:String)
	{
		return getPath('data/$key.json', TEXT, library);
	}

	inline static public function shaderFragment(key:String, ?library:String)
	{
		return getPath('shaders/$key.frag', TEXT, library);
	}
	inline static public function shaderVertex(key:String, ?library:String)
	{
		return getPath('shaders/$key.vert', TEXT, library);
	}
	inline static public function lua(key:String, ?library:String)
	{
		return getPath('$key.lua', TEXT, library);
	}

	static public function video(key:String)
	{
		#if MODS_ALLOWED
		var file:String = modsVideo(key);
		if(FileSystem.exists(file)) {
			return file;
		}
		#end
		return 'assets/videos/$key.$VIDEO_EXT';
	}

	static public function sound(key:String, ?library:String):Sound
	{
		var sound:Sound = returnSound('sounds', key, library);
		return sound;
	}

	inline static public function soundRandom(key:String, min:Int, max:Int, ?library:String)
	{
		return sound(key + FlxG.random.int(min, max), library);
	}

	inline static public function music(key:String, ?library:String):Sound
	{
		var file:Sound = returnSound('music', key, library);
		return file;
	}

	inline static public function voices(song:String, postfix:String = null):Any
	{
		var songKey:String = '${formatToSongPath(song)}/Voices';
		if(postfix != null) songKey += '-' + postfix;
		// 选歌预载命中: 取走后台解码好的 Sound, 注册进正常缓存
		#if (cpp && mobile)
		var preV:Sound = backend.AudioPreload.take('songs:$songKey');
		if (preV != null)
		{
			var gpV:String = '$songKey.$SOUND_EXT';
			currentTrackedSounds.set(gpV, preV);
			localTrackedAssets.set(gpV, true);
			return preV;
		}
		#end
		var voices = returnSound(null, songKey, 'songs');
		return voices;
	}

	inline static public function inst(song:String):Any
	{
		var songKey:String = '${formatToSongPath(song)}/Inst';
		// 选歌预载命中: 取走后台解码好的 Sound, 注册进正常缓存
		#if (cpp && mobile)
		var preI:Sound = backend.AudioPreload.take('songs:$songKey');
		if (preI != null)
		{
			var gpI:String = '$songKey.$SOUND_EXT';
			currentTrackedSounds.set(gpI, preI);
			localTrackedAssets.set(gpI, true);
			return preI;
		}
		#end
		var inst = returnSound(null, songKey, 'songs');
		return inst;
	}

	// ===== B1 并行解码支持: 仅解析歌曲音频真实路径(不解码/不进缓存, 线程安全) =====
	// 只覆盖 mod 文件夹歌曲(可后台 Sound.fromFile); 嵌入 APK 资产返回 null(调用方回退主线程原路径)
	public static function songSoundFile(songKey:String):String
	{
		#if MODS_ALLOWED
		var file:String = modsSounds('songs', songKey);
		if (FileSystem.exists(file)) return file;
		#end
		return null;
	}

	// 供 LuaSoundScan: 把 lua 里的音效键解析为实际文件路径(找不到返回 null)
	public static function anySoundFile(key:String):String
	{
		#if MODS_ALLOWED
		var f:String = modsSounds('sounds', key);
		if (FileSystem.exists(f)) return f;
		f = modsSounds('music', key);
		if (FileSystem.exists(f)) return f;
		#end
		return null;
	}

	// ===== 打歌中首载诊断: 缓存未命中的解码超过阈值且处于打歌状态时, 记录到 PerfProbe =====
	static function logSlowLoad(kind:String, file:String, ms:Float):Void
	{
		if (ms < 50) return;
		var st:String = Type.getClassName(Type.getClass(flixel.FlxG.state));
		if (st == null || st.indexOf('PlayState') < 0) return;
		backend.PerfProbe.log('[首载] ' + kind + ' ' + file.substr(file.lastIndexOf('/') + 1) + ' ' + Math.round(ms) + 'ms');
	}

	public static var currentTrackedAssets:Map<String, FlxGraphic> = [];
	
	static public function image(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxGraphic
	{
		var bitmap:BitmapData = null;
		var file:String = null;

		#if MODS_ALLOWED
		#if ASTC_SUPPORT
		var fileAstc:String = modFolders('images/' + key + '.astc');
		
		var cachedAstc = currentTrackedAssets.get(fileAstc);
		if (cachedAstc != null)
		{
			localTrackedAssets.set(fileAstc, true);
			texTouch(fileAstc);
			return cachedAstc;
		}
		else if (FileSystem.exists(fileAstc))
		{
			file = fileAstc;
			bitmap = ASTCBitmapData.fromBytes(File.getBytes(file));
		}
		#end

		if (bitmap == null)
		{
			var filePng:String = modsImages(key);
			var cachedPng = currentTrackedAssets.get(filePng);
			
			if (cachedPng != null)
			{
				localTrackedAssets.set(filePng, true);
				texTouch(filePng);
				return cachedPng;
			}
			else if (FileSystem.exists(filePng))
			{
				file = filePng;
				var t0:Float = haxe.Timer.stamp() * 1000;
				bitmap = BitmapData.fromFile(file);
				logSlowLoad('贴图', file, haxe.Timer.stamp() * 1000 - t0);
			}
		}
		#end

		if (bitmap == null)
		{
			var pathPng:String = getPath('images/$key.png', IMAGE, library);
			
			#if ASTC_SUPPORT
			var pathAstc:String = StringTools.replace(pathPng, '.png', '.astc');
			
			var cachedPathAstc = currentTrackedAssets.get(pathAstc);
			if (cachedPathAstc != null)
			{
				localTrackedAssets.set(pathAstc, true);
				texTouch(pathAstc);
				return cachedPathAstc;
			}
			else if (OpenFlAssets.exists(pathAstc))
			{
				file = pathAstc;
				bitmap = ASTCBitmapData.fromBytes(OpenFlAssets.getBytes(file));
			}
			#end
			
			if (bitmap == null)
			{
				var cachedPathPng = currentTrackedAssets.get(pathPng);
				if (cachedPathPng != null)
				{
					localTrackedAssets.set(pathPng, true);
					texTouch(pathPng);
					return cachedPathPng;
				}
				else if (OpenFlAssets.exists(pathPng, IMAGE))
				{
					file = pathPng;
					bitmap = OpenFlAssets.getBitmapData(file);
				}
				else
				{
					file = pathPng;
				}
			}
		}

		if (bitmap != null)
		{
			var retVal = cacheBitmap(file, bitmap, allowGPU);
			if (retVal != null) return retVal;
		}

		trace('oh no its returning null NOOOO ($file)');
		return null;
	}

	static public function cacheBitmap(file:String, ?bitmap:BitmapData = null, ?allowGPU:Bool = true)
	{
		if(bitmap == null)
		{
			#if MODS_ALLOWED
			if (FileSystem.exists(file))
			{
				#if ASTC_SUPPORT
				if (StringTools.endsWith(file, '.astc'))
					bitmap = ASTCBitmapData.fromBytes(File.getBytes(file));
				else
				#end
					bitmap = BitmapData.fromFile(file);
			}
			else
			#end
			{
				#if ASTC_SUPPORT
				if (StringTools.endsWith(file, '.astc'))
				{
					if (OpenFlAssets.exists(file))
						bitmap = ASTCBitmapData.fromBytes(OpenFlAssets.getBytes(file));
				}
				else
				#end
				{
					if (OpenFlAssets.exists(file, IMAGE))
						bitmap = OpenFlAssets.getBitmapData(file);
				}
			}

			if(bitmap == null) return null;
		}

		localTrackedAssets.set(file, true);
		texTouch(file);		// L1: 记账"这张图刚被请求", 供空闲回收判断

		var isAstc:Bool = false;
		#if ASTC_SUPPORT
		isAstc = StringTools.endsWith(file, '.astc');
		#end

		// 大图自动 GPU 化: 解码 >= 2MB 的贴图上传显存后丢弃 CPU 副本(不受 cacheOnGPU 开关影响)
		// 目标: mod 大图/excludes 未压缩图的堆占用; 小图维持原路径零风险; ASTC 本就零堆占用直接跳过
		var bigTex:Bool = bitmap.width * bitmap.height * 4 >= 2097152;
		if (allowGPU && !isAstc && (ClientPrefs.data.cacheOnGPU || bigTex))
		{
			var texture:RectangleTexture = FlxG.stage.context3D.createRectangleTexture(bitmap.width, bitmap.height, BGRA, true);
			texture.uploadFromBitmapData(bitmap);
            bitmap.image.data = null;
			bitmap.dispose();
			bitmap.disposeImage();
			bitmap = BitmapData.fromTexture(texture);
		}

		var newGraphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, file);
		newGraphic.persist = true;
		newGraphic.destroyOnNoUse = false;
		currentTrackedAssets.set(file, newGraphic);
		
		return newGraphic;
	}

	static public function getTextFromFile(key:String, ?ignoreMods:Bool = false):String
	{
		#if sys
		#if MODS_ALLOWED
		if (!ignoreMods && FileSystem.exists(modFolders(key)))
			return File.getContent(modFolders(key));
		#end

		if (FileSystem.exists(getSharedPath(key)))
			return File.getContent(getSharedPath(key));

		if (currentLevel != null)
		{
			var levelPath:String = '';
			if(currentLevel != 'shared') {
				levelPath = getLibraryPathForce(key, 'week_assets', currentLevel);
				if (FileSystem.exists(levelPath))
					return File.getContent(levelPath);
			}
		}
		#end
		var path:String = getPath(key, TEXT);
		if(OpenFlAssets.exists(path, TEXT)) return Assets.getText(path);
		return null;
	}

	inline static public function font(key:String)
	{
		#if MODS_ALLOWED
		var file:String = modsFont(key);
		if(FileSystem.exists(file)) {
			return file;
		}
		#end
		return 'assets/fonts/$key';
	}

	public static function fileExists(key:String, type:AssetType, ?ignoreMods:Bool = false, ?library:String = null)
	{
		var cacheKey:String = key + "_" + type + "_" + ignoreMods + "_" + library;
		var cachedResult = fileExistsCache.get(cacheKey);
		if (cachedResult != null) return cachedResult;

		var exists:Bool = false;

		#if MODS_ALLOWED
		if(!ignoreMods)
		{
			for(mod in Mods.getGlobalMods()) {
				if (FileSystem.exists(mods('$mod/$key'))) {
					exists = true;
					break;
				}
			}

			if (!exists && (FileSystem.exists(mods(Mods.currentModDirectory + '/' + key)) || FileSystem.exists(mods(key))))
				exists = true;
			
			if (!exists && FileSystem.exists(mods('$key')))
				exists = true;
		}
		#end

		if(!exists && OpenFlAssets.exists(getPath(key, type, library, false))) {
			exists = true;
		}

		fileExistsCache.set(cacheKey, exists);
		return exists;
	}

	static public function getAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var useMod = false;
		var imageLoaded:FlxGraphic = image(key, library, allowGPU);

		var myXml:Dynamic = getPath('images/$key.xml', TEXT, library, true);
		if(OpenFlAssets.exists(myXml) #if MODS_ALLOWED || (FileSystem.exists(myXml) && (useMod = true)) #end )
		{
			#if MODS_ALLOWED
			return FlxAtlasFrames.fromSparrow(imageLoaded, (useMod ? File.getContent(myXml) : myXml));
			#else
			return FlxAtlasFrames.fromSparrow(imageLoaded, myXml);
			#end
		}
		else
		{
			var myJson:Dynamic = getPath('images/$key.json', TEXT, library, true);
			if(OpenFlAssets.exists(myJson) #if MODS_ALLOWED || (FileSystem.exists(myJson) && (useMod = true)) #end )
			{
				#if MODS_ALLOWED
				return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, (useMod ? File.getContent(myJson) : myJson));
				#else
				return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, myJson);
				#end
			}
		}
		return getPackerAtlas(key, library);
	}

	inline static public function getSparrowAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var imageLoaded:FlxGraphic = image(key, library, allowGPU);
		#if MODS_ALLOWED
		var xmlExists:Bool = false;

		var xml:String = modsXml(key);
		if(FileSystem.exists(xml)) xmlExists = true;

		return FlxAtlasFrames.fromSparrow(imageLoaded, (xmlExists ? File.getContent(xml) : getPath('images/$key.xml', library)));
		#else
		return FlxAtlasFrames.fromSparrow(imageLoaded, getPath('images/$key.xml', library));
		#end
	}

	inline static public function getPackerAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var imageLoaded:FlxGraphic = image(key, library, allowGPU);
		#if MODS_ALLOWED
		var txtExists:Bool = false;
		
		var txt:String = modsTxt(key);
		if(FileSystem.exists(txt)) txtExists = true;

		return FlxAtlasFrames.fromSpriteSheetPacker(imageLoaded, (txtExists ? File.getContent(txt) : getPath('images/$key.txt', library)));
		#else
		return FlxAtlasFrames.fromSpriteSheetPacker(imageLoaded, getPath('images/$key.txt', library));
		#end
	}

	inline static public function getAsepriteAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var imageLoaded:FlxGraphic = image(key, library, allowGPU);
		#if MODS_ALLOWED
		var jsonExists:Bool = false;

		var json:String = modsImagesJson(key);
		if(FileSystem.exists(json)) jsonExists = true;

		return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, (jsonExists ? File.getContent(json) : getPath('images/$key.json', library)));
		#else
		return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, getPath('images/$key.json', library));
		#end
	}

	inline static public function formatToSongPath(path:String) {
		var invalidChars = ~/[~&\\;:<>#]/;
		var hideChars = ~/[.,'"%?!]/;

		var path = invalidChars.split(path.replace(' ', '-')).join("-");
		return hideChars.split(path).join("").toLowerCase();
	}

	public static var currentTrackedSounds:Map<String, Sound> = [];
	
	public static function returnSound(path:Null<String>, key:String, ?library:String) {
		#if MODS_ALLOWED
		var modLibPath:String = '';
		if (library != null) modLibPath = '$library/';
		if (path != null) modLibPath += '$path';

		var file:String = modsSounds(modLibPath, key);
		if(FileSystem.exists(file)) {
			var cachedModSound = currentTrackedSounds.get(file);
			if(cachedModSound == null)
				cachedModSound = backend.LuaSoundScan.take(file);	// lua 扫描预载命中: 零停顿
			if(cachedModSound == null)
			{
				var t0:Float = haxe.Timer.stamp() * 1000;
				cachedModSound = Sound.fromFile(file);
				logSlowLoad('音频', file, haxe.Timer.stamp() * 1000 - t0);
				currentTrackedSounds.set(file, cachedModSound);
			}
			// 菜单曲常驻: 曲3 实测每首歌末回选曲时都要把 mod 版 freakyMenu 重新全解码一次
			// (1.4~2.3s, 是整份日志里最大的一次停顿), 因为 clearStoredMemory() 每次进状态都会清掉它。
			// 这份只解码一次后常驻(约 10~30MB, 在音频库/原生内存, 不进 hxcpp 堆、不参与 GC)。
			if (key == 'freakyMenu') excludeAsset(file);
			localTrackedAssets.set(file, true);
			return cachedModSound;
		}
		#end

		var gottenPath:String = '$key.$SOUND_EXT';
		if(path != null) gottenPath = '$path/$gottenPath';
		gottenPath = getPath(gottenPath, SOUND, library);
		gottenPath = gottenPath.substring(gottenPath.indexOf(':') + 1, gottenPath.length);
		
		var cachedSound = currentTrackedSounds.get(gottenPath);
		if(cachedSound == null)
		{
			var retKey:String = (path != null) ? '$path/$key' : key;
			retKey = ((path == 'songs') ? 'songs:' : '') + getPath('$retKey.$SOUND_EXT', SOUND, library);
			if(OpenFlAssets.exists(retKey, SOUND))
			{
				cachedSound = OpenFlAssets.getSound(retKey);
				currentTrackedSounds.set(gottenPath, cachedSound);
			}
		}
		localTrackedAssets.set(gottenPath, true);
		return cachedSound;
	}

	#if MODS_ALLOWED
	inline static public function mods(key:String = '') {
		return #if mobile StorageSystem.getDirectory() + #end 'mods/' + key;
	}

	inline static public function modsFont(key:String) {
		return modFolders('fonts/' + key);
	}

	inline static public function modsJson(key:String) {
		return modFolders('data/' + key + '.json');
	}

	inline static public function modsVideo(key:String) {
		return modFolders('videos/' + key + '.' + VIDEO_EXT);
	}

	inline static public function modsSounds(path:String, key:String) {
		return modFolders(path + '/' + key + '.' + SOUND_EXT);
	}

	inline static public function modsImages(key:String) {
		return modFolders('images/' + key + '.png');
	}

	inline static public function modsXml(key:String) {
		return modFolders('images/' + key + '.xml');
	}

	inline static public function modsTxt(key:String) {
		return modFolders('images/' + key + '.txt');
	}

	inline static public function modsImagesJson(key:String) {
		return modFolders('images/' + key + '.json');
	}

	static public function modFolders(key:String) {
		var cachedPath = pathCache.get(key);
		if (cachedPath != null) return cachedPath;

		var basePath:String = #if mobile StorageSystem.getDirectory() + #end 'mods/';
		
		if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0) {
			var fileToCheck:String = basePath + Mods.currentModDirectory + '/' + key;
			if(FileSystem.exists(fileToCheck)) {
				pathCache.set(key, fileToCheck);
				return fileToCheck;
			}
		}

		for(mod in Mods.getGlobalMods()){
			var fileToCheck:String = basePath + mod + '/' + key;
			if(FileSystem.exists(fileToCheck)) {
				pathCache.set(key, fileToCheck);
				return fileToCheck;
			}
		}
		
		var defaultPath:String = basePath + key;
		pathCache.set(key, defaultPath);
		return defaultPath;
	}
	#end

	#if flxanimate
	public static function loadAnimateAtlas(spr:FlxAnimate, folderOrImg:Dynamic, spriteJson:Dynamic = null, animationJson:Dynamic = null)
	{
		var changedAnimJson = false;
		var changedAtlasJson = false;
		var changedImage = false;
		
		if(spriteJson != null)
		{
			changedAtlasJson = true;
			spriteJson = File.getContent(spriteJson);
		}

		if(animationJson != null) 
		{
			changedAnimJson = true;
			animationJson = File.getContent(animationJson);
		}

		// is folder or image path
		if(Std.isOfType(folderOrImg, String))
		{
			var originalPath:String = folderOrImg;
			for (i in 0...10)
			{
				var st:String = '$i';
				if(i == 0) st = '';

				if(!changedAtlasJson)
				{
					spriteJson = getTextFromFile('images/$originalPath/spritemap$st.json');
					if(spriteJson != null)
					{
						changedImage = true;
						changedAtlasJson = true;
						folderOrImg = Paths.image('$originalPath/spritemap$st');
						break;
					}
				}
				else if(Paths.fileExists('images/$originalPath/spritemap$st.png', IMAGE))
				{
					changedImage = true;
					folderOrImg = Paths.image('$originalPath/spritemap$st');
					break;
				}
			}

			if(!changedImage)
			{
				changedImage = true;
				folderOrImg = Paths.image(originalPath);
			}

			if(!changedAnimJson)
			{
				changedAnimJson = true;
				animationJson = getTextFromFile('images/$originalPath/Animation.json');
			}
		}

		spr.loadAtlasEx(folderOrImg, spriteJson, animationJson);
	}
	#end
}