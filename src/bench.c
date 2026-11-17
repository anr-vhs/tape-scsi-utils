#include "bench.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "logger.h"
#include "stopwatch_utils.h"

int main(int argc, char **argv) {
    set_log_level(TRACE);
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <changer> <drives>...\n", argv[0]);
        return 1;
    }

    Library library;
    if (library_init(&library, argv[1], (const char *const *)&argv[2],
                     (size_t)(argc - 2)) < 0) {
        return 1;
    }

    if (benchmark_changer(&library)) {
        log_error("Failed to benchmark changer");
        return 1;
    }

    if (reset_stopwatch() < 0) {
        return 1;
    }

    if (benchmark_drive(library.drives[0].drive)) {
        log_error("Failed to benchmark drive");
        return 1;
    }

    library_deinit(&library);
    return 0;
}
