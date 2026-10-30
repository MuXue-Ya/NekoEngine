package mobile.backend;

import lime.app.Application;

import haxe.io.Path;
import haxe.io.Bytes;

import openfl.utils.ByteArray;
import openfl.utils.Assets;

#if android
import androidmanager.os.Environment;
import androidmanager.tools.PermissionUtils;
import androidmanager.os.Build.VERSION;
import androidmanager.os.Build.VERSION_CODES;
import androidmanager.content.Interface;
#end

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/** * @Authors StarNova (Cream.BR), LumiCoder (FNF BR)
 * @version 0.2.0
 */
class StorageSystem
{
	private static var folderName(get, never):String;
	
	private static function get_folderName():String
	{
		return 'NekoEngine';
	}
	
	private static var packageName(get, never):String;
	
	private static function get_packageName():String
	{
		return Application.current.meta.get('packageName');
	}
	
	/**
	 * Returns the base storage directory path.
	 */
	public static function getDirectory():String
	{
		#if android
		if (VERSION.SDK_INT >= VERSION_CODES.R)
			return Environment.getExternalStorageDirectory() + '/.' + folderName + '/';
		else
			return '/storage/emulated/0/.' + folderName + '/';
		#elseif ios
		return haxe.io.Path.addTrailingSlash(lime.system.System.documentsDirectory);
		#else
		return Sys.getCwd();
		#end
	}
	
	/**
	 * Returns the assets directory path.
	 */
	public static function getAssetsDirectory():String
	{
		#if android
		if (VERSION.SDK_INT >= VERSION_CODES.R)
			return Environment.getExternalStorageDirectory() + '/Android/media/' + packageName + '/';
		else
			return '/storage/emulated/0/Android/media/' + packageName + '/';
		#elseif ios
		return haxe.io.Path.addTrailingSlash(lime.system.System.documentsDirectory);
		#else
		return Sys.getCwd();
		#end
	}
	
	/**
	 * Requests Android storage permissions and verifies external assets.
	 * @return Bool Returns TRUE if the game boot should halt (permissions pending or full extract), FALSE if ready to play.
	 */
	public static function getPermissions():Bool
	{
		#if android
		if (VERSION.SDK_INT >= VERSION_CODES.TIRAMISU)
		{
			PermissionUtils.requestPermissions([
				'READ_MEDIA_IMAGES',
				'READ_MEDIA_VIDEO',
				'READ_MEDIA_AUDIO',
				'READ_MEDIA_VISUAL_USER_SELECTED'
			]);
		}
		else
		{
			PermissionUtils.requestPermissions(['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE']);
		}
		
		if (VERSION.SDK_INT >= VERSION_CODES.R)
		{
			if (!Environment.isExternalStorageManager()) 
			{
				Interface.requestSetting('MANAGE_APP_ALL_FILES_ACCESS_PERMISSION');
				return true;
			}
		}
		#end
		
		#if mobile
		try
		{
			var path:String = getDirectory();

			// 等待用户授权后再创建文件夹(最多12秒)
			var ready:Bool = false;
			for (i in 0...12)
			{
				if (!FileSystem.exists(path)) FileSystem.createDirectory(path);
				if (FileSystem.exists(path))
				{
					ready = true;
					break;
				}
				Sys.sleep(1);
			}

			if (!ready)
			{
				PopUp.showAlert("Storage Permission", "Please grant storage permission, then restart the game.", "OK");
				return true;
			}

			#if android
			// Creating .nomedia files to avoid images remaining in the gallery
			if (!FileSystem.exists(path + ".nomedia")) File.saveContent(path + ".nomedia", path);
			#end
		}
		catch (e:Dynamic)
		{
			trace("Storage Error: " + e);
		}
		#end

		return false; // If not Mobile, or no interruption needed, proceed.
	}

	/**
	 * 首屏(TitleState)阶段调用: 此时所有资产库已注册完毕, Assets.list() 才完整。
	 * 全部资源解压到 .NekoEngine (getDirectory)。
	 *
	 * 规则: 已存在的目录绝不覆盖(尊重玩家手动放置的 assets/mods),
	 *       只补齐缺失文件; 全新安装才做完整解压并提示重启。
	 */
	public static function checkAndExtract():Void
	{
		#if mobile
		try
		{
			var dataPath:String = getDirectory();
			var needFullExtract:Bool = false;

			// ===== 版本标记: 校验过且版本未变时跳过逐文件完整性扫描 =====
			// 旧逻辑每次冷启动都对全部资产逐个 stat(本仓 485 文件 ≈ 上千次系统调用),
			// Android 外置存储上约多花 0.5~1.5s; 加标记后降为"每次升版本后一次"。
			// 注意: 更新 APK 内置资源但没升 version 时, 缺失文件不会自动补 —— 发版请同步升版本号。
			var appVer:String = '0';
			try { appVer = lime.app.Application.current.meta.get('version'); } catch (eVer:Dynamic) {}
			var markerPath:String = dataPath + '.assets_ver';
			var assetsOk:Bool = FileSystem.exists(dataPath + "assets");
			var modsOk:Bool = FileSystem.exists(dataPath + "mods");
			if (assetsOk && modsOk && FileSystem.exists(markerPath))
			{
				var savedVer:String = '';
				try { savedVer = File.getContent(markerPath); } catch (eMk:Dynamic) {}
				if (savedVer == appVer) return; // 与上次同版本, 跳过扫描
			}

			// 资源: 不存在 → 完整解压; 已存在 → 只补缺失(不覆盖玩家改动)
			if (!assetsOk)
			{
				needFullExtract = true;
				copyFromAPK("assets/", null, true, dataPath);
			}
			else
			{
				var restored = copyFromAPK("assets/", null, false, dataPath);
				if (restored > 0) trace('Assets integrity check restored $restored missing files.');
			}

			// mod: 不存在 → 解压内置示例; 已存在 → 完全不动玩家的 mods
			if (!modsOk)
			{
				needFullExtract = true;
				copyFromAPK("mods/", null, true, dataPath);
			}

			if (needFullExtract)
			{
				PopUp.showConfirm("Success!", "Files extracted. The game will now restart.", "Restart", "Cancel", function() {
					lime.system.System.exit(0);
				});
			}

			// 本轮校验/解压完成, 写标记供下次启动短路
			try { File.saveContent(markerPath, appVer); } catch (eW:Dynamic) {}
		}
		catch (e:Dynamic)
		{
			trace("Storage Error: " + e);
		}
		#end
	}
	
		/**
	 * Recursively copies folders from the APK to external directory.
	 * @return Int The number of files successfully copied.
	 */
	public static function copyFromAPK(sourceDir:String, ?targetDir:String = null, ?forceOverwrite:Bool = true, ?baseDirectory:String):Int
	{
		var copiedCount = 0;
		
		#if mobile
		if (!StringTools.endsWith(sourceDir, "/")) sourceDir += "/";
		
		if (baseDirectory == null) baseDirectory = getDirectory();
		if (targetDir == null) targetDir = baseDirectory + sourceDir;
		if (!StringTools.endsWith(targetDir, "/")) targetDir += "/";
		
		try
		{
			if (!FileSystem.exists(targetDir)) createDirectoryRecursive(targetDir);
			
			var assetList:Array<String> = Assets.list();
			
			for (assetPath in assetList)
			{
				if (StringTools.startsWith(assetPath, sourceDir))
				{
					var relativePath = assetPath.substring(sourceDir.length);
					if (relativePath == "" || relativePath == null) continue;
					
					if (StringTools.startsWith(relativePath, "embeds/")) relativePath = relativePath.substring(7);
					else if (StringTools.startsWith(relativePath, "game/")) relativePath = relativePath.substring(5);
					
					var fullTargetPath = targetDir + relativePath;
					var targetFolder = Path.directory(fullTargetPath);
					
					if (!FileSystem.exists(targetFolder)) createDirectoryRecursive(targetFolder);
					
					if (Assets.exists(assetPath))
					{
						if (FileSystem.exists(fullTargetPath) && !forceOverwrite) continue;
						
						var fileBytes:Bytes = null;
						
						try { 
							var b:ByteArray = Assets.getBytes(assetPath);
							if (b != null) fileBytes = Bytes.ofData(b);
						} catch (e:Dynamic) {}
						
						if (fileBytes == null)
						{
							try {
								fileBytes = lime.utils.Assets.getBytes(assetPath);
							} catch(e:Dynamic) {}
						}
						
						if (fileBytes != null)
						{
							File.saveBytes(fullTargetPath, fileBytes);
							copiedCount++;
						}
						else
						{
							var isAudioOrFont = StringTools.endsWith(assetPath, ".ogg") || StringTools.endsWith(assetPath, ".ttf") || StringTools.endsWith(assetPath, ".otf");
							
							if (!isAudioOrFont)
							{
								try
								{
									var text = Assets.getText(assetPath);
									if (text != null)
									{
										File.saveContent(fullTargetPath, text);
										copiedCount++;
									}
								}
								catch (e:Dynamic)
								{
									if (!FileSystem.exists(fullTargetPath)) trace('Warn: failure extracting $assetPath');
								}
							}
							else if (!FileSystem.exists(fullTargetPath)) 
							{
								trace('Warn: failure extracting binary file $assetPath');
							}
						}
					}
				}
			}
			
			if (copiedCount > 0) trace('Extraction Success! $copiedCount files written to: $targetDir');
		}
		catch (e:Dynamic)
		{
			trace('Critical Error during copyFromAPK: $e');
		}
		#end
		
		return copiedCount;
	}
	
	/**
	 * Saves text content to the internal 'files' directory.
	 */
	#if sys
	public static function saveContent(name:String = 'file', ext:String = '.json', data:String = ''):Void
	{
		var saveFolder:String = Path.join([getDirectory(), "files"]);
		var fullPath:String = Path.join([saveFolder, name + ext]);
		
		try
		{
			if (!FileSystem.exists(saveFolder)) FileSystem.createDirectory(saveFolder);
			
			File.saveContent(fullPath, data);
			PopUp.showAlert("Success!", "File saved in:\n" + saveFolder + "/" + name + ext, "OK");
		}
		catch (e:haxe.Exception)
		{
			var errorMsg:String = "Error on Save!:\n" + e.message;
			trace('Error ' + errorMsg);
			PopUp.showAlert("Error saving file", errorMsg, "Close");
		}
	}
	#end
	
	/**
	 * Creates folders recursively in a safe way, fixing absolute path issues.
	 */
	private static function createDirectoryRecursive(path:String):Void
	{
		#if mobile
		if (FileSystem.exists(path)) return;
		
		var pathParts = path.split("/");
		var currentPath = "";
		
		if (StringTools.startsWith(path, "/"))
		{
			currentPath = "/";
			pathParts.shift();
		}
		
		for (part in pathParts)
		{
			if (part == "") continue;
			
			currentPath = (currentPath == "/") ? (currentPath + part) : (currentPath + "/" + part);
			
			if (!FileSystem.exists(currentPath))
			{
				try
				{
					FileSystem.createDirectory(currentPath);
				}
				catch (e:Dynamic)
				{
					trace('Error Creating Subfolder $currentPath: $e');
				}
			}
		}
		#end
	}
}