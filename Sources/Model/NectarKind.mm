#import "NectarKind.h"
#import "GameConstants.h"

BOOL pkNectarIsSpecial(NSString *flowerName, int hkind) {
    return flowerName.length > 0 || (hkind != 0 && hkind != PK_HONEY_COMMON_FLOWER_KIND);
}
