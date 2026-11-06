#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <signal.h>
#include <sys/stat.h>

/* Runs only the protected Core copy; no shell, inherited environment, or CLT. */
int main(int argc, char **argv) {
    if (argc != 2 || getuid() != 0) return 1;
    char *end;
    unsigned long uid = strtoul(argv[1], &end, 10);
    if (!*argv[1] || *end || uid < 501 || uid > 2147483647) return 1;
    int channel[2];
    if (pipe(channel)) return 1;
    if (fcntl(channel[1], F_SETFD, FD_CLOEXEC) < 0) return 1;
    pid_t child = fork();
    if (child < 0) return 1;
    if (child) {
        close(channel[1]);
        int status, error;
        while (waitpid(child, &status, 0) < 0) if (errno != EINTR) return 1;
        ssize_t count;
        do { count = read(channel[0], &error, sizeof(error)); } while (count < 0 && errno == EINTR);
        return count == 0 && WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : 1;
    }
    close(channel[0]);
    if (setsid() < 0) goto failed;
    child = fork();
    if (child < 0) goto failed;
    if (child) _exit(0);
    if (chdir("/")) goto failed;
    int null = open("/dev/null", O_RDWR);
    if (null < 0) goto failed;
    for (int i = 0; i < 3; i++) if (dup2(null, i) < 0) goto failed;
    if (null > 2) close(null);
    for (int fd = 3; fd < getdtablesize(); fd++) if (fd != channel[1]) close(fd);
    umask(022);
    sigset_t empty;
    sigemptyset(&empty);
    if (sigprocmask(SIG_SETMASK, &empty, NULL) < 0) goto failed;
    int signals[] = {SIGHUP, SIGINT, SIGTERM, SIGPIPE};
    for (unsigned int i = 0; i < sizeof(signals) / sizeof(signals[0]); i++)
        if (signal(signals[i], SIG_DFL) == SIG_ERR) goto failed;
    char control[64];
    snprintf(control, sizeof(control), "BIMERON_CONTROL_UID=%lu", uid);
    char *environment[] = {control, "PATH=/usr/bin:/bin:/usr/sbin:/sbin", NULL};
    char *arguments[] = {"/Library/Application Support/Bimeron/DevCore/bimeron-core", "daemon", NULL};
    execve(arguments[0], arguments, environment);
failed:
    { int error = errno; write(channel[1], &error, sizeof(error)); }
    _exit(1);
}
