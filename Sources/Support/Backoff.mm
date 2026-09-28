#import "Backoff.h"
#import "Clock.h"

@interface PKBackoffEntry : NSObject
@property (nonatomic) NSTimeInterval last;
@property (nonatomic) int tries;
@property (nonatomic, copy) NSString *signature;
@end
@implementation PKBackoffEntry
@end

@implementation PKBackoff {
    NSTimeInterval _base, _max;
    double _factor;
    NSMutableDictionary<NSString *, PKBackoffEntry *> *_entries;
}

- (instancetype)initWithBase:(NSTimeInterval)base factor:(double)factor max:(NSTimeInterval)max {
    if ((self = [super init])) {
        _base = base; _factor = factor; _max = max;
        _entries = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSTimeInterval)waitForTries:(int)n {
    if (n <= 0) return 0;
    NSTimeInterval w = _base;
    for (int i = 1; i < n && w < _max; i++) w *= _factor;
    return MIN(w, _max);
}

- (NSTimeInterval)waitFor:(NSString *)key { return [self waitForTries:_entries[key].tries]; }
- (int)tries:(NSString *)key { return _entries[key].tries; }

- (BOOL)ready:(NSString *)key {
    PKBackoffEntry *e = _entries[key];
    return !e || pkMono() - e.last >= [self waitForTries:e.tries];
}

- (void)recordSend:(NSString *)key { [self recordSend:key signature:nil]; }

- (void)recordSend:(NSString *)key signature:(NSString *)signature {
    PKBackoffEntry *e = _entries[key];
    if (!e) { e = [PKBackoffEntry new]; _entries[key] = e; }
    if (signature && e.signature && ![signature isEqualToString:e.signature]) e.tries = 0;
    e.signature = signature;
    e.tries += 1;
    e.last = pkMono();
}

- (void)pruneKeeping:(NSSet<NSString *> *)alive {
    for (NSString *k in _entries.allKeys)
        if (![alive containsObject:k]) [_entries removeObjectForKey:k];
}
@end
