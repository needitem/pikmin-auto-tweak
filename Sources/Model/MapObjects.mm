#import "MapObjects.h"
#import "Clock.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Layout.h"

@implementation PKMapObject
@end

static NSArray<PKMapObject *> *gCache = nil;
static NSTimeInterval gCacheAt = 0;
static const NSTimeInterval kMapTtl = 4.0;

// Only big flowers and mushrooms are read: they are all the passes and the map
// dump use, and the manager holds hundreds of other objects, each of which used
// to cost a string, an object and a dozen field reads on every scan.
static BOOL wanted(int kind) { return kind == PK_MO_POIFLOWER || kind == PK_MO_MUSHROOM; }

// MapObjectManager.MapObject.Proto is a Predicted<MapObjectProto>; the
// predicted side is what the map shows, with the confirmed one as fallback.
static NSArray<PKMapObject *> *scan(void) {
    void *mgr = pkMapObj();
    if (!mgr || !pkRuntimeReady()) return nil;
    void *dict = pkGetPtr(mgr, &F_MapMgr_objs);
    if (!dict) return nil;
    NSMutableArray<PKMapObject *> *out = [NSMutableArray arrayWithCapacity:64];
    pkDictEachValue(dict, ^(void *mo) {
        void *pred = pkGetPtr(mo, &F_MapObj_proto);
        void *proto = pkGetPtr(pred, &F_Pred_pred) ?: pkGetPtr(pred, &F_Pred_conf);
        if (!proto) return;
        int kind = pkGetInt(proto, &F_MO_case);
        if (!wanted(kind)) return;
        NSString *oid = pkGetStr(proto, &F_MO_id);
        void *pt = pkGetPtr(proto, &F_MO_point);
        if (!oid.length || !pt) return;
        void *obj = pkGetPtr(proto, &F_MO_obj);
        PKMapObject *m = [PKMapObject new];
        m.oid = oid;
        m.kind = kind;
        m.lat = pkGetF64(pt, &F_Pt_lat);
        m.lng = pkGetF64(pt, &F_Pt_lng);
        if (m.kind == PK_MO_POIFLOWER && obj) {
            m.state = pkGetInt(obj, &F_Poi_state);
            m.color = pkGetInt(pkGetPtr(obj, &F_Poi_app), &F_Fl_color);
            m.bloomMs = pkGetI64(obj, &F_Poi_bloomed);
            m.visited = pkGetBool(obj, &F_Poi_visited);
        }
        [out addObject:m];
    });
    return out;
}

NSArray<PKMapObject *> *pkMapObjects(void) {
    NSTimeInterval now = pkMono();
    if (gCache && now - gCacheAt < kMapTtl) return gCache;
    gCache = scan();
    gCacheAt = now;
    return gCache;
}
