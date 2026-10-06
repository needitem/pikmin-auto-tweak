#import "PlantPlan.h"

const int kPlantSwitchMargin = 10;
static const NSTimeInterval kStartGap = 60;       // a start that did not go live is not retried every pass
static const NSTimeInterval kStopGap = 20;        // stop is async; do not repeat it
static const NSTimeInterval kAdoptGap = 90;       // a session may take a while to go live after the request

PKPetal *pkBiggestPlain(NSArray<PKPetal *> *petals) {
    PKPetal *best = nil;
    for (PKPetal *p in petals) {
        if (p.special) continue;
        if (!best || p.num > best.num || (p.num == best.num && [p.itemId compare:best.itemId] == NSOrderedAscending)) best = p;
    }
    return best;
}

PKPetal *pkStackById(NSArray<PKPetal *> *petals, NSString *itemId) {
    for (PKPetal *p in petals) if ([p.itemId isEqualToString:itemId]) return p;
    return nil;
}

PKPlantDecision pkPlantDecide(NSArray<PKPetal *> *petals, PKPlantInputs in) {
    PKPetal *best = pkBiggestPlain(petals);
    PKPlantDecision d = { PKPlantKeep, NO };
    if (in.live) {
        if (!in.ourStackId.length) { d.action = PKPlantLeaveAlone; return d; }
        PKPetal *cur = pkStackById(petals, in.ourStackId);
        if (cur && best && ![best.itemId isEqualToString:cur.itemId] && best.num >= cur.num + kPlantSwitchMargin)
            d.action = (in.now - in.lastStop < kStopGap) ? PKPlantSwitchWait : PKPlantSwitch;
        return d;
    }
    d.forgetOurStack = in.now - in.lastStart > kAdoptGap;       // not live, and the request is old: it did not take
    long long plain = 0;
    for (PKPetal *p in petals) if (!p.special) plain += p.num;
    if (plain <= 0) d.action = PKPlantNoPlain;
    else if (!best) d.action = PKPlantNoStack;
    else if (in.now - in.lastStart < kStartGap) d.action = PKPlantStartWait;
    else d.action = PKPlantStart;
    return d;
}
