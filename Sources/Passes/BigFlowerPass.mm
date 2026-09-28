#import "Passes.h"
#import "Backoff.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Location.h"
#import "Log.h"
#import "MapObjects.h"
#import "RpcClient.h"

// PoiFlowerVisitRewardClaimer.CanTryClaim = IsBlooming && !VisitRewardReceived &&
// IsWithinRange && HasCapacity. The first three are checked from the map object
// and our own position; the server answers with FailedReason for the rest.
//
// The game's own range for a big flower is 100 m (DEFAULT_POI_FLOWER_RANGE;
// campaigns carry their own). The server judges range against the location the
// game last reported, not this instant's, so asking from 99 m out mostly
// failed: ask only from comfortably inside and ask again soon — the walk is
// routed past the flower, so a closer approach is coming.
static const double kRangeM = 100.0;
static const double kSendM = 65.0;
static const NSTimeInterval kRetry = 45.0;
static const NSTimeInterval kMaxLocationAge = 300.0;   // a spoofed fix may simply not change while standing still

static double distanceM(double lat1, double lng1, double lat2, double lng2) {
    const double r = 6371000.0, p = M_PI / 180.0;
    double dlat = (lat2 - lat1) * p, dlng = (lng2 - lng1) * p;
    double a = sin(dlat / 2) * sin(dlat / 2) + cos(lat1 * p) * cos(lat2 * p) * sin(dlng / 2) * sin(dlng / 2);
    return 2 * r * atan2(sqrt(a), sqrt(1 - a));
}

static PKBackoff *backoff(void) {
    static PKBackoff *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [[PKBackoff alloc] initWithBase:kRetry factor:1 max:kRetry]; });
    return b;
}

NSString *pkBigFlowerPass(void) {
    if (!pkMapObj()) return @"맵 오브젝트 대기";
    if (!pkRpc()) return @"서버 준비 대기";
    double mlat, mlng;
    if (!pkLocationGet(&mlat, &mlng)) return @"위치 대기";
    if (pkLocationAge() > kMaxLocationAge) return [NSString stringWithFormat:@"위치 %.0f초째 갱신 없음 — 대기", pkLocationAge()];

    NSArray<PKMapObject *> *objs = pkMapObjects();
    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    int nFlower = 0, nBloom = 0, nNear = 0, sent = 0;
    NSUInteger claimed = 0;
    for (PKMapObject *o in objs) {
        if (o.kind != PK_MO_POIFLOWER) continue;
        nFlower++;
        [alive addObject:o.oid];
        if (o.visited) claimed++;
        if (o.state != PK_FS_FLOWER && o.state != PK_FS_FULL_BLOOM) continue;
        nBloom++;
        if (o.visited) continue;
        double d = distanceM(mlat, mlng, o.lat, o.lng);
        if (d > kRangeM) continue;
        nNear++;
        if (d > kSendM || sent >= 2) continue;               // wait until closer / two per pass
        if (![backoff() ready:o.oid]) continue;
        // Fire and forget: the answer is read off the map object (the server sets
        // visitRewardReceived_).
        if (pkRpcClaimBigFlower(o.oid)) {
            sent++;
            [backoff() recordSend:o.oid];
            PALOG(@"[큰꽃] 정수 채집 요청 id=%@ state=%d color=%d dist=%.0fm", o.oid, o.state, o.color, d);
        }
    }
    [backoff() pruneKeeping:alive];

    static NSUInteger lastClaimed = 0;
    if (claimed != lastClaimed) {
        PALOG(@"[큰꽃] 채집 완료 표시 %lu → %lu", (unsigned long)lastClaimed, (unsigned long)claimed);
        lastClaimed = claimed;
    }
    return [NSString stringWithFormat:@"🌼 큰꽃 %d / 만개 %d / 사정권(≤%.0fm) %d / 요청(≤%.0fm) %d / 채집됨 %lu",
            nFlower, nBloom, kRangeM, nNear, kSendM, sent, (unsigned long)claimed];
}
