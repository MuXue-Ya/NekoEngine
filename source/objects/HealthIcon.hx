package objects;

class HealthIcon extends FlxSprite
{
	public var sprTracker:FlxSprite;
	private var isOldIcon:Bool = false;
	private var isPlayer:Bool = false;
	private var char:String = '';
	// 图标三态支持(阶段 O): 0=正常 1=落后(输) 2=领先(赢)。
	// 老图标只有 2 帧(正常/落后), 新图标是 3 帧(正常/落后/领先); 没有第 3 帧就自动退回"正常", 老 mod 行为不变。
	public var iconStates:Int = 2;
	public var curIconState:Int = 0;
	private var hasWinFrame:Bool = false;

	public function new(char:String = 'bf', isPlayer:Bool = false, ?allowGPU:Bool = true)
	{
		super();
		isOldIcon = (char == 'bf-old');
		this.isPlayer = isPlayer;
		changeIcon(char, allowGPU);
		scrollFactor.set();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (sprTracker != null)
			setPosition(sprTracker.x + sprTracker.width + 12, sprTracker.y - 30);
	}

	private var iconOffsets:Array<Float> = [0, 0];
	public function changeIcon(char:String, ?allowGPU:Bool = true) {
		if(this.char != char) {
			var name:String = 'icons/' + char;
			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-' + char; //Older versions of psych engine's support
			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-face'; //Prevents crash from missing icon
			
			var graphic = Paths.image(name, allowGPU);
			// 帧数判定: 图标格子都是正方形, 所以"帧宽 ≈ 图高"才成立。
			// 先按 2 帧算(老格式), 只有当 2 帧不成正方形、而 3 帧成正方形时才认成 3 帧 —— 保证老图标一刀不动。
			var fw2:Float = graphic.width / 2;
			var fw3:Float = graphic.width / 3;
			var gh:Float = graphic.height;
			var states:Int = 2;
			var frameW:Float = fw2;
			if (Math.abs(fw2 - gh) > gh * 0.20 && Math.abs(fw3 - gh) <= gh * 0.10)
			{
				states = 3;
				frameW = fw3;
			}
			this.iconStates = states;
			this.hasWinFrame = (states == 3);
			this.curIconState = -1;	// 换角色后强制下一帧重新套用当前血量状态

			loadGraphic(graphic, true, Std.int(frameW), Math.floor(gh));
			iconOffsets[0] = (width - 150) / 2;
			iconOffsets[1] = (height - 150) / 2;
			updateHitbox();

			animation.add(char, [0, 1], 0, false, isPlayer);
			if (hasWinFrame) animation.add(char + '-win', [2], 0, false, isPlayer);
			animation.play(char);
			this.char = char;

			if(char.endsWith('-pixel'))
				antialiasing = false;
			else
				antialiasing = ClientPrefs.data.antialiasing;
		}
	}

	override function updateHitbox()
	{
		super.updateHitbox();
		offset.x = iconOffsets[0];
		offset.y = iconOffsets[1];
	}

	// 切换三态图标: 0=正常 1=落后 2=领先。
	// 没有第 3 帧时 state=2 自动退回 0(正常), 也就是"没有这种图标就用默认的"。
	public function setIconState(state:Int):Void
	{
		if (!hasWinFrame && state == 2) state = 0;
		if (state == curIconState) return;
		curIconState = state;

		var animName:String = (state == 2) ? char + '-win' : char;
		if (animation.curAnim == null || animation.curAnim.name != animName) animation.play(animName);

		var frameIdx:Int = (state == 1) ? 1 : 0;
		if (animation.curAnim != null && frameIdx < animation.curAnim.numFrames)
			animation.curAnim.curFrame = frameIdx;
	}

	public function getCharacter():String {
		return char;
	}
}
