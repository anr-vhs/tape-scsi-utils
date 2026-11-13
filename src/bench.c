#include "tapelib.h"

#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "logger.h"
#include "stopwatch_utils.h"

#define ITERATIONS 4

typedef struct {
    double avg;
    double stddev;
} BenchStats;

static BenchStats calculate_stats(const double samples[ITERATIONS]) {
    BenchStats stats = {0};
    for (size_t i = 0; i < ITERATIONS; ++i) {
        stats.avg += samples[i];
    }
    stats.avg /= ITERATIONS;
    for (size_t i = 0; i < ITERATIONS; ++i) {
        double delta = stats.avg - samples[i];
        stats.stddev += delta * delta;
    }
    stats.stddev = sqrt(stats.stddev / ITERATIONS);
    return stats;
}

static int measured_load_store(Library *library, size_t slot, size_t drive,
                               BenchStats *load_stats,
                               BenchStats *store_stats) {
    double load_samples[ITERATIONS], store_samples[ITERATIONS];
    for (size_t i = 0; i < ITERATIONS; ++i) {
        stopwatch_snapshot();
        if (library_load(library, slot, drive) < 0) {
            return -1;
        }
        stopwatch_snapshot();

        load_samples[i] = elapsed_io_ms(get_last_lap());

        stopwatch_snapshot();
        if (library_store(library, drive, slot) < 0) {
            return -1;
        }
        stopwatch_snapshot();
        store_samples[i] = elapsed_io_ms(get_last_lap());
    }
    *load_stats = calculate_stats(load_samples);
    *store_stats = calculate_stats(store_samples);
    return 0;
}

static void write_stat(FILE *file, BenchStats value) {
    fprintf(file, "%.2f,%.2f", value.avg, value.stddev);
}

static int save_metadata(size_t drives, size_t slots) {
    log_info("Saving metadata");

    FILE *meta = fopen("chbench/meta.toml", "w");
    if (meta == NULL) {
        log_perror();
        return -1;
    }
    fprintf(meta,
            "iterations = %d\n"
            "drive_count = %zu\n"
            "slot_count = %zu\n",
            ITERATIONS, drives, slots);
    return fclose(meta);
}

static int benchmark_changer(Library *library) {
    BenchStats *loads =
        calloc(library->slot_count * library->drive_count, sizeof(*loads));
    BenchStats *stores =
        calloc(library->drive_count * library->slot_count, sizeof(*stores));
    BenchStats *moves =
        calloc(library->slot_count * library->slot_count, sizeof(*moves));

    log_info("Benchmarking loads and stores");
    for (size_t slot = 0; slot < library->slot_count; ++slot) {
        if (changer_move_arm(&library->changer, TAPE_ELEMENT_SLOT, slot) < 0) {
            goto fail;
        }
        if (!library->slots[slot].content.full) {
            size_t source = slot;
            while (source > 0 && !library->slots[source - 1].content.full) {
                --source;
            }
            if (source == 0 ||
                library_move(library, TAPE_ELEMENT_SLOT, source - 1,
                             TAPE_ELEMENT_SLOT, slot) < 0) {
                goto fail;
            }
        }
        for (size_t drive = 0; drive < library->drive_count; ++drive) {
            BenchStats load_stat, store_stat;
            if (measured_load_store(library, slot, drive, &load_stat,
                                    &store_stat) < 0) {
                goto fail;
            }
            loads[slot * library->drive_count + drive] = load_stat;
            stores[drive * library->slot_count + slot] = store_stat;
        }
    }

    log_info("Benchmarking moves between slots");
    for (size_t from = 0; from < library->slot_count; ++from) {
        if (changer_move_arm(&library->changer, TAPE_ELEMENT_SLOT, from) < 0) {
            goto fail;
        }
        for (size_t to = 0; to < from; ++to) {
            double samples[ITERATIONS];
            double samples_back[ITERATIONS];
            for (size_t i = 0; i < ITERATIONS; ++i) {
                stopwatch_snapshot();
                if (changer_move_arm(&library->changer, TAPE_ELEMENT_SLOT, to) <
                    0) {
                    goto fail;
                }
                stopwatch_snapshot();

                samples[i] = elapsed_io_ms(get_last_lap());

                stopwatch_snapshot();
                if (changer_move_arm(&library->changer, TAPE_ELEMENT_SLOT,
                                     from) < 0) {
                    goto fail;
                }
                stopwatch_snapshot();

                samples_back[i] = elapsed_io_ms(get_last_lap());
            }
            moves[from * library->slot_count + to] = calculate_stats(samples);
            moves[to * library->slot_count + from] =
                calculate_stats(samples_back);
        }
    }

    log_info("Saving benchmark results");
    if (mkdir("chbench", 0755) < 0 && errno != EEXIST) {
        log_perror();
        goto fail;
    }
    FILE *load_file = fopen("chbench/loads.csv", "w");
    FILE *store_file = fopen("chbench/stores.csv", "w");
    FILE *move_file = fopen("chbench/moves.csv", "w");
    if (!load_file || !store_file || !move_file) {
        log_perror();
        if (load_file) {
            fclose(load_file);
        }
        if (store_file) {
            fclose(store_file);
        }
        if (move_file) {
            fclose(move_file);
        }
        goto fail;
    }

    for (size_t row = 0; row < library->slot_count; ++row) {
        for (size_t col = 0; col < library->slot_count; ++col) {
            if (col) {
                fputc(',', move_file);
            }
            write_stat(move_file, moves[row * library->slot_count + col]);
        }
        fputc('\n', move_file);
    }
    for (size_t row = 0; row < library->drive_count; ++row) {
        for (size_t col = 0; col < library->slot_count; ++col) {
            if (col) {
                fputc(',', store_file);
            }
            write_stat(store_file, stores[col * library->drive_count + row]);
        }
        fputc('\n', store_file);
    }
    for (size_t row = 0; row < library->slot_count; ++row) {
        for (size_t col = 0; col < library->drive_count; ++col) {
            if (col) {
                fputc(',', load_file);
            }
            write_stat(load_file, loads[col * library->slot_count + row]);
        }
        fputc('\n', load_file);
    }
    if (fclose(load_file) != 0 || fclose(store_file) != 0 ||
        fclose(move_file) != 0) {
    }
    if (save_metadata(library->drive_count, library->slot_count) == 0) {
        free(loads);
        free(stores);
        free(moves);
        return 0;
    }
    errno = EIO;

fail: // Some cleanup in case the funtion fails
    free(loads);
    free(stores);
    free(moves);
    return -1;
}

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

    library_deinit(&library);
    return 0;
}
