#include "bench.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "logger.h"
#include "stopwatch_utils.h"
#include "tapelib.h"

#define KB *1024
#define MB KB KB
#define GB KB MB
#define TB KB GB

static const size_t BLOCK_SIZE = 512;
static const size_t WRITE_SIZE = 8 * BLOCK_SIZE;

int benchmark_drive(Drive *drive) {
    log_debug("Setting up folder");
    if (mkdir("drvbench", 0755) < 0 && errno != EEXIST) {
        log_perror();
        return -1;
    }
    FILE *meta_file = fopen("drvbench/meta.toml", "w");
    FILE *write_file = fopen("drvbench/write.csv", "w");
    FILE *read_file = fopen("drvbench/read.csv", "w");
    if (!meta_file || !write_file) {
        log_perror();
        if (meta_file) {
            fclose(meta_file);
        }
        if (write_file) {
            fclose(write_file);
        }
        return -1;
    }

    log_info("Benchmarking writes");
    if (drive_ensure_logical_block(drive)) {
        return -1;
    }
    drive_set_block_size(drive, BLOCK_SIZE);

    drive_rewind(drive);

    char *data = calloc(WRITE_SIZE, 1);
    memset(data, 'A', WRITE_SIZE);

    size_t current_block = drive_tell(drive);
    size_t previous_block;

    ssize_t written;
    do {
        previous_block = current_block;

        stopwatch_snapshot();
        written = write(drive->fd, data, WRITE_SIZE);
        stopwatch_snapshot();

        if (written == -1) {
            return -1;
        }

        current_block = drive_tell(drive);

        fprintf(write_file, "%zu,%zu,%.2f\n", previous_block, current_block,
                elapsed_io_ms(get_last_lap()));
    } while (written == WRITE_SIZE);

    fprintf(meta_file, "total_size_tb = %zu\n", (current_block * BLOCK_SIZE) / (1l TB));

    free(data);
    return 0;
}
