package backend;

#if VIDEOS_ALLOWED
#if hxCodec
#if (hxCodec >= "3.0.0") import hxcodec.flixel.FlxVideoSprite as VideoSprite;
#elseif (hxCodec >= "2.6.1") import hxcodec.VideoSprite;
#elseif (hxCodec == "2.6.0") import VideoSprite;
#else import vlc.MP4Sprite as VideoSprite; #end
#elseif hxvlc
import hxvlc.flixel.FlxVideoSprite as VideoSprite;
#end
#end

import states.PlayState;
import haxe.extern.EitherType;
import flixel.util.FlxSignal;
import flixel.util.FlxTimer;
import flixel.FlxG;

#if VIDEOS_ALLOWED
/**
 * A robust video sprite manager that handles cross-compatibility between `hxvlc` 
 * and multiple versions of `hxCodec`. It safely manages video playback, pausing, 
 * memory cleanup, and event signaling.
 */
class FunkinVideoSprite extends VideoSprite {
    
    /** Indicates whether the current active state is PlayState. */
    public var onPlayState(get, never):Bool;
    
    /** Controls the playback speed of the video. */
    public var playbackRate(get, set):EitherType<Single, Float>;
    
    /** Controls the pause state of the video. Hooked into global focus events. */
    public var paused(default, set):Bool = false;
    
    /** Signal dispatched when the video playback finishes. */
    public var onVideoEnd:FlxSignal;
    
    /** Signal dispatched when the video playback starts. */
    public var onVideoStart:FlxSignal;

    /**
     * Initializes a new VideoSpriteManager instance.
     * 
     * @param x The initial X position of the sprite.
     * @param y The initial Y position of the sprite.
     */
    public function new(x:Float = 0, y:Float = 0 #if (hxCodec < "2.6.0" && hxCodec), width:Float = 1280, height:Float = 720, autoScale:Bool = true #end) {
        
        #if hxvlc
        super(Std.int(x), Std.int(y));
        #else
        super(x, y #if (hxCodec < "2.6.0" && hxCodec), width, height, autoScale #end);
        #end

        // Automatically register this video to the PlayState's video list if applicable
        if (onPlayState)
            PlayState.instance.videoSprite.push(this); 
        
        onVideoStart = new FlxSignal();
        onVideoEnd = new FlxSignal();

        // Unified cleanup logic to prevent memory leaks and double destruction
        onVideoEnd.add(function() {
            if (onPlayState && PlayState.instance.videoSprite.contains(this))
                PlayState.instance.videoSprite.remove(this); 
            
            destroy();
        });

        // Setup backend-specific callbacks for video events
        #if (hxCodec >= "3.0.0" || hxvlc)
        bitmap.onOpening.add(function() {
            onVideoStart.dispatch();
        });
        bitmap.onEndReached.add(function() {
            onVideoEnd.dispatch();
        });
        #elseif (hxCodec < "3.0.0" && hxCodec)
        openingCallback = function() {
            onVideoStart.dispatch();
        };
        finishCallback = function() {
            onVideoEnd.dispatch();
        };
        #end
    }
    
    /**
     * Starts the video playback with backend-specific loading logic.
     * 
     * @param path The file path to the video.
     */
    public function startVideo(path:String, #if hxCodec loop:Bool = false #elseif hxvlc loops:Int = 0, ?options:Array<String> #end) {
        #if (hxCodec >= "3.0.0" && hxCodec)
        play(path, loop);
        #elseif (hxCodec < "3.0.0" && hxCodec)
        playVideo(path, loop, false);
        #elseif hxvlc
        load(path, loops, options);
        new FlxTimer().start(0.001, function(tmr:FlxTimer) {
            play();
        });
        #end
        
        // Sync playback rate with the game's current speed
        if (onPlayState)
            playbackRate = PlayState.instance.playbackRate;
    }

    /** Helper function to resume video natively based on the active backend. */
    @:noCompletion
    private function _resumeNativeVideo():Void {
        #if (hxCodec >= "3.0.0" || hxvlc)
        resume();
        #elseif (hxCodec < "3.0.0" && hxCodec)
        bitmap.resume();
        #end
    }

    /** Helper function to pause video natively based on the active backend. */
    @:noCompletion
    private function _pauseNativeVideo():Void {
        #if (hxCodec >= "3.0.0" || hxvlc)
        pause();
        #elseif (hxCodec < "3.0.0" && hxCodec)
        bitmap.pause();
        #end
    }

    /**
     * Safely updates the paused state and manages FlxG focus signals to prevent
     * crashes and memory leaks when the app loses or gains focus.
     */
    @:noCompletion
    private function set_paused(shouldPause:Bool):Bool {
        if (shouldPause) {
            _pauseNativeVideo();
    
            // Safely remove global listeners when manually paused
            if (FlxG.autoPause) {
                if (FlxG.signals.focusGained.has(_resumeNativeVideo))
                    FlxG.signals.focusGained.remove(_resumeNativeVideo);
    
                if (FlxG.signals.focusLost.has(_pauseNativeVideo))
                    FlxG.signals.focusLost.remove(_pauseNativeVideo);
            }
        } else {
            _resumeNativeVideo();

            // Re-add focus listeners only if they don't already exist
            if (FlxG.autoPause) {
                if (!FlxG.signals.focusGained.has(_resumeNativeVideo))
                    FlxG.signals.focusGained.add(_resumeNativeVideo);
                
                if (!FlxG.signals.focusLost.has(_pauseNativeVideo))
                    FlxG.signals.focusLost.add(_pauseNativeVideo);
            }
        }
        
        paused = shouldPause;
        return paused;
    }

    @:noCompletion
    private function set_playbackRate(multi:EitherType<Single, Float>):EitherType<Single, Float> {
        bitmap.rate = multi;
        return multi;
    }

    @:noCompletion
    private function get_playbackRate():EitherType<Single, Float> {
        return bitmap.rate;
    }

    @:noCompletion
    private function get_onPlayState():Bool {
        return Std.isOfType(MusicBeatState.getState(), PlayState);
    }

    /**
     * Safely destroys the video sprite, ensuring all global signals are properly
     * unhooked to prevent memory leaks and null object references.
     */
    override public function destroy() {
        if (FlxG.signals.focusGained.has(_resumeNativeVideo))
            FlxG.signals.focusGained.remove(_resumeNativeVideo);
            
        if (FlxG.signals.focusLost.has(_pauseNativeVideo))
            FlxG.signals.focusLost.remove(_pauseNativeVideo);

        super.destroy();
    }

    /** Alternative destruction method that forces the end callback on older codecs. */
    public function altDestroy() {
        #if (hxCodec < "3.0.0" && hxCodec)
        bitmap.finishCallback = null;
        bitmap.onEndReached();
        #end
        destroy();
    }
}
#end