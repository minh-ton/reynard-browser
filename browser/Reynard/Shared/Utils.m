//
//  Utils.m
//  Reynard
//
//  Created by Minh Ton on 12/4/26.
//

// https://github.com/AngelAuraMC/Amethyst-iOS/blob/ed267f52dafa24219f1166c542294b0e682ebc64/Natives/utils.m
// https://github.com/AngelAuraMC/Amethyst-iOS/blob/00678b07a192ef5c79f8c4a2e4cecf1d7406c8c5/Natives/SurfaceViewController.m
// https://github.com/opa334/TrollStore/blob/88424f683b2a08f34a3f88985f790f97d84ce1df/Shared/TSUtil.m

#import "Utils.h"

#include <string.h>
#include <errno.h>
#include <sys/types.h>
#import <spawn.h>
#import <sys/wait.h>

#define MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT 6
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1

CFTypeRef SecTaskCopyValueForEntitlement(void *task, NSString *entitlement, CFErrorRef _Nullable *error);
void *SecTaskCreateFromSelf(CFAllocatorRef allocator);
int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags, void *buffer, size_t buffersize);

extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t * __restrict attr, uid_t persona, uint32_t flags);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t * __restrict attr, uid_t uid);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t * __restrict attr, uid_t gid);

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

int spawnRoot(NSString *path, NSArray<NSString *> *args) {
    NSMutableArray<NSString *> *arguments = args.mutableCopy ?: [NSMutableArray new];
    [arguments insertObject:path atIndex:0];
    
    NSUInteger argCount = arguments.count;
    char **argv = calloc(argCount + 1, sizeof(char *));
    for (NSUInteger index = 0; index < argCount; index++) {
        argv[index] = strdup(arguments[index].UTF8String);
    }
    
    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    posix_spawnattr_set_persona_np(&attributes, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attributes, 0);
    posix_spawnattr_set_persona_gid_np(&attributes, 0);
    
    pid_t taskPID = 0;
    int spawnError = posix_spawn(&taskPID, path.fileSystemRepresentation, NULL, &attributes, argv, NULL);
    
    posix_spawnattr_destroy(&attributes);
    for (NSUInteger index = 0; index < argCount; index++) free(argv[index]);
    free(argv);
    
    if (spawnError != 0) return spawnError;
    
    int status = 0;
    do {
        if (waitpid(taskPID, &status, 0) == -1) {
            if (errno == EINTR) continue;
            return errno;
        }
    } while (!WIFEXITED(status) && !WIFSIGNALED(status));
    
    return WEXITSTATUS(status);
}
