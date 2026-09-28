#import "GameContext.h"
#import "Layout.h"
#import "Log.h"
#import <os/lock.h>

static const char *const kSlotNames[PKS_COUNT] = {
    "RpcManager", "PikminManager", "PikminActionManager", "ExpeditionDataStore",
    "PikminInventoryTools", "FlowerPlantingController", "MapObjectManager", "ExtractSelectionTracker",
};

static struct { void *ptr; uint32_t handle; } gSlots[PKS_COUNT];
static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;

void *pkGet(PKSlotId slot) { return __atomic_load_n(&gSlots[slot].ptr, __ATOMIC_ACQUIRE); }

void pkCapture(PKSlotId slot, void *instance, const char *via) {
    if (!instance || pkGet(slot) == instance) return;        // hot path: no lock
    void *old; uint32_t oldHandle;
    os_unfair_lock_lock(&gLock);
    old = gSlots[slot].ptr; oldHandle = gSlots[slot].handle;
    BOOL changed = old != instance;
    if (changed) {
        gSlots[slot].handle = pkGcPin(instance);
        __atomic_store_n(&gSlots[slot].ptr, instance, __ATOMIC_RELEASE);
    }
    os_unfair_lock_unlock(&gLock);
    if (!changed) return;
    pkGcUnpin(oldHandle);
    PKLOGC([@"capture." stringByAppendingString:@(kSlotNames[slot])],
           [NSString stringWithFormat:@"[capture] %s=%p (%s)%@", kSlotNames[slot], instance, via,
            old ? [NSString stringWithFormat:@" — 이전 %p 교체", old] : @""]);
}

void *pkInv(void) { return pkGetPtr(pkMgr(), &F_Mgr_inv); }
