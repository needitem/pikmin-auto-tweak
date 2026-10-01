#import "Inventory.h"
#import "GameContext.h"
#import "Log.h"
#import "Runtime.h"

void *pkInvList(const char *getter) {
    void *inv = pkInv();
    return inv ? pkInvoke(pkMethodOf(inv, getter, 0), inv, NULL) : NULL;
}

// ---------- item.Proto / item.Id ----------
// Every scan reads these two for every item (hundreds of Pikmin, nectar
// stacks, petals, seeds), and each read was a reflective runtime_invoke. They
// are plain getters over a field, so once the field is known the read is a
// pointer load. The field is never assumed: for each item class it is looked
// up by name, and the direct read must agree with the getter on the first
// kProbe items before it is trusted. Trusted reads are still checked against
// the getter every kRecheck-th use, and a single disagreement sends that class
// back to the getter for good. If no field matches, the class stays on the
// getter and the log lists its fields so the name can be added.
static const int kProbe = 16;
static const int kRecheck = 512;

enum { kUnknown = 0, kProbing, kDirect, kGetter };

typedef struct {
    void *cls;
    const char *getter;               // "get_Proto" / "get_Id"
    ptrdiff_t off;
    int state, agreed;
    unsigned uses;
} Probe;

typedef struct { Probe proto, id; } Shape;

// Main thread only, like every scan (hooks never read items).
static const int kMaxShapes = 24;
static Shape gShapes[kMaxShapes];
static int gShapeCount = 0;

static Shape *shapeOf(void *cls) {
    for (int i = 0; i < gShapeCount; i++) if (gShapes[i].proto.cls == cls) return &gShapes[i];
    if (gShapeCount >= kMaxShapes) return NULL;
    Shape *s = &gShapes[gShapeCount++];
    *s = {};
    s->proto = { cls, "get_Proto", -1, kUnknown, 0, 0 };
    s->id    = { cls, "get_Id",    -1, kUnknown, 0, 0 };
    return s;
}

static ptrdiff_t findField(void *cls, const char *const *names) {
    for (; *names; names++) {
        ptrdiff_t off = -1;
        if (pkRefFieldOffsetByName(cls, *names, &off) && off >= 0x10 && off < 0x400) return off;
    }
    return -1;
}

static void giveUp(void *item, Probe *p, const char *what, const char *why) {
    p->state = kGetter;
    PALOG(@"[item] %@.%s: %@ — getter 사용. 필드: %@", pkClassName(item) ?: @"?", what,
          [NSString stringWithUTF8String:why], pkDescribeFields(p->cls));
    // One level down: what the item's reference fields actually hold, so the
    // field the getter reads can be named (RawProto wraps the typed proto).
    static NSMutableSet<NSValue *> *shown;
    if (!shown) shown = [NSMutableSet set];
    NSValue *key = [NSValue valueWithPointer:p->cls];
    if ([shown containsObject:key]) return;
    [shown addObject:key];
    pkEachRefField(item, ^(void *child) {
        PALOG(@"[item]   %@ → %@: %@", pkClassName(item) ?: @"?", pkClassName(child) ?: @"?", pkDescribeFields(pkClassOf(child)));
    });
}

// `direct` reads the candidate field; `same` compares it with the getter's answer.
template <typename Read, typename Same>
static void *fetch(void *item, Probe *p, const char *what, const char *const *names, Read direct, Same same) {
    if (p->state == kGetter) return pkCall0(item, p->getter);
    if (p->state == kUnknown) {
        p->off = findField(p->cls, names);
        if (p->off < 0) { giveUp(item, p, what, "일치하는 필드 이름 없음"); return pkCall0(item, p->getter); }
        p->state = kProbing;
    }
    void *viaGetter = NULL;
    BOOL check = p->state == kProbing || (++p->uses % kRecheck) == 0;
    if (!check) return direct(item, p->off);
    viaGetter = pkCall0(item, p->getter);
    void *viaField = direct(item, p->off);
    if (!same(viaField, viaGetter)) { giveUp(item, p, what, "필드 값이 getter와 다름"); return viaGetter; }
    if (p->state == kProbing && ++p->agreed >= kProbe) {
        p->state = kDirect;
        PALOG(@"[item] %@.%s 필드 직접 읽기 확정 (+0x%tx)", pkClassName(item) ?: @"?", what, p->off);
    }
    return viaGetter;
}

static void *readPtr(void *item, ptrdiff_t off) { return *(void **)((char *)item + off); }

void *pkItemProto(void *item) {
    if (!item) return NULL;
    static const char *const names[] = { "<Proto>k__BackingField", "proto_", "_proto", "Proto", "<proto>k__BackingField", "m_Proto", NULL };
    Shape *s = shapeOf(pkClassOf(item));
    if (!s) return pkCall0(item, "get_Proto");
    return fetch(item, &s->proto, "Proto", names, readPtr, [](void *a, void *b) { return a == b; });
}

NSString *pkItemId(void *item) {
    if (!item) return nil;
    static const char *const names[] = { "<Id>k__BackingField", "id_", "_id", "Id", "<id>k__BackingField", "m_Id", NULL };
    Shape *s = shapeOf(pkClassOf(item));
    if (!s) return pkStr(pkCall0(item, "get_Id"));
    // Strings are compared by content: the getter may hand back an equal copy.
    return pkStr(fetch(item, &s->id, "Id", names, readPtr, [](void *a, void *b) -> bool {
        if (a == b) return true;
        NSString *x = pkStr(a), *y = pkStr(b);
        return x && y && [x isEqualToString:y];
    }));
}
