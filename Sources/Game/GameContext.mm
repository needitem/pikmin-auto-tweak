#import "GameContext.h"
#import "Layout.h"
#import "Log.h"

static const char *const kSlotNames[PKS_COUNT] = {
    "RpcManager", "PikminManager", "PikminActionManager", "ExpeditionDataStore",
    "PikminInventoryTools", "FlowerPlantingController", "MapObjectManager", "ExtractSelectionTracker",
};

static struct { void *ptr; uint32_t handle; } gSlots[PKS_COUNT];     // published: what the passes see (main thread writes)
static void *gPending[PKS_COUNT];                                     // seen by a hook, not yet adopted (any thread writes)
static const char *gVia[PKS_COUNT];

void *pkGet(PKSlotId slot) { return __atomic_load_n(&gSlots[slot].ptr, __ATOMIC_ACQUIRE); }

// Runs inside the game's own calls, on whatever thread made them — sometimes in
// the middle of a constructor, sometimes while the app is going to the
// background — so it does the least possible: remember the pointer. No lock,
// no il2cpp call (a GC-handle call from here is what crashed the game, inside
// the PikminActionManager constructor hook), no logging, no allocation.
void pkCapture(PKSlotId slot, void *instance, const char *via) {
    if (!instance || pkGet(slot) == instance) return;        // hot path
    __atomic_store_n(&gVia[slot], via, __ATOMIC_RELAXED);
    __atomic_store_n(&gPending[slot], instance, __ATOMIC_RELEASE);
}

// Main thread, between passes (never inside one): pin what the hooks saw, make it
// visible, release the instance it replaces. Passes therefore never see a
// singleton change under them, even when a request they send makes the game
// call a hooked method.
void pkAdoptCaptured(void) {
    for (int slot = 0; slot < PKS_COUNT; slot++) {
        void *instance = __atomic_exchange_n(&gPending[slot], NULL, __ATOMIC_ACQ_REL);
        if (!instance || gSlots[slot].ptr == instance) continue;
        void *old = gSlots[slot].ptr; uint32_t oldHandle = gSlots[slot].handle;
        gSlots[slot].handle = pkGcPin(instance);
        __atomic_store_n(&gSlots[slot].ptr, instance, __ATOMIC_RELEASE);
        pkGcUnpin(oldHandle);
        PKLOGC([@"capture." stringByAppendingString:@(kSlotNames[slot])],
               [NSString stringWithFormat:@"[capture] %s=%p (%s)%@", kSlotNames[slot], instance, __atomic_load_n(&gVia[slot], __ATOMIC_RELAXED),
                old ? [NSString stringWithFormat:@" — 이전 %p 교체", old] : @""]);
    }
}

void *pkInv(void) { return pkGetPtr(pkMgr(), &F_Mgr_inv); }
