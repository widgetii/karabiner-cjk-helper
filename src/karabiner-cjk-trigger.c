#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static const char *SOCKET_PATH = "/tmp/karabiner-cjk-helper.sock";

int main(int argc, char *argv[]) {
    if (argc < 2 || argv[1][0] == '\0') {
        fprintf(stderr, "usage: %s <input_source_id>\n", argv[0]);
        return 1;
    }

    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    if (s < 0) { perror("socket"); return 1; }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);

    if (connect(s, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("connect");
        close(s);
        return 1;
    }

    size_t len = strlen(argv[1]);
    ssize_t w = write(s, argv[1], len);
    close(s);
    return (w == (ssize_t)len) ? 0 : 1;
}
