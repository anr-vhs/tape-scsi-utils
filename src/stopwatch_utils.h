#include <sys/resource.h>
#include <time.h>

typedef struct {
    struct timespec wall;
    struct rusage usage;
} Snapshot;

typedef struct {
    Snapshot *start;
    Snapshot *end;
} Lap;

int reset_stopwatch();

int stopwatch_snapshot();

Lap get_lap(size_t index);
Lap get_last_lap();

double elapsed_io_ms(Lap lap);
