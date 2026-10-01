#import "FrameRate.h"
#import "Log.h"
#import "Runtime.h"
#import "Settings.h"

// 0 (the default) means no cap: the game keeps its own frame rate. A capped
// game felt sluggish under the finger, and the phone is in hand most of the time.
static int wantedFps(void) {
    NSInteger v = [PKSettings integerForKey:kSettingFps];
    if (v <= 0) return 0;
    return (int)MIN(MAX(v, 5), 60);
}

void pkApplyFrameRate(BOOL automating) {
    static int savedVSync = -1;                  // the game's own settings, kept while we override them
    static int savedTarget = 0;                  // 0 = we have not capped anything
    int cap = automating ? wantedFps() : 0;
    if (!cap && !savedTarget) return;            // no cap wanted, none applied: the game's own frame rate is left alone
    if (!pkRuntimeReady()) return;
    void *app = pkClass("UnityEngine", "Application");
    void *quality = pkClass("UnityEngine", "QualitySettings");
    void *mGet = pkMethod(app, "get_targetFrameRate", 0);
    void *mSet = pkMethod(app, "set_targetFrameRate", 1);
    if (!mGet || !mSet) return;

    automating = cap > 0;
    int cur = pkUnboxInt(pkInvoke(mGet, NULL, NULL));
    int want = automating ? cap : savedTarget;
    void *mVsGet = pkMethod(quality, "get_vSyncCount", 0);
    void *mVsSet = pkMethod(quality, "set_vSyncCount", 1);

    if (automating) {
        if (cur == want) return;
        if (!savedTarget) savedTarget = cur > 0 ? cur : -1;
        if (mVsSet && mVsGet) {                  // a cap with vSync on does nothing
            if (savedVSync < 0) savedVSync = pkUnboxInt(pkInvoke(mVsGet, NULL, NULL));
            int zero = 0; void *a[1] = { &zero };
            pkInvoke(mVsSet, NULL, a);
        }
    } else {
        savedTarget = 0;
        if (savedVSync >= 0 && mVsSet) {
            void *a[1] = { &savedVSync };
            pkInvoke(mVsSet, NULL, a);
            savedVSync = -1;
        }
    }
    void *a[1] = { &want };
    pkInvoke(mSet, NULL, a);
    PALOG(@"[fps] 목표 프레임 %d → %d", cur, want);
}
