#import <AVFoundation/AVFoundation.h>

/// Godot 4.6 starts CoreAudio inside `Main::setup`, and only afterwards sets
/// `audio/general/ios/session_category`. Until the session is active,
/// `AVAudioSession.sampleRate` is 0, the driver refuses to start, and the game
/// stays silent. This runs when the app binary loads, before that setup.
static void activate_playback_session(void) {
	AVAudioSession *session = [AVAudioSession sharedInstance];
	NSError *error = nil;
	if (![session setCategory:AVAudioSessionCategoryPlayback error:&error]) {
		NSLog(@"AudioSession: setCategory failed: %@", error);
	}
	error = nil;
	if (![session setActive:YES error:&error]) {
		NSLog(@"AudioSession: setActive failed: %@", error);
	}
}

__attribute__((constructor)) static void audio_session_constructor(void) {
	activate_playback_session();
}

void audio_session_init(void) {
	activate_playback_session();
}

void audio_session_deinit(void) {
}
