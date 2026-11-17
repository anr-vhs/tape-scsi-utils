#include "stopwatch_utils.h"
#include "logger.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static size_t n_laps;
static size_t laps_capacity;
static Snapshot *laps;

void __attribute__((constructor)) init_stopwatch();
void __attribute__((destructor)) deinit_stopwatch();

void init_stopwatch() {
    n_laps = 0;
    laps_capacity = 16;
    laps = calloc(laps_capacity, sizeof(Snapshot));
    if (clock_gettime(CLOCK_MONOTONIC, &laps[0].wall) < 0 ||
        getrusage(RUSAGE_SELF, &laps[0].usage) < 0) {
        log_perror();
        exit(1);
    }
    log_trace("initialized stopwatch")
}

void deinit_stopwatch() {
    n_laps = 0;
    free(laps);
}

int reset_stopwatch() {
    memset(laps, 0, n_laps * sizeof(Lap));
    n_laps = 0;
    if (clock_gettime(CLOCK_MONOTONIC, &laps[0].wall) < 0 ||
        getrusage(RUSAGE_SELF, &laps[0].usage) < 0) {
        log_perror();
        return -1;
    }
    return 0;
}

static Snapshot *next_snapshot() {
    n_laps++;
    if (n_laps >= laps_capacity) {
        log_trace("not enough capacity (%lu), doubling size", laps_capacity)
        laps_capacity *= 2;
        laps = reallocarray(laps, laps_capacity, sizeof(Snapshot));
    }
    return &laps[n_laps];
}

int stopwatch_snapshot() {
    Snapshot *snapshot = next_snapshot();
    if (clock_gettime(CLOCK_MONOTONIC, &snapshot->wall) < 0 ||
        getrusage(RUSAGE_SELF, &snapshot->usage) < 0) {
        log_perror();
        return -1;
    }
    return 0;
}

Lap get_lap(size_t index) {
    return (Lap) {
        .start = &laps[index],
        .end = &laps[index + 1],
    };
}

Lap get_last_lap() {
    return get_lap(n_laps - 1);
}

static double timeval_ms(struct timeval value) {
    return (double)value.tv_sec * 1000.0 + (double)value.tv_usec / 1000.0;
}

double elapsed_io_ms(Lap lap) {
    double wall = (double)(lap.end->wall.tv_sec - lap.start->wall.tv_sec) * 1000.0 +
                  (double)(lap.end->wall.tv_nsec - lap.start->wall.tv_nsec) / 1000000.0;
    double user =
        timeval_ms(lap.end->usage.ru_utime) - timeval_ms(lap.start->usage.ru_utime);
    double system =
        timeval_ms(lap.end->usage.ru_stime) - timeval_ms(lap.start->usage.ru_stime);
    return wall - user - system;
}
