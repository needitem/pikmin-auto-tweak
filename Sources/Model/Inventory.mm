#import "Inventory.h"
#import "GameContext.h"
#import "Runtime.h"

void *pkInvList(const char *getter) {
    void *inv = pkInv();
    return inv ? pkInvoke(pkMethodOf(inv, getter, 0), inv, NULL) : NULL;
}
void *pkItemProto(void *item) { return pkCall0(item, "get_Proto"); }
NSString *pkItemId(void *item) { return pkStr(pkCall0(item, "get_Id")); }
