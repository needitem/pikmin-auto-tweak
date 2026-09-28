#import "FrameRate.h"
#import "Log.h"
#import "Runtime.h"
#import "Settings.h"

static int wantedFps(void) {
    NSInteger v = [PKSettings integerForKey:kSettingFps];
    if (v <= 0) v = 20;                          // enough to stay usable if glanced at
    return (int)MIN(MAX(v, 5), 60);
}

void pkApplyFrameRate(BOOL automating) {
    if (!pkRuntimeReady()) return;
    void *app = pkClass("UnityEngine", "Application");
    void *quality = pkClass("UnityEngine", "QualitySettings");
    void *mGet = pkMethod(app, "get_targetFrameRate", 0);
    void *mSet = pkMethod(app, "set_targetFrameRate", 1);
    if (!mGet || !mSet) return;

    static int savedVSync = -1;                  // the game's own setting, kept while we override it
    int want = automating ? wantedFps() : -1;
    int cur = pkUnboxInt(pkInvoke(mGet, NULL, NULL));
    void *mVsGet = pkMethod(quality, "get_vSyncCount", 0);
    void *mVsSet = pkMethod(quality, "set_vSyncCount", 1);

    if (automating) {
        if (cur == want) return;
        if (mVsSet && mVsGet) {                  // a cap with vSync on does nothing
            if (savedVSync < 0) savedVSync = pkUnboxInt(pkInvoke(mVsGet, NULL, NULL));
            int zero = 0; void *a[1] = { &zero };
            pkInvoke(mVsSet, NULL, a);
        }
    } else {
        if (cur == want && savedVSync < 0) return;
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
