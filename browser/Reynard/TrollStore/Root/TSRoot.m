//
//  TSRoot.m
//  Reynard
//
//  Created by Minh Ton on 12/4/26.
//

// https://github.com/opa334/TrollStore/blob/88424f683b2a08f34a3f88985f790f97d84ce1df/Shared/TSUtil.m

#import "TSRoot.h"
#import <spawn.h>
#import <sys/wait.h>

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1

extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t * __restrict attr, uid_t persona, uint32_t flags);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t * __restrict attr, uid_t uid);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t * __restrict attr, uid_t gid);

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
