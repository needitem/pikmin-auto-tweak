#import "Passes.h"
#import "Clock.h"
#import "GameConstants.h"
#import "GameContext.h"
#import "Location.h"
#import "Log.h"
#import "MapObjects.h"
#import "Roster.h"
#import "SharedFile.h"
#import <cmath>
#import <string>

// Both dumps rewrite only when their content changed (position, which moves
// constantly, is not part of the comparison) or once a minute regardless. The
// first cut wrote ~580 objects every five seconds and drew an iOS diskwrites
// report; the walk needs a couple of kilobytes a minute.
static const NSTimeInterval kMinRewrite = 60.0;

// Change detection by a 64-bit FNV-1a over the fields that matter. It used to be
// a full JSON serialisation of every row just to be compared and thrown away,
// which for 600+ Pikmin cost more than the file write it was avoiding.
// A false "unchanged" (a collision) only delays a rewrite until the minute gate.
static uint64_t fnv(uint64_t h, const void *p, size_t n) {
    const unsigned char *b = (const unsigned char *)p;
    while (n--) { h ^= *b++; h *= 0x100000001b3ULL; }
    return h;
}
static const uint64_t kFnvBasis = 0xcbf29ce484222325ULL;

static BOOL unchanged(uint64_t sig, uint64_t *last, BOOL *haveLast, NSTimeInterval *lastWrite) {
    NSTimeInterval t = pkMono();
    if (*haveLast && *last == sig && t - *lastWrite < kMinRewrite) return YES;
    *last = sig; *haveLast = YES; *lastWrite = t;
    return NO;
}

// ---------- map objects, for GPS Wander's routing ----------
// Only the kinds it can use: big flowers and mushrooms.
void pkMapDumpPass(void) {
    NSArray<PKMapObject *> *objs = pkMapObjects();
    if (!objs) return;
    uint64_t sig = kFnvBasis;
    for (PKMapObject *o in objs) {
        if (o.kind != PK_MO_POIFLOWER && o.kind != PK_MO_MUSHROOM) continue;
        const char *id = o.oid.UTF8String;
        struct { int kind, state, color, visited; double lat, lng; long long bloom; } v =
            { o.kind, o.state, o.color, o.visited, o.lat, o.lng, o.bloomMs };
        sig = fnv(fnv(sig, id, strlen(id)), &v, sizeof v);
    }
    static uint64_t last; static BOOL haveLast; static NSTimeInterval lastWrite;
    if (unchanged(sig, &last, &haveLast, &lastWrite)) return;

    NSMutableArray *rows = [NSMutableArray array];
    for (PKMapObject *o in objs) {
        if (o.kind != PK_MO_POIFLOWER && o.kind != PK_MO_MUSHROOM) continue;
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

// ---------- roster (for planning mushroom battles) ----------
static const char *const kColorNames[9] = { "미상", "빨강", "파랑", "노랑", "하양", "보라", "바위", "날개", "얼음" };
static int colorIdx(int c) { return (c >= 1 && c <= 8) ? c : 0; }
static int flowerIdx(int s) { return s == PK_PF_FLOWER ? 0 : s == PK_PF_BUD ? 1 : s == PK_PF_LEAF ? 2 : 3; }
static const char *flowerName(int s) {
    switch (s) { case PK_PF_LEAF: return "잎"; case PK_PF_BUD: return "봉우리"; case PK_PF_FLOWER: return "꽃";
        case PK_PF_PICK: return "수확대기"; case PK_PF_WILTED: return "시듦"; }
    return "?";
}
static int statusIdx(int s) { return s == PK_STATUS_AVAILABLE ? 0 : s == PK_STATUS_TASK ? 1 : s == PK_STATUS_ENTOURAGE ? 2 : -1; }
static const char *const kStatusNames[3] = { "대기", "작업중", "동행" };

// JSON string body (no quotes): the characters JSON requires escaped.
static void appendEscaped(std::string &out, const char *u) {
    for (; u && *u; u++) {
        unsigned char c = (unsigned char)*u;
        if (c == '"' || c == '\\') { out += '\\'; out += (char)c; }
        else if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); out += b; }
        else out += (char)c;
    }
}

void pkRosterDumpPass(void) {
    NSArray<PKPikmin *> *all = pkRoster();
    if (!all) return;

    // Walking changes `steps` constantly, so it stays out of the change check.
    uint64_t sig = kFnvBasis;
    for (PKPikmin *p in all) {
        const char *name = p.name.UTF8String ?: "";
        sig = fnv(sig, name, strlen(name) + 1);
        int v[8] = { p.color, p.flowerState, p.status, 0, p.heartPoints, p.asset, p.category, p.starred };
        float h = p.hearts; memcpy(&v[3], &h, sizeof h);
        sig = fnv(sig, v, sizeof v);
    }
    static uint64_t last; static BOOL haveLast; static NSTimeInterval lastWrite;
    if (unchanged(sig, &last, &haveLast, &lastWrite)) return;

    int byColor[9] = {0}, byStatus[3] = {0}, flowered[9][4] = {{0}};
    int starred = 0, decor = 0;
    std::string rows;
    rows.reserve(all.count * 190);
    BOOL first = YES;
    char buf[320];
    for (PKPikmin *p in all) {
        int ci = colorIdx(p.color), si = statusIdx(p.status);
        byColor[ci]++;
        if (si >= 0) byStatus[si]++;
        flowered[ci][flowerIdx(p.flowerState)]++;
        if (p.starred) starred++;
        if (p.isDecor) decor++;
        rows += first ? "\n" : ",\n"; first = NO;
        rows += "{\"name\":\"";
        appendEscaped(rows, p.name.UTF8String);
        snprintf(buf, sizeof buf,
                 "\",\"color\":%d,\"colorName\":\"%s\",\"flower\":%d,\"flowerName\":\"%s\",\"status\":%d,\"statusName\":\"%s\","
                 "\"hearts\":%.6g,\"fpt\":%d,\"asset\":%d,\"category\":%d,\"deco\":%s,\"starred\":%s,\"steps\":%lld}",
                 p.color, kColorNames[ci], p.flowerState, flowerName(p.flowerState), p.status, si >= 0 ? kStatusNames[si] : "?",
                 std::isfinite(p.hearts) ? (double)p.hearts : 0.0, p.heartPoints, p.asset, p.category, p.isDecor ? "true" : "false", p.starred ? "true" : "false", p.steps);
        rows += buf;
    }
    std::string json;
    json.reserve(rows.size() + 128);
    snprintf(buf, sizeof buf, "{\"t\":%.3f,\"total\":%lu,\"starred\":%d,\"pikmin\":[", [NSDate date].timeIntervalSince1970,
             (unsigned long)all.count, starred);
    json += buf; json += rows; json += "\n]}\n";
    pkWriteShared(@"roster.json", [NSData dataWithBytes:json.data() length:json.size()]);

    std::string txt;
    snprintf(buf, sizeof buf, "=== 보유 피크민 %lu마리 (즐겨찾기 %d) ===\n[색상별]\n", (unsigned long)all.count, starred);
    txt += buf;
    static const int order[9] = { 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    for (int k = 0; k < 9; k++) {
        int c = order[k];
        if (!byColor[c]) continue;
        snprintf(buf, sizeof buf, "  %s %d마리  (꽃 %d / 봉우리 %d / 잎 %d)\n", kColorNames[c], byColor[c],
                 flowered[c][0], flowered[c][1], flowered[c][2]);
        txt += buf;
    }
    txt += "[상태별]\n";
    for (int k = 0; k < 3; k++) {
        if (!byStatus[k]) continue;
        snprintf(buf, sizeof buf, "  %s %d마리\n", kStatusNames[k], byStatus[k]);
        txt += buf;
    }
    snprintf(buf, sizeof buf, "[데코] 코스튬 착용 %d마리 (방출 제외 권장)\n", decor);
    txt += buf;
    pkWriteShared(@"roster.txt", [NSData dataWithBytes:txt.data() length:txt.size()]);
    PALOG(@"[로스터] %lu마리 기록", (unsigned long)all.count);
}
