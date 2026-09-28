// InventoryManager access shared by every reader of the player's items.
#pragma once
#import <Foundation/Foundation.h>

void *pkInvList(const char *getter);        // InventoryManager.Get*List()
void *pkItemProto(void *item);              // item.get_Proto()
NSString *pkItemId(void *item);             // item.get_Id() as text
