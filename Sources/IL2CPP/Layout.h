// Every game field the tweak reads or writes, in one table.
//
// Fields are located BY NAME on the object's own class, so a game update that
// shifts offsets keeps working. The offset from the reference dump is only a
// fallback, and only while the layout is trusted:
//   - first run after install, or the game build is unchanged  -> trusted;
//   - the build changed -> untrusted until at least 8 name-resolved fields all
//     agree with the dump (then the rest of the dump is believed too).
// While untrusted, a field that cannot be found by name fails closed: reads
// return zero/NULL and pkLayoutHealthy() turns false, which pauses every pass.
#pragma once
#import "Runtime.h"

//       id            il2cpp name                       alt name   dump offset
#define PK_LAYOUT(X) \
    /* PikminManager / Pikmin */ \
    X(Mgr_inv,        "inventoryManager",                NULL,      0x30) \
    X(Mgr_squad,      "playerFollowingPikmins",          NULL,      0x68) \
    X(Pik_proto,      "pikminProto",                     NULL,      0xC0) \
    /* PikminProto and the objects it points at */ \
    X(PP_type,        "pikminType_",                     NULL,      0x18) \
    X(PP_id,          "id_",                             NULL,      0x28) \
    X(PP_name,        "name_",                           NULL,      0x30) \
    X(PP_steps,       NULL,                              NULL,      0x40) \
    X(PP_flowerState, "flowerState_",                    NULL,      0x48) \
    X(PP_flowerCount, "flowerStateFlowerCount_",         NULL,      0x58) \
    X(PP_wilted,      "wiltedCount_",                    NULL,      0x5C) \
    X(PP_bloom,       "bloomingFlower_",                 NULL,      0x78) \
    X(PP_starred,     "starred_",                        NULL,      0x98) \
    X(PP_pluck,       "pluckTime_",                      NULL,      0xA0) \
    X(PP_friend,      "friendship_",                     NULL,      0xB0) \
    X(PP_status,      "statusCase_",                     NULL,      0xD0) \
    X(Ts_ms,          "utcTimeMs_",                      NULL,      0x18) \
    X(PT_type,        "type_",                           NULL,      0x18) \
    X(PT_category,    "categoryId_",                     NULL,      0x1C) \
    X(PT_asset,       "fullAssetId_",                    NULL,      0x20) \
    X(Fr_points,      NULL,                              NULL,      0x18) \
    X(Fr_hearts,      "numHearts_",                      NULL,      0x1C) \
    X(Fl_color,       "color_",                          NULL,      0x18) \
    X(Fl_kind,        "flowerKind_",                     NULL,      0x1C) \
    /* InventoryManager and its storages */ \
    X(Inv_honey,      NULL,                              NULL,      0x48) \
    X(Inv_capacity,   "itemCapacityInventoryItemStorage",NULL,      0x158) \
    X(Stor_items,     "Items",                           NULL,      0x10) \
    X(Pred_conf,      "confirmedValue",                  NULL,      0x10) \
    X(Pred_pred,      "predictedValue",                  NULL,      0x18) \
    /* nectar */ \
    X(HB_balls,       "numBalls_",                       NULL,      0x18) \
    X(HB_type,        "honeyType_",                      NULL,      0x1C) \
    X(HB_hkind,       "honeyFlowerKind_",                NULL,      0x20) \
    X(HB_fkind,       "flowerKind_",                     NULL,      0x28) \
    X(Ex_color,       "extractType",                     NULL,      0x20) \
    X(Ex_kind,        "flowerKind",                      NULL,      0x28) \
    X(Ex_hbt,         "honeyBallType",                   NULL,      0x60) \
    X(FK_id,          NULL,                              NULL,      0x18) \
    X(FK_kind,        NULL,                              NULL,      0x20) \
    X(HBT_hkind,      "honeyFlowerKind_",                NULL,      0x1C) \
    X(HBT_fkind,      "flowerKind_",                     NULL,      0x20) \
    /* petals and capacity */ \
    X(Petal_color,    "flowerType_",                     NULL,      0x18) \
    X(Petal_kind,     "kind_",                           NULL,      0x1C) \
    X(Petal_num,      "numPetal_",                       NULL,      0x20) \
    X(Petal_fkind,    "flowerKind_",                     NULL,      0x28) \
    X(Cap_petal,      "petal_",                          NULL,      0x28) \
    X(Cap_cur,        "currentCount_",                   NULL,      0x18) \
    X(Cap_pur,        "purchasedCount_",                 NULL,      0x1C) \
    /* tasks and expeditions */ \
    X(Task_start,     "startTimeMs_",                    NULL,      0x18) \
    X(Task_finish,    "finishTimeMs_",                   NULL,      0x20) \
    X(Task_pikmin,    "pikminId_",                       NULL,      0x28) \
    X(Task_case,      "taskCase_",                       NULL,      0x50) \
    X(ExpStore_cache, "cache",                           NULL,      0x18) \
    X(ExpItem_item,   "item",                            NULL,      0x78) \
    X(Tools_settings, "clientSettingsCache",             NULL,      0x18) \
    X(CS_pikmin,      "pikmin_",                         NULL,      0x78) \
    X(PS_minTroop,    "minTroopPikminCount_",            NULL,      0x1C) \
    /* planting, seedlings, planters */ \
    X(Plant_started,  "isStarted",                       NULL,      0x118) \
    X(Seed_birth,     "birthPlacePoint_",                NULL,      0x28) \
    X(Seed_req,       "requiredSteps_",                  NULL,      0x50) \
    X(Seed_cur,       "currentSteps_",                   NULL,      0x54) \
    X(Seed_bonus,     "currentBonusSteps_",              NULL,      0x58) \
    X(Seed_planted,   "plantedTimeMs_",                  NULL,      0x60) \
    X(Planter_slots,  "slot_",                           NULL,      0x20) \
    X(Slot_seed,      "pikminSeedId_",                   NULL,      0x18) \
    X(Slot_remain,    "remainingUse_",                   NULL,      0x20) \
    X(Slot_index,     "index_",                          NULL,      0x24) \
    X(Slot_type,      "slotType_",                       NULL,      0x28) \
    /* map objects */ \
    X(MapMgr_objs,    "mapObjects",                      NULL,      0x70) \
    X(MapObj_proto,   "Proto",                "<Proto>k__BackingField", 0x10) \
    X(MO_id,          "id_",                             NULL,      0x18) \
    X(MO_point,       "point_",                          NULL,      0x20) \
    X(MO_obj,         "object_",                         NULL,      0x30) \
    X(MO_case,        "objectCase_",                     NULL,      0x38) \
    X(Pt_lat,         "latDegrees_",                     NULL,      0x18) \
    X(Pt_lng,         "lngDegrees_",                     NULL,      0x20) \
    X(Poi_state,      "state_",                          NULL,      0x18) \
    X(Poi_app,        "appearance_",                     NULL,      0x20) \
    X(Poi_bloomed,    "bloomedTimeMs_",                  NULL,      0x40) \
    X(Poi_visited,    "visitRewardReceived_",            NULL,      0x48) \
    X(Ovl_state,      "state_",                          NULL,      0x18) \
    X(Ovl_flower,     "flower_",                         NULL,      0x20) \
    X(Ovl_bloom,      "lastBloomingMs_",                 NULL,      0x28) \
    /* requests we fill by field (no setter is used) */ \
    X(Complete_taskId,"pikminTaskId_",                   NULL,      0x18) \
    X(Claim_id,       "mapObjectId_",                    NULL,      0x18) \
    X(Claim_fail,     "includeFailedReason_",            NULL,      0x20) \
    X(SetSeed_id,     "seedId_",                         NULL,      0x18) \
    X(SetSeed_point,  "point_",                          NULL,      0x20) \
    /* request logging (debug hooks only) */ \
    X(FeedReq_ids,    "pikminId_",                       NULL,      0x18) \
    X(FeedReq_item,   "itemId_",                         NULL,      0x20) \
    X(FeedReq_num,    "numItems_",                       NULL,      0x28) \
    X(PickReq_ids,    "pikminId_",                       NULL,      0x18) \
    X(SeedReq_id,     "seedId_",                         NULL,      0x18) \
    X(SeedReq_point,  "point_",                          NULL,      0x20) \
    /* collections (name only; the corlib picks the spelling) */ \
    X(List_items,     "_items",                          NULL,      0x10) \
    X(List_size,      "_size",                           NULL,      0x18) \
    X(Rep_array,      "array",                           NULL,      -1) \
    X(Rep_count,      "count",                           "_count",  -1) \
    X(Dict_entries,   "_entries",                        "entries", -1) \
    X(Dict_count,     "_count",                          "count",   -1)

#define PK_DECLARE_FIELD(id, n, a, fb) extern PKField F_##id;
PK_LAYOUT(PK_DECLARE_FIELD)
#undef PK_DECLARE_FIELD

void pkLayoutInit(void);       // decide trust from the game build; call once, early
BOOL pkLayoutHealthy(void);    // false while any field is unresolvable

// Typed access. A NULL object, or a field that cannot be resolved, reads as 0/NULL.
void     *pkGetPtr(void *obj, PKField *f);
int       pkGetInt(void *obj, PKField *f);
long long pkGetI64(void *obj, PKField *f);
float     pkGetF32(void *obj, PKField *f);
double    pkGetF64(void *obj, PKField *f);
BOOL      pkGetBool(void *obj, PKField *f);
NSString *pkGetStr(void *obj, PKField *f);
void      pkSetRef(void *obj, PKField *f, void *value);
void      pkSetBool(void *obj, PKField *f, BOOL value);
void      pkSetF64(void *obj, PKField *f, double value);
