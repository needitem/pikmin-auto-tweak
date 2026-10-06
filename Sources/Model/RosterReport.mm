#import "RosterReport.h"
#import "ChangeGate.h"
#import "GameConstants.h"
#import <cmath>
#import <string>

static const char *const kColorNames[9] = { "미상", "빨강", "파랑", "노랑", "하양", "보라", "바위", "날개", "얼음" };
static const char *const kStatusNames[3] = { "대기", "작업중", "동행" };

static int colorIdx(int c) { return (c >= 1 && c <= 8) ? c : 0; }
static int flowerIdx(int s) { return s == PK_PF_FLOWER ? 0 : s == PK_PF_BUD ? 1 : s == PK_PF_LEAF ? 2 : 3; }
static int statusIdx(int s) { return s == PK_STATUS_AVAILABLE ? 0 : s == PK_STATUS_TASK ? 1 : s == PK_STATUS_ENTOURAGE ? 2 : -1; }
static const char *flowerName(int s) {
    switch (s) { case PK_PF_LEAF: return "잎"; case PK_PF_BUD: return "봉우리"; case PK_PF_FLOWER: return "꽃";
        case PK_PF_PICK: return "수확대기"; case PK_PF_WILTED: return "시듦"; }
    return "?";
}

// JSON string body (no quotes): the characters JSON requires escaped.
static void appendEscaped(std::string &out, const char *u) {
    for (; u && *u; u++) {
        unsigned char c = (unsigned char)*u;
        if (c == '"' || c == '\\') { out += '\\'; out += (char)c; }
        else if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); out += b; }
        else out += (char)c;
    }
}

uint64_t pkRosterSignature(NSArray<PKPikmin *> *roster) {
    uint64_t sig = kPKHashSeed;
    for (PKPikmin *p in roster) {
        const char *name = p.name.UTF8String ?: "";
        sig = pkHash(sig, name, strlen(name) + 1);
        int v[8] = { p.color, p.flowerState, p.status, 0, p.heartPoints, p.asset, p.category, p.starred };
        float h = p.hearts; memcpy(&v[3], &h, sizeof h);
        sig = pkHash(sig, v, sizeof v);
    }
    return sig;
}

NSData *pkRosterJson(NSArray<PKPikmin *> *roster, NSTimeInterval stamp) {
    int starred = 0;
    std::string rows;
    rows.reserve(roster.count * 190);
    BOOL first = YES;
    char buf[320];
    for (PKPikmin *p in roster) {
        int ci = colorIdx(p.color), si = statusIdx(p.status);
        if (p.starred) starred++;
        rows += first ? "\n" : ",\n"; first = NO;
        rows += "{\"name\":\"";
        appendEscaped(rows, p.name.UTF8String);
        snprintf(buf, sizeof buf,
                 "\",\"color\":%d,\"colorName\":\"%s\",\"flower\":%d,\"flowerName\":\"%s\",\"status\":%d,\"statusName\":\"%s\","
                 "\"hearts\":%.6g,\"fpt\":%d,\"asset\":%d,\"category\":%d,\"deco\":%s,\"starred\":%s,\"steps\":%lld}",
                 p.color, kColorNames[ci], p.flowerState, flowerName(p.flowerState), p.status, si >= 0 ? kStatusNames[si] : "?",
                 std::isfinite(p.hearts) ? (double)p.hearts : 0.0, p.heartPoints, p.asset, p.category,
                 p.isDecor ? "true" : "false", p.starred ? "true" : "false", p.steps);
        rows += buf;
    }
    std::string json;
    json.reserve(rows.size() + 128);
    snprintf(buf, sizeof buf, "{\"t\":%.3f,\"total\":%lu,\"starred\":%d,\"pikmin\":[", stamp, (unsigned long)roster.count, starred);
    json += buf; json += rows; json += "\n]}\n";
    return [NSData dataWithBytes:json.data() length:json.size()];
}

NSData *pkRosterSummary(NSArray<PKPikmin *> *roster) {
    int byColor[9] = {0}, byStatus[3] = {0}, flowered[9][4] = {{0}};
    int starred = 0, decor = 0;
    for (PKPikmin *p in roster) {
        int ci = colorIdx(p.color), si = statusIdx(p.status);
        byColor[ci]++;
        if (si >= 0) byStatus[si]++;
        flowered[ci][flowerIdx(p.flowerState)]++;
        if (p.starred) starred++;
        if (p.isDecor) decor++;
    }
    std::string txt;
    char buf[320];
    snprintf(buf, sizeof buf, "=== 보유 피크민 %lu마리 (즐겨찾기 %d) ===\n[색상별]\n", (unsigned long)roster.count, starred);
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
    return [NSData dataWithBytes:txt.data() length:txt.size()];
}
