//
//  TSUtils.m
//  Reynard
//
//  Created by Minh Ton on 12/4/26.
//

// https://github.com/AngelAuraMC/Amethyst-iOS/blob/ed267f52dafa24219f1166c542294b0e682ebc64/Natives/utils.m
// https://github.com/AngelAuraMC/Amethyst-iOS/blob/00678b07a192ef5c79f8c4a2e4cecf1d7406c8c5/Natives/SurfaceViewController.m

#import "TSUtils.h"

#include <string.h>
#include <errno.h>
#include <sys/types.h>

#define MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT 6

CFTypeRef SecTaskCopyValueForEntitlement(void *task, NSString *entitlement, CFErrorRef _Nullable *error);
void *SecTaskCreateFromSelf(CFAllocatorRef allocator);
int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags, void *buffer, size_t buffersize);

BOOL getEntitlementValue(NSString *key) {
    void *secTask = SecTaskCreateFromSelf(NULL);
    if (!secTask) return NO;
    
    CFTypeRef value = SecTaskCopyValueForEntitlement(secTask, key, nil);
    CFRelease(secTask);
    if (!value) return NO;
    
    BOOL hasValue = ![(__bridge id)value isKindOfClass:NSNumber.class] || [(__bridge NSNumber *)value boolValue];
    CFRelease(value);
    return hasValue;
}

void updateJetsamControl(pid_t pid) {
    if (!getEntitlementValue(@"com.apple.private.memorystatus")) return;

    // FIXME: Find an actual resonable limit instead of setting 75% of physical mem
    int limit = (int)((NSProcessInfo.processInfo.physicalMemory >> 20) * 0.75);
    if (memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT, pid, limit, NULL, 0) == -1) {
        NSLog(@"Failed to set Jetsam task limit to %d MB for pid %d: error: %s", limit, pid, strerror(errno));
    } else {
        NSLog(@"Successfully set Jetsam task limit to %d MB for pid %d", limit, pid);
    }
}
