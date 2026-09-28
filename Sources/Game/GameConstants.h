// Enum values of the game's protos, as observed on-device.
#pragma once

// PikminProto.statusCase_
#define PK_STATUS_AVAILABLE 1    // waiting
#define PK_STATUS_TASK      2    // busy on an expedition / carry
#define PK_STATUS_ENTOURAGE 32   // walking with the player

// PikminProto.flowerState_ — a Pikmin's own head (not the big-flower states below)
#define PK_PF_LEAF   1
#define PK_PF_BUD    3
#define PK_PF_FLOWER 4
#define PK_PF_PICK   5           // FLOWER_READY_TO_PICK
#define PK_PF_WILTED 6

// PikminTaskProto.TaskOneofCase
#define PK_TASK_CARRY        1
#define PK_TASK_EXPEDITION   6
#define PK_TASK_GIFT         8
#define PK_TASK_POICHALLENGE 9

// ExpeditionState
#define PK_EXP_AVAILABLE 0       // Outgoing 1, AtSpawn 2, Incoming 3
#define PK_EXP_RETURNED  4

// MapObjectProto.ObjectOneofCase
#define PK_MO_POIFLOWER   13
#define PK_MO_FLOWERFIELD 14
#define PK_MO_OVERLAY     21
#define PK_MO_MUSHROOM    22
#define PK_MO_CAMPAIGN    23

// PoiFlowerProto / PoiFlowerOverlayProto state
#define PK_FS_LEAF       1
#define PK_FS_BUD        2
#define PK_FS_FLOWER     3
#define PK_FS_FULL_BLOOM 4
#define PK_FS_PRE_FLOWER 5

// HoneyType: 1 white, 2 red, 3 blue, 4 yellow, 5 happy (rainbow)
#define PK_HONEY_COMMON_FLOWER_KIND 5   // "kind 5" is ordinary nectar despite carrying a kind

// PikminProto friendship: hearts 0..8 (0-4 red, 4-8 yellow), 4 is the raising target
#define PK_HEARTS_TARGET 4.0f
