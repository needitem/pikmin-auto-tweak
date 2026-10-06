#import "Heartbeat.h"
#import "CpuStats.h"
#import "GameContext.h"
#import "Governor.h"
#import "Hooks.h"
#import "Location.h"
#import "Log.h"
#import "PassTimings.h"
#import "RpcClient.h"
#import "RpcPacer.h"
#import <UIKit/UIKit.h>

void pkHeartbeatBeat(void) {
    static int beat = 0;
    if (++beat % 60) return;
    static NSArray *thermal = @[ @"정상", @"주의", @"높음", @"위험" ];
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    NSProcessInfoThermalState ts = NSProcessInfo.processInfo.thermalState;
    PALOG(@"[hb] rpc=%d mgr=%d inv=%d 위치 %lu회, 마지막 %.0f초 전 | 발열 %@, 배터리 %.0f%% | 패스 %@",
          pkRpc() != NULL, pkMgr() != NULL, pkInv() != NULL, pkLocationCount(), MIN(pkLocationAge(), 9999.0),
          thermal[MIN((int)ts, 3)], UIDevice.currentDevice.batteryLevel * 100.0, pkTimingsTake());
    PKGovernorStats g = pkGovernorTakeStats();
    PALOG(@"[hb2] %@ | 후킹 호출/분 %@ | RPC/분 %@ | 전송 큐 %@ | 보류 틱 %d | 메인 지연 최대 %.0fms (>100ms %d회, >500ms %d회)",
          pkCpuSummary(), pkHookStats(), pkRpcStats(), pkRpcQueueStats(), g.heldTicks, g.lateMaxMs, g.over100, g.over500);
}
