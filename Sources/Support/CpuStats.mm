#import "CpuStats.h"
#import "Clock.h"
#import <mach/mach.h>
#import <string>
#import <unordered_map>
#import <vector>
#import <algorithm>

static double seconds(time_value_t t) { return t.seconds + t.microseconds / 1e6; }

NSString *pkCpuSummary(void) {
    static std::unordered_map<uint64_t, double> prev;        // thread id -> cumulative cpu seconds
    static NSTimeInterval prevAt = 0;
    static uint64_t mainId = 0;

    NSTimeInterval now = pkMono();
    if (!mainId) {
        thread_t self = mach_thread_self();
        thread_identifier_info_data_t ii; mach_msg_type_number_t c = THREAD_IDENTIFIER_INFO_COUNT;
        if (thread_info(self, THREAD_IDENTIFIER_INFO, (thread_info_t)&ii, &c) == KERN_SUCCESS) mainId = ii.thread_id;
        mach_port_deallocate(mach_task_self(), self);
    }
    thread_act_array_t th = NULL; mach_msg_type_number_t n = 0;
    if (task_threads(mach_task_self(), &th, &n) != KERN_SUCCESS) return @"cpu 조회 실패";

    struct Row { std::string name; double delta; };
    std::vector<Row> rows;
    std::unordered_map<uint64_t, double> cur;
    double total = 0;
    for (mach_msg_type_number_t i = 0; i < n; i++) {
        thread_basic_info_data_t bi; mach_msg_type_number_t bc = THREAD_BASIC_INFO_COUNT;
        thread_identifier_info_data_t ii; mach_msg_type_number_t ic = THREAD_IDENTIFIER_INFO_COUNT;
        thread_extended_info_data_t ei; mach_msg_type_number_t ec = THREAD_EXTENDED_INFO_COUNT;
        if (thread_info(th[i], THREAD_BASIC_INFO, (thread_info_t)&bi, &bc) == KERN_SUCCESS &&
            thread_info(th[i], THREAD_IDENTIFIER_INFO, (thread_info_t)&ii, &ic) == KERN_SUCCESS) {
            double used = seconds(bi.user_time) + seconds(bi.system_time);
            cur[ii.thread_id] = used;
            auto it = prev.find(ii.thread_id);
            double d = it == prev.end() ? 0 : used - it->second;
            if (d < 0) d = 0;
            total += d;
            std::string name;
            if (ii.thread_id == mainId) name = "main";
            else if (thread_info(th[i], THREAD_EXTENDED_INFO, (thread_info_t)&ei, &ec) == KERN_SUCCESS && ei.pth_name[0]) name = ei.pth_name;
            else { char b[32]; snprintf(b, sizeof b, "t%llu", (unsigned long long)ii.thread_id); name = b; }
            rows.push_back({ name, d });
        }
        mach_port_deallocate(mach_task_self(), th[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)th, n * sizeof(thread_t));

    double wall = now - prevAt;
    BOOL first = prevAt == 0;
    prev.swap(cur); prevAt = now;
    if (first || wall <= 0) return @"cpu 기준 측정 시작";

    std::sort(rows.begin(), rows.end(), [](const Row &a, const Row &b) { return a.delta > b.delta; });
    NSMutableArray *bits = [NSMutableArray array];
    for (size_t i = 0; i < rows.size() && i < 5; i++) {
        if (rows[i].delta / wall < 0.005) break;
        [bits addObject:[NSString stringWithFormat:@"%s %.0f%%", rows[i].name.c_str(), rows[i].delta / wall * 100.0]];
    }
    return [NSString stringWithFormat:@"CPU 합 %.0f%% (코어 1개=100%%, 스레드 %u) [%@]", total / wall * 100.0, n,
            bits.count ? [bits componentsJoinedByString:@", "] : @"-"];
}
