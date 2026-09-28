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

// MapObjectManager.MapObject.Proto is a Predicted<MapObjectProto>; the
// predicted side is what the map shows, with the confirmed one as fallback.
static NSArray<PKMapObject *> *scan(void) {
    void *mgr = pkMapObj();
    if (!mgr || !pkRuntimeReady()) return nil;
    void *dict = pkGetPtr(mgr, &F_MapMgr_objs);
    if (!dict) return nil;
    NSMutableArray<PKMapObject *> *out = [NSMutableArray array];
    pkDictEachValue(dict, ^(void *mo) {
        void *pred = pkGetPtr(mo, &F_MapObj_proto);
        void *proto = pkGetPtr(pred, &F_Pred_pred) ?: pkGetPtr(pred, &F_Pred_conf);
        if (!proto) return;
        NSString *oid = pkGetStr(proto, &F_MO_id);
        void *pt = pkGetPtr(proto, &F_MO_point);
        if (!oid.length || !pt) return;
        void *obj = pkGetPtr(proto, &F_MO_obj);
        PKMapObject *m = [PKMapObject new];
        m.oid = oid;
        m.kind = pkGetInt(proto, &F_MO_case);
        m.lat = pkGetF64(pt, &F_Pt_lat);
        m.lng = pkGetF64(pt, &F_Pt_lng);
        if (m.kind == PK_MO_POIFLOWER && obj) {
            m.state = pkGetInt(obj, &F_Poi_state);
            m.color = pkGetInt(pkGetPtr(obj, &F_Poi_app), &F_Fl_color);
            m.bloomMs = pkGetI64(obj, &F_Poi_bloomed);
            m.visited = pkGetBool(obj, &F_Poi_visited);
        } else if (m.kind == PK_MO_OVERLAY && obj) {
            m.state = pkGetInt(obj, &F_Ovl_state);
            m.color = pkGetInt(pkGetPtr(obj, &F_Ovl_flower), &F_Petal_color);
            m.bloomMs = pkGetI64(obj, &F_Ovl_bloom);
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
