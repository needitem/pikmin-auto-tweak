// List<T>, RepeatedField<T> and Dictionary<K,V> readers. The only place that
// knows the managed array header (data starts 0x20 into an Il2CppArray) and
// the Dictionary entry shape.
#import "Layout.h"

static const size_t kArrayData = 0x20;
static const int kMaxItems = 200000;

void pkListEach(void *list, void (^fn)(void *item)) {
    int size = pkListCount(list);
    void *arr = pkGetPtr(list, &F_List_items);
    if (!arr || size <= 0) return;
    void **data = (void **)((char *)arr + kArrayData);
    for (int i = 0; i < size; i++) if (data[i]) fn(data[i]);
}

int pkListCount(void *list) {
    int n = pkGetInt(list, &F_List_size);
    return (n < 0 || n > kMaxItems) ? 0 : n;
}

int pkRepeatedCount(void *rf) {
    int n = pkGetInt(rf, &F_Rep_count);
    return (n < 0 || n > kMaxItems) ? 0 : n;
}

void pkRepeatedEach(void *rf, void (^fn)(void *item)) {
    int n = pkRepeatedCount(rf);
    void *arr = pkGetPtr(rf, &F_Rep_array);
    if (!arr || n <= 0) return;
    void **data = (void **)((char *)arr + kArrayData);
    for (int i = 0; i < n; i++) if (data[i]) fn(data[i]);
}

void pkRepeatedAdd(void *rf, void *item) {
    if (!rf) return;
    void *a[1] = { item };
    pkInvoke(pkMethodOf(rf, "Add", 1), rf, a);
}

void pkRepeatedClear(void *rf) {
    if (rf) pkInvoke(pkMethodOf(rf, "Clear", 0), rf, NULL);
}

// Dictionary<string, TRef>: Entry {int hash; int next; TKey key @8; TValue value @0x10}, stride 0x18.
// A live slot is recognised by a non-null value, which holds for both the
// .NET Framework and Core entry conventions (removed entries are zeroed).
void pkDictEachValue(void *dict, void (^fn)(void *value)) {
    void *entries = pkGetPtr(dict, &F_Dict_entries);
    int count = pkGetInt(dict, &F_Dict_count);
    if (!entries || count <= 0 || count > kMaxItems) return;
    char *data = (char *)entries + kArrayData;
    for (int i = 0; i < count; i++) {
        void *v = *(void **)(data + (size_t)i * 0x18 + 0x10);
        if (v) fn(v);
    }
}
