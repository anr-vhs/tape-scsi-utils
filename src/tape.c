#define _GNU_SOURCE
#include "tapelib.h"

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "logger.h"

static void print_help(const char *command) {
    printf("Help :\n"
           "%s <operation> [args]...\n\n"
           "Available operations :\n"
           "    help : Show this message and exit\n"
           "  Changer operations\n"
           "    load <slot> <drive> [device] : Load a tape from a slot to a "
           "drive\n"
           "    store <drive> <slot> [device] : Store a tape from a drive to a "
           "slot\n"
           "    contents [device] : Get the contents of each drive and slot\n"
           "  Tape drive operations\n"
           "    tell <device> : Tell at which block the reader is in the tape\n"
           "    seek <device> <block> : Seek to the block\n",
           command);
}

static size_t parse_size(const char *text) {
    char *end = NULL;
    errno = 0;
    size_t parsed = strtoul(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' || parsed > SIZE_MAX) {
        errno = EINVAL;
        return 0;
    }
    return parsed;
}

static void print_tag(const unsigned char tag[TAPE_VOLUME_TAG_SIZE]) {
    fwrite(tag, 1, TAPE_VOLUME_TAG_SIZE, stdout);
    putchar('\n');
}

static int print_contents(const Changer *changer) {
    const TapeElementKind kinds[] = {TAPE_ELEMENT_DRIVE, TAPE_ELEMENT_SLOT};
    const char *names[] = {"Drive", "Slot"};
    for (size_t k = 0; k < 2; ++k) {
        TapeElement *contents = NULL;
        size_t count = 0;
        if (changer_get_contents(changer, kinds[k], &contents, &count) < 0) {
            return -1;
        }
        for (size_t i = 0; i < count; ++i) {
            printf("%s %zu: ", names[k], i);
            if (contents[i].full) {
                print_tag(contents[i].tag);
            } else {
                puts("Empty");
            }
        }
        free(contents);
    }
    return 0;
}

int main(int argc, char **argv) {
    set_log_level(TRACE);

    if (argc < 2) {
        print_help(argv[0]);
        return 1;
    }
    if (strcmp(argv[1], "help") == 0) {
        print_help(argv[0]);
        return 0;
    }

    if (strcmp(argv[1], "load") == 0) {
        if (argc < 4) {
            log_error("Invalid usage");
            print_help(argv[0]);
            return 1;
        }
        size_t source = parse_size(argv[2]);
        size_t destination = parse_size(argv[3]);

        if (errno == EINVAL) {
            log_error("Invalid usage");
            print_help(argv[0]);
        }

        Changer changer;
        const char *device = argc == 5 ? argv[4] : "/dev/sch0";
        if (changer_init(&changer, device) < 0) {
            return 1;
        }
        int result = changer_load(&changer, source, destination);

        changer_deinit(&changer);
        return result;
    }

    if (strcmp(argv[1], "store") == 0) {
        if (argc < 4) {
            log_error("Invalid usage");
            print_help(argv[0]);
            return 1;
        }
        size_t source = parse_size(argv[2]);
        size_t destination = parse_size(argv[3]);

        if (errno == EINVAL) {
            log_error("Invalid usage");
            print_help(argv[0]);
        }

        Changer changer;
        const char *device = argc == 5 ? argv[4] : "/dev/sch0";
        if (changer_init(&changer, device) < 0) {
            return 1;
        }
        int result = changer_store(&changer, source, destination);

        changer_deinit(&changer);
        return result;
    }

    if (strcmp(argv[1], "contents") == 0) {
        if (argc != 2 && argc != 3) {
            fprintf(stderr, "Invalid usage\n");
            print_help(argv[0]);
            return 1;
        }
        Changer changer;
        if (changer_init(&changer, argc == 3 ? argv[2] : "/dev/sch0") < 0) {
            return 1;
        }
        int result = print_contents(&changer);
        changer_deinit(&changer);
        return result == 0 ? 0 : 1;
    }

    if (strcmp(argv[1], "seek") == 0) {
        if (argc < 4) {
            log_error("Invalid usage");
            print_help(argv[0]);
            return 1;
        }

        Drive drive;
        if (drive_init(&drive, argv[2]) < 0) {
            return 1;
        }

        if (drive.block_size == 0) {
            log_warn("Tape has variable block size");
        }

        size_t block = parse_size(argv[3]);
        int result = 0;
        if (drive_seek(&drive, block)) {
            log_error("Could not seek to block %lu", block);
            result = 1;
        }

        drive_deinit(&drive);
        return result;
    }

    if (strcmp(argv[1], "tell") == 0) {
        if (argc < 3) {
            log_error("Invalid usage");
            print_help(argv[0]);
            return 1;
        }

        Drive drive;
        if (drive_init(&drive, argv[2]) < 0) {
            return 1;
        }

        if (drive.block_size == 0) {
            log_warn("Tape has variable block size");
        }

        size_t block = drive_tell(&drive);
        int result = 0;
        if (block != SIZE_MAX) {
            printf("%zu", block);
        } else {
            log_error("Could not get current block");
            result = 1;
        }

        drive_deinit(&drive);
        return result;
    }

    log_error("Invalid usage\n");
    print_help(argv[0]);
    return 1;
}
