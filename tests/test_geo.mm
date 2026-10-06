#import "TestKit.h"
#import "Geo.h"

void test_geo_distance(void) {
    CHECK(pkDistanceM(37.0, 127.0, 37.0, 127.0) == 0);
    // one degree of latitude is about 111.2 km everywhere
    double lat = pkDistanceM(37.0, 127.0, 38.0, 127.0);
    CHECK(lat > 111000 && lat < 111400);
    // a degree of longitude shrinks with latitude: cos(37 deg) of the equatorial value
    double lng = pkDistanceM(37.0, 127.0, 37.0, 128.0);
    CHECK(lng > 88000 && lng < 89500);
    // symmetric, and about 65 m for a tiny step (the big-flower send range)
    CHECK(pkDistanceM(37.0, 127.0, 37.0005, 127.0) == pkDistanceM(37.0005, 127.0, 37.0, 127.0));
    double step = pkDistanceM(37.0, 127.0, 37.0, 127.0 + 65.0 / 88800.0);
    CHECK(step > 64 && step < 66);
}
