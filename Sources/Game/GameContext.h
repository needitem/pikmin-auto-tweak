// The live game singletons the hooks capture (Zenject builds them; we only
// ever see them by hooking one of their methods). Each is pinned with a GC
// handle so the collector cannot free it under us, and REPLACED when the game
// hands us a different instance (re-login, scene reload) instead of keeping
// the first one forever.
#pragma once
#import <Foundation/Foundation.h>

typedef enum {
    PKS_RPC,        // RpcManager
    PKS_MGR,        // PikminManager
    PKS_ACTION,     // PikminActionManager
    PKS_EXPSTORE,   // ExpeditionDataStore
    PKS_TOOLS,      // PikminInventoryTools
    PKS_PLANT,      // FlowerPlantingController
    PKS_MAPOBJ,     // MapObjectManager
    PKS_EXTRACT,    // ExtractSelectionTracker
    PKS_COUNT
} PKSlotId;

void pkCapture(PKSlotId slot, void *instance, const char *via);   // any thread
void *pkGet(PKSlotId slot);

static inline void *pkRpc(void)      { return pkGet(PKS_RPC); }
static inline void *pkMgr(void)      { return pkGet(PKS_MGR); }
static inline void *pkAction(void)   { return pkGet(PKS_ACTION); }
static inline void *pkExpStore(void) { return pkGet(PKS_EXPSTORE); }
static inline void *pkTools(void)    { return pkGet(PKS_TOOLS); }
static inline void *pkPlant(void)    { return pkGet(PKS_PLANT); }
static inline void *pkMapObj(void)   { return pkGet(PKS_MAPOBJ); }
static inline void *pkExtract(void)  { return pkGet(PKS_EXTRACT); }

// InventoryManager, reached through the PikminManager.
void *pkInv(void);
