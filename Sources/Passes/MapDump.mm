#import "Passes.h"
#import "ChangeGate.h"
#import "Clock.h"
#import "GameConstants.h"
#import "Location.h"
#import "Log.h"
#import "MapObjects.h"
#import "SharedFile.h"

// mapobjects.json, for GPS Wander's routing: only the kinds it can use, big
// flowers and mushrooms. Rewritten only when they changed (our own position,
// which moves constantly, is not part of the comparison) or once a minute.
static const NSTimeInterval kMinRewrite = 60.0;

static BOOL wanted(PKMapObject *o) { return o.kind == PK_MO_POIFLOWER || o.kind == PK_MO_MUSHROOM; }

static uint64_t signatureOf(NSArray<PKMapObject *> *objs) {
    uint64_t sig = kPKHashSeed;
    for (PKMapObject *o in objs) {
        if (!wanted(o)) continue;
        const char *id = o.oid.UTF8String;
        struct { int kind, state, color, visited; double lat, lng; long long bloom; } v =
            { o.kind, o.state, o.color, o.visited, o.lat, o.lng, o.bloomMs };
        sig = pkHash(pkHash(sig, id, strlen(id)), &v, sizeof v);
    }
    return sig;
}

void pkMapDumpPass(void) {
    NSArray<PKMapObject *> *objs = pkMapObjects();
    if (!objs) return;
    static PKChangeGate gate;
    if (pkChangeGateSkip(&gate, signatureOf(objs), pkMono(), kMinRewrite)) return;

    NSMutableArray *rows = [NSMutableArray array];
    for (PKMapObject *o in objs) {
        if (!wanted(o)) continue;
        [rows addObject:@{ @"id": o.oid, @"kind": @(o.kind), @"lat": @(o.lat), @"lng": @(o.lng),
                           @"state": @(o.state), @"color": @(o.color), @"bloom": @(o.bloomMs), @"visited": @(o.visited) }];
    }
    double lat = 0, lng = 0; pkLocationGet(&lat, &lng);
    NSDictionary *doc = @{ @"t": @([NSDate date].timeIntervalSince1970), @"lat": @(lat), @"lng": @(lng), @"objs": rows };
    NSData *json = [NSJSONSerialization dataWithJSONObject:doc options:0 error:nil];
    if (!json) return;
    static int sharedState = -1;
    BOOL ok = pkWriteShared(@"mapobjects.json", json);
    if ((int)ok != sharedState) {
        sharedState = ok;
        PALOG(@"[map] %lu개 기록, 공유 경로 %@", (unsigned long)rows.count, ok ? @"성공" : @"거부(Documents로 대체)");
    }
}
