package options;

class GameplaySettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = 'Gameplay Settings';
		rpcTitle = 'Gameplay Settings Menu'; //for Discord Rich Presence

		//I'd suggest using "Downscroll" as an example for making your own option since it is the simplest here
		var option:Option = new Option('下落模式', //Name
			'开启后音符向下落，而不是向上。', //Description
			'downScroll', //Save data variable name
			'bool'); //Variable type
		addOption(option);

		var option:Option = new Option('居中模式',
			'开启后你的音符会居中显示。',
			'middleScroll',
			'bool');
		addOption(option);
		
		#if mobile		
		var option:Option = new Option('隐藏判定框',
            '开启后判定框将不可见。',
            'invisibleHitbox',
            'bool');
		addOption(option);
		
		#if !ios
		var option:Option = new Option('隐藏暂停按钮',
            '开启后暂停按钮将不可见。',
            'invisibleButtonPause',
            'bool');
		addOption(option);
		#end
		#end

		var option:Option = new Option('对手音符',
			'关闭后隐藏对手的音符。',
			'opponentStrums',
			'bool');
		addOption(option);

		var option:Option = new Option('幽灵按键',
			"开启后，方向上没有音符时\n按键不会被判为Miss。",
			'ghostTapping',
			'bool');
		addOption(option);
		
		var option:Option = new Option('自动暂停',
			"开启后，画面失去焦点时游戏自动暂停。",
			'autoPause',
			'bool');
		addOption(option);
		option.onChange = onChangeAutoPause;

		var option:Option = new Option('禁用重开键',
			"开启后按重开键将无效果。",
			'noReset',
			'bool');
		addOption(option);

		var option:Option = new Option('打击音效音量',
			'击中音符时会发出“Tick!”声，此项调整音量。',
			'hitsoundVolume',
			'percent');
		addOption(option);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		option.onChange = onChangeHitsoundVolume;

		var option:Option = new Option('评价偏移',
			'调整击出“Sick!”评价所需的提前/延迟量。\n数值越大，判定越宽松。',
			'ratingOffset',
			'int');
		option.displayFormat = '%vms';
		option.scrollSpeed = 20;
		option.minValue = -30;
		option.maxValue = 30;
		addOption(option);

		var option:Option = new Option('Sick! 判定窗口',
			'调整击出“Sick!”评价的\n时间窗口(毫秒)。',
			'sickWindow',
			'int');
		option.displayFormat = '%vms';
		option.scrollSpeed = 15;
		option.minValue = 15;
		option.maxValue = 45;
		addOption(option);

		var option:Option = new Option('Good 判定窗口',
			'调整击出“Good”评价的\n时间窗口(毫秒)。',
			'goodWindow',
			'int');
		option.displayFormat = '%vms';
		option.scrollSpeed = 30;
		option.minValue = 15;
		option.maxValue = 90;
		addOption(option);

		var option:Option = new Option('Bad 判定窗口',
			'调整击出“Bad”评价的\n时间窗口(毫秒)。',
			'badWindow',
			'int');
		option.displayFormat = '%vms';
		option.scrollSpeed = 60;
		option.minValue = 15;
		option.maxValue = 135;
		addOption(option);

		var option:Option = new Option('安全帧数',
			'调整音符可提前或延后判定的帧数范围。',
			'safeFrames',
			'float');
		option.scrollSpeed = 5;
		option.minValue = 2;
		option.maxValue = 10;
		option.changeValue = 0.1;
		addOption(option);

		var option:Option = new Option('长条按单音符计',
			"开启后，Miss时长条不可继续按压，\n并按单个音符计分。",
			'guitarHeroSustains',
			'bool');
		addOption(option);

		super();
	}

	function onChangeHitsoundVolume()
		FlxG.sound.play(Paths.sound('hitsound'), ClientPrefs.data.hitsoundVolume);

	function onChangeAutoPause()
		FlxG.autoPause = ClientPrefs.data.autoPause;
}