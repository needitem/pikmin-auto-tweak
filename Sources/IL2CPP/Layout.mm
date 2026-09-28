#import "Layout.h"
#import "Log.h"
#import "Settings.h"
#import <os/lock.h>

void *pkRawFieldOffsetByName(void *cls, const char *name, ptrdiff_t *off);   // Runtime.mm

#define PK_DEFINE_FIELD(id, n, a, fb) PKField F_##id = PKF(n, a, fb);
PK_LAYOUT(PK_DEFINE_FIELD)
#undef PK_DEFINE_FIELD

static NSString * const kLayoutBuildKey = @"pa_layout_build";
static const int kTrustAfterMatches = 8;

static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;
static BOOL gTrustFallback = YES;
static int gMatched = 0, gMismatched = 0, gMissing = 0;
static NSString *gBuild = nil;

void pkLayoutInit(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    gBuild = [NSString stringWithFormat:@"%@(%@)", info[@"CFBundleShortVersionString"] ?: @"?",
              info[@"CFBundleVersion"] ?: @"?"];
    NSString *seen = [PKSettings stringForKey:kLayoutBuildKey];
    if (!seen) {
        [PKSettings setString:gBuild forKey:kLayoutBuildKey];   // first run: the dump is assumed to fit
        gTrustFallback = YES;
    } else {
        gTrustFallback = [seen isEqualToString:gBuild];
    }
    if (gTrustFallback) PALOG(@"[layout] 게임 빌드 %@ — 덤프 오프셋 신뢰", gBuild);
    else PALOG(@"[layout] 게임 빌드 변경 %@ → %@ — 이름으로 찾은 필드 8개가 덤프와 일치하기 전까지 이름 없는 필드는 비활성", seen, gBuild);
}

BOOL pkLayoutHealthy(void) {
    os_unfair_lock_lock(&gLock);
    BOOL ok = gMissing == 0;
    os_unfair_lock_unlock(&gLock);
    return ok;
}

// Lock held by caller.
static void noteMatchLocked(BOOL match) {
    if (match) gMatched++; else gMismatched++;
    if (!gTrustFallback && gMismatched == 0 && gMatched >= kTrustAfterMatches) {
        gTrustFallback = YES;
        [PKSettings setString:gBuild forKey:kLayoutBuildKey];
        PALOG(@"[layout] 이름 해석 %d개가 덤프와 일치 — 새 빌드 %@ 신뢰", gMatched, gBuild);
    }
}

static BOOL resolve(void *obj, PKField *f) {
    if (f->off >= 0) return YES;
    void *cls = pkClassOf(obj);
    if (!cls) return NO;

    os_unfair_lock_lock(&gLock);
    if (f->off >= 0) { os_unfair_lock_unlock(&gLock); return YES; }
    BOOL wasMissing = (f->off == -1);

    ptrdiff_t byName = -1;
    if (f->name && !pkRawFieldOffsetByName(cls, f->name, &byName)) byName = -1;
    if (byName < 0 && f->alt && !pkRawFieldOffsetByName(cls, f->alt, &byName)) byName = -1;

    NSString *log = nil;
    BOOL ok = YES;
    if (byName >= 0) {
        f->off = byName;
        if (f->fallback >= 0) {
            noteMatchLocked(byName == f->fallback);
            if (byName != f->fallback) {
                // Same build as the dump: the dump is right by definition, so a
                // disagreeing name is a wrong guess at the name. After a game
                // update the dump is what is stale, so the name wins.
                if (gTrustFallback) f->off = f->fallback;
                log = [NSString stringWithFormat:@"[layout] %s: 이름 해석 0x%tx ≠ 덤프 0x%tx (%@ 사용)", f->name, byName, f->fallback,
                       gTrustFallback ? @"덤프값 — 이름이 잘못된 듯" : @"이름값 — 게임이 바뀐 듯"];
            }
        }
    } else if (f->fallback >= 0 && gTrustFallback) {
        f->off = f->fallback;
    } else {
        if (!wasMissing) {
            f->off = -1; gMissing++;
            log = [NSString stringWithFormat:@"[layout] %s 해석 실패 (덤프 오프셋 %s) — 이 필드를 쓰는 기능은 멈춤",
                   f->name ?: "(이름 없음)", gTrustFallback ? "없음" : "미신뢰"];
        }
        ok = NO;
    }
    if (ok && wasMissing) gMissing--;
    os_unfair_lock_unlock(&gLock);
    if (log) PALOG(@"%@", log);
    return ok;
}

// A field that failed while untrusted is retried once trust arrives (resolve()
// sees off == -1 and takes the fallback branch).
static inline char *at(void *obj, PKField *f) {
    return (obj && resolve(obj, f)) ? (char *)obj + f->off : NULL;
}

void *pkGetPtr(void *obj, PKField *f)      { char *p = at(obj, f); return p ? *(void **)p : NULL; }
int pkGetInt(void *obj, PKField *f)        { char *p = at(obj, f); return p ? *(int *)p : 0; }
long long pkGetI64(void *obj, PKField *f)  { char *p = at(obj, f); return p ? *(long long *)p : 0; }
float pkGetF32(void *obj, PKField *f)      { char *p = at(obj, f); return p ? *(float *)p : 0; }
double pkGetF64(void *obj, PKField *f)     { char *p = at(obj, f); return p ? *(double *)p : 0; }
BOOL pkGetBool(void *obj, PKField *f)      { char *p = at(obj, f); return p ? *(unsigned char *)p != 0 : NO; }
NSString *pkGetStr(void *obj, PKField *f)  { return pkStr(pkGetPtr(obj, f)); }
void pkSetRef(void *obj, PKField *f, void *v)   { char *p = at(obj, f); if (p) pkWriteRef(obj, (void **)p, v); }
void pkSetBool(void *obj, PKField *f, BOOL v)   { char *p = at(obj, f); if (p) *(unsigned char *)p = v ? 1 : 0; }
void pkSetF64(void *obj, PKField *f, double v)  { char *p = at(obj, f); if (p) *(double *)p = v; }
