#import "Geo.h"
#import <math.h>

double pkDistanceM(double lat1, double lng1, double lat2, double lng2) {
    const double r = 6371000.0, p = M_PI / 180.0;
    double dlat = (lat2 - lat1) * p, dlng = (lng2 - lng1) * p;
    double a = sin(dlat / 2) * sin(dlat / 2) + cos(lat1 * p) * cos(lat2 * p) * sin(dlng / 2) * sin(dlng / 2);
    return 2 * r * atan2(sqrt(a), sqrt(1 - a));
}
