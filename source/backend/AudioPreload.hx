package backend;

import openfl.media.Sound;
import sys.thread.Mutex;
import sys.thread.Thread;

/**
 * 选歌预载: 选曲界面后台线程预解码 Inst/Voices(ogg->PCM), 点歌时 Paths.inst/voices
 * 从 ready 表原子取走, 进歌省 1-2 秒解码。
 * 线程安全: 后台线程用 Sound.fromFile 纯解码(不碰 Paths 全局缓存), ready 表读写全走 mutex;
 * 主线程 take() 同锁。过期结果(用户已换歌)直接丢弃, ready 最多驻留一首的 PCM。
 */
class AudioPreload
{
	static var ready:Map<String, Sound> = [];	// key(songs:xxx/Inst) -> 已解码 Sound
	static var mutex:Mutex = new Mutex();
	static var want:String = '';		// 最新选中的歌
	static var running:Bool = false;	// worker 是否存活

	/** 选曲界面换歌时调用(滚动防抖由调用方自由, 内部自动串行) */
	public static function preload(song:String):Void
	{
		#if (cpp && mobile)
		if (song == null || song.length < 1) return;
		var key:String = Paths.formatToSongPath(song);
		mutex.acquire();
		var changed:Bool = (key != want);
		want = key;
		var start:Bool = false;
		if (changed && !running && !ready.exists('songs:$key/Inst'))
		{
			running = true;
			start = true;
		}
		mutex.release();
		if (start) Thread.create(worker);
		#end
	}

	/** 主线程取走预载结果(原子), 未命中返回 null */
	public static function take(key:String):Sound
	{
		var s:Sound = null;
		mutex.acquire();
		if (ready.exists(key)) { s = ready.get(key); ready.remove(key); }
		mutex.release();
		return s;
	}

	static function worker():Void
	{
		while (true)
		{
			mutex.acquire();
			var target:String = want;
			var needWork:Bool = !ready.exists('songs:$target/Inst');
			mutex.release();

			if (needWork)
			{
				// 纯解码: 不经 Paths 缓存, 不写全局 Map (后台线程零竞态)
				var inst:Sound = null;
				var voices:Sound = null;
				try
				{
					var p:String = Paths.getPath('songs/$target/Inst.$SOUND_EXT', TEXT, 'songs');
					p = p.substring(p.indexOf(':') + 1, p.length);
					if (sys.FileSystem.exists(p)) inst = Sound.fromFile(p);
				}
				catch (e:Dynamic) {}
				try
				{
					var p:String = Paths.getPath('songs/$target/Voices.$SOUND_EXT', TEXT, 'songs');
					p = p.substring(p.indexOf(':') + 1, p.length);
					if (sys.FileSystem.exists(p)) voices = Sound.fromFile(p);
				}
				catch (e:Dynamic) {}

				mutex.acquire();
				if (want == target)	// 未被新选择替换才入表
				{
					if (inst != null) ready.set('songs:$target/Inst', inst);
					if (voices != null) ready.set('songs:$target/Voices', voices);
				}
				mutex.release();
			}

			// want 已就绪(或不存在)则收工; 换了新目标继续
			mutex.acquire();
			var more:Bool = !ready.exists('songs:$want/Inst');
			if (!more) running = false;
			mutex.release();
			if (!more) return;
		}
	}
}
