// Where the process spends its CPU, per thread, since the previous call.
// Diagnostic only (the heartbeat prints it): tells the main thread, the render
// thread and the network threads apart, which a whole-process figure cannot.
// Call from the main thread; the first call only sets the baseline.
#pragma once
#import <Foundation/Foundation.h>

NSString *pkCpuSummary(void);
