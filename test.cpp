#include "ljx.h"
#include "unistd.h"
#include "spawn.h"
#include "errno.h"
#include "poll.h"

#include <vector>

int main() {
    int pipfd[2];

    ok = pipe(pipfd);

    pid_t pid {-1};

    posix_spawn_file_actions_t actions; {
        ok = posix_spawn_file_actions_init(&actions);
        ok = posix_spawn_file_actions_addclose(&actions, pipfd[0]);
        ok = posix_spawn_file_actions_adddup2(&actions, pipfd[1], 1);
        ok = posix_spawn_file_actions_adddup2(&actions, pipfd[1], 2);
        // ok = posix_spawn_file_actions_destroy(&actions);
    }

    posix_spawnattr_t attrs; {
        ok = posix_spawnattr_init(&attrs);
        // ok = posix_spawnattr_setflags(&attrs, POSIX_SPAWN_SETSIGMASK);
        // ok = posix_spawnattr_setsigmask(&attrs, nullptr);
        // ok = posix_spawnattr_setsigdefault(&attrs, nullptr);
        // ok = posix_spawnattr_setpgroup(&attrs, 0);
        // ok = posix_spawnattr_setschedpolicy(&attrs, 0);
        // ok = posix_spawnattr_setschedparam(&attrs, nullptr);
        // ok = posix_spawnattr_setrlimit(&attrs, RLIMIT_NOFILE, nullptr);
        // ok = posix_spawnattr_destroy(&attrs);
    }

    char * const argv[] = {"cmd.exe", "/C", "date", "/T", nullptr};
    char * const envp[] = {nullptr};

    int r = posix_spawnp(&pid, "cmd.exe", &actions, &attrs, argv, envp);

    if(r != 0) {
        printf("%d, %s\n", r, strerror(r)); return 0;
    }

    close(pipfd[1]);

    std::vector<pollfd> fds {{pipfd[0], POLLIN}};

    // while(true) {
    //     int r = poll(fds.data(), fds.size(), -1);

    //     if(r == -1) {
    //         if(errno == EINTR) continue;
    //         else break;
    //     }

    //     if(r == 0) continue;

    //     if(fds[0].revents & POLLIN) {
    //         char buf[1024];

    //         int n = read(pipfd[0], buf, sizeof(buf));

    //         printf("%d, %.*s\n", n, n, buf);
    //     }
    //     else break;
    // }

    waitpid(pid, nullptr, 0);

    while(true) {
        int r = poll(fds.data(), fds.size(), -1);

        if(r == -1) {
            if(errno == EINTR) continue;
            else break;
        }

        if(r == 0) continue;

        if(fds[0].revents & POLLIN) {
            char buf[1024];

            int n = read(pipfd[0], buf, sizeof(buf));

            printf("%d, %.*s\n", n, n, buf);
        }
        else break;
    }

    // char buf[1024];

    // int n = read(pipfd[0], buf, sizeof(buf));

    // printf("%d, %.*s\n", n, n, buf);

    return 0;
}