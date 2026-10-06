#import "TestKit.h"
#import "RosterReport.h"

static PKPikmin *full(NSString *name, int color, float hearts, BOOL decor, int status, int flower, BOOL starred) {
    PKPikmin *p = pikmin(name, color, hearts, decor, status);
    p.name = name; p.flowerState = flower; p.starred = starred; p.steps = 12345; p.heartPoints = 7; p.category = 3;
    return p;
}
static NSDictionary *parse(NSData *d) { return [NSJSONSerialization JSONObjectWithData:d options:0 error:nil]; }

void test_roster_json_is_valid_and_complete(void) {
    NSArray *roster = @[ full(@"1", 1, 4.5f, YES, 32, 4, YES), full(@"2", 2, 0.0f, NO, 2, 1, NO) ];
    NSDictionary *doc = parse(pkRosterJson(roster, 1234.5));
    CHECK(doc != nil);
    CHECK_EQ([doc[@"total"] intValue], 2);
    CHECK_EQ([doc[@"starred"] intValue], 1);
    CHECK([doc[@"t"] doubleValue] == 1234.5);
    NSArray *rows = doc[@"pikmin"];
    CHECK_EQ(rows.count, 2);
    NSDictionary *a = rows[0];
    CHECK([a[@"colorName"] isEqualToString:@"빨강"]);
    CHECK([a[@"flowerName"] isEqualToString:@"꽃"]);
    CHECK([a[@"statusName"] isEqualToString:@"동행"]);
    CHECK([a[@"deco"] boolValue]);
    CHECK([a[@"starred"] boolValue]);
    CHECK([a[@"hearts"] doubleValue] == 4.5);
    CHECK_EQ([a[@"steps"] longLongValue], 12345);
    CHECK([rows[1][@"statusName"] isEqualToString:@"작업중"]);
}

// Names reach the JSON through hand-written escaping: quotes, backslashes and control characters must survive.
void test_roster_json_escapes_names(void) {
    NSString *nasty = @"a\"b\\c\td";
    NSDictionary *doc = parse(pkRosterJson(@[ full(nasty, 1, 1.0f, NO, 1, 1, NO) ], 0));
    CHECK(doc != nil);
    CHECK([doc[@"pikmin"][0][@"name"] isEqualToString:nasty]);
}

void test_roster_json_handles_bad_numbers_and_empty(void) {
    PKPikmin *p = full(@"x", 1, NAN, NO, 1, 1, NO);
    NSDictionary *doc = parse(pkRosterJson(@[ p ], 0));
    CHECK(doc != nil);
    CHECK([doc[@"pikmin"][0][@"hearts"] doubleValue] == 0.0);        // NaN would not be JSON
    NSDictionary *empty = parse(pkRosterJson(@[], 0));
    CHECK(empty != nil);
    CHECK_EQ([empty[@"total"] intValue], 0);
    CHECK_EQ([empty[@"pikmin"] count], 0);
}

void test_roster_summary(void) {
    NSArray *roster = @[ full(@"1", 1, 5, YES, 32, 4, YES), full(@"2", 1, 1, NO, 32, 1, NO), full(@"3", 8, 2, YES, 1, 3, NO) ];
    NSString *t = [[NSString alloc] initWithData:pkRosterSummary(roster) encoding:NSUTF8StringEncoding];
    CHECK([t containsString:@"보유 피크민 3마리 (즐겨찾기 1)"]);
    CHECK([t containsString:@"빨강 2마리  (꽃 1 / 봉우리 0 / 잎 1)"]);
    CHECK([t containsString:@"얼음 1마리"]);
    CHECK([t containsString:@"동행 2마리"]);
    CHECK([t containsString:@"대기 1마리"]);
    CHECK([t containsString:@"코스튬 착용 2마리"]);
}

// The signature is what decides a rewrite: it follows what the files show and ignores walking.
void test_roster_signature(void) {
    PKPikmin *a = full(@"1", 1, 4.5f, NO, 32, 4, NO);
    uint64_t base = pkRosterSignature(@[ a ]);
    a.steps += 500;                                                   // walking: not shown, not part of it
    CHECK(pkRosterSignature(@[ a ]) == base);
    a.hearts = 4.6f;                                                  // hearts moved
    CHECK(pkRosterSignature(@[ a ]) != base);
    a.hearts = 4.5f;
    CHECK(pkRosterSignature(@[ a ]) == base);
    a.status = 1;
    CHECK(pkRosterSignature(@[ a ]) != base);
    a.status = 32; a.name = @"renamed";
    CHECK(pkRosterSignature(@[ a ]) != base);
}
