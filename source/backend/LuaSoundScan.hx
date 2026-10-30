package backend;

// ===== lua 音效扫描预载: 进歌时扫描脚本字面量里的 playSound/playMusic 键, 后台线程预解码 =====
// 动机: mod 脚本在打歌中途 Paths.sound 动态解码, 单轨 1-4s 主线程停顿(Infraction 实测: 音轨 1→8 波动,
//       四次 1.5-4s 卡顿, 42 个 miss 中 39 个来自其中两次)。
// 线程模式与 AudioPreload 相同: 后台 Sound.fromFile 纯解码(不碰 Paths 全局缓存, 零竞态), Mutex 保护就绪表。
// 就绪表按"解析后的绝对文件路径"存取; Paths.returnSound 在同步解码前先查表, 命中即零停顿。
// 只识别脚本里的字面量键(变量拼接的键回退原同步路径, 无回归)。
class LuaSoundScan
{
	static var ready:Map<String, openfl.media.Sound> = [];
	static var mutex:sys.thread.Mutex = new sys.thread.Mutex();
	static var gen:Int = 0;	// 代际号: reset/新开局使进行中的旧扫描失效

	// 新开局/状态销毁: 清表并使旧扫描作废
	public static function reset():Void
	{
		mutex.acquire();
		ready.clear();
		gen++;
		mutex.release();
	}

	// Paths.returnSound 同步解码前调用: 命中返回已解码的 Sound 并从就绪表移除
	public static function take(file:String):openfl.media.Sound
	{
		var s:openfl.media.Sound = null;
		mutex.acquire();
		if (ready.exists(file))
		{
			s = ready.get(file);
			ready.remove(file);
		}
		mutex.release();
		return s;
	}

	// 进歌收尾调用(PlayState.create 脚本全部加载后): 传入所有已加载脚本的文件路径
	public static function start(scriptPaths:Array<String>):Void
	{
		#if (MODS_ALLOWED && sys)
		mutex.acquire();
		ready.clear();
		gen++;
		var myGen:Int = gen;
		mutex.release();

		// 1) 扫描脚本源文本, 收集音效键
		var r:EReg = new EReg("(?:playSound|playMusic)\\s*\\(\\s*[\"']([^\"']+)[\"']", "g");
		var seen:Map<String, Bool> = [];
		var files:Array<String> = [];
		for (p in scriptPaths)
		{
			var txt:String = null;
			try { txt = sys.io.File.getContent(p); } catch (e:Dynamic) { continue; }
			while (r.match(txt))
			{
				var key:String = r.matched(1);
				txt = r.matchedRight();
				if (key == null || key.length < 1 || seen.exists(key)) continue;
				seen.set(key, true);
				var f:String = Paths.anySoundFile(key);
				if (f != null) files.push(f);
			}
		}
		if (files.length < 1) return;

		// 2) 后台线程顺序解码
		sys.thread.Thread.create(function() {
			for (f in files)
			{
				mutex.acquire();
				var stale:Bool = (gen != myGen) || ready.exists(f);
				mutex.release();
				if (stale) continue;
				var s:openfl.media.Sound = null;
				try { s = openfl.media.Sound.fromFile(f); } catch (eScan:Dynamic) { s = null; }
				if (s == null) continue;
				mutex.acquire();
				if (gen == myGen && !ready.exists(f)) ready.set(f, s);
				mutex.release();
			}
		});
		#end
	}
}
