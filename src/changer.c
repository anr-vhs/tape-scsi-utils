#define _GNU_SOURCE
#include "tapelib.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/chio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "logger.h"

int changer_init(Changer *changer, const char *device_path) {
    struct changer_params params;
    memset(changer, 0, sizeof(*changer));
    changer->fd = open(device_path, O_RDWR | O_CLOEXEC);
    if (changer->fd < 0) {
        log_perror();
        return -1;
    }
    if (ioctl(changer->fd, CHIOGPARAMS, &params) < 0) {
        log_perror();
        close(changer->fd);
        changer->fd = -1;
        return -1;
    }
    if (params.cp_ndrives < 0 || params.cp_nslots < 0) {
        close(changer->fd);
        changer->fd = -1;
        errno = EPROTO;
        return -1;
    }
    changer->drive_count = (size_t)params.cp_ndrives;
    changer->slot_count = (size_t)params.cp_nslots;
    log_trace(
        "Changer at %s init with %zu drives, %zu slots, %d arms, %d I/O slots",
        device_path, changer->drive_count, changer->slot_count,
        params.cp_npickers, params.cp_nportals);
    return 0;
}

void changer_deinit(Changer *changer) {
    if (changer != NULL && changer->fd >= 0) {
        close(changer->fd);
        changer->fd = -1;
    }
}

static int validate_element(const Changer *changer, TapeElementKind kind,
                            size_t id) {
    size_t limit;
    if (kind == TAPE_ELEMENT_DRIVE) {
        limit = changer->drive_count;
    } else if (kind == TAPE_ELEMENT_SLOT) {
        limit = changer->slot_count;
    } else {
        errno = EINVAL;
        return -1;
    }
    if (id >= limit || id > INT_MAX) {
        errno = ERANGE;
        return -1;
    }
    return 0;
}

static char *drive_str = "drive";
static char *slot_str = "slot";
static char *unkonwn_element_str = "element";

static char *get_element_kind_str(TapeElementKind kind) {
    switch (kind) {
    case TAPE_ELEMENT_DRIVE:
        return drive_str;
    case TAPE_ELEMENT_SLOT:
        return slot_str;
    default:
        return unkonwn_element_str;
    }
}

int changer_move(const Changer *changer, TapeElementKind source_kind,
                 size_t source_id, TapeElementKind dest_kind, size_t dest_id) {
    struct changer_move move;
    if (validate_element(changer, source_kind, source_id) < 0 ||
        validate_element(changer, dest_kind, dest_id) < 0) {
        return -1;
    }
    move.cm_fromtype = source_kind;
    move.cm_fromunit = (int)source_id;
    move.cm_totype = dest_kind;
    move.cm_tounit = (int)dest_id;
    move.cm_flags = 0;
    if (ioctl(changer->fd, CHIOMOVE, &move) < 0) {
        log_perror();
        return -1;
    }
    log_debug("Changer moved from %s %lu to %s %lu",
              get_element_kind_str(source_kind), source_id,
              get_element_kind_str(dest_kind), dest_id);
    return 0;
}

int changer_load(const Changer *changer, size_t slot, size_t drive) {
    return changer_move(changer, TAPE_ELEMENT_SLOT, slot, TAPE_ELEMENT_DRIVE,
                        drive);
}

int changer_store(const Changer *changer, size_t drive, size_t slot) {
    return changer_move(changer, TAPE_ELEMENT_DRIVE, drive, TAPE_ELEMENT_SLOT,
                        slot);
}

int changer_move_arm(const Changer *changer, TapeElementKind kind,
                     size_t position) {
    struct changer_position pos;
    if (validate_element(changer, kind, position) < 0) {
        return -1;
    }
    pos.cp_type = kind;
    pos.cp_unit = (int)position;
    pos.cp_flags = 0;
    if (ioctl(changer->fd, CHIOPOSITION, &pos) < 0) {
        log_perror();
        return -1;
    }
    return 0;
}

TapeElement *changer_get_contents(const Changer *changer, TapeElementKind kind,
                                  size_t *count) {
    if (kind == TAPE_ELEMENT_DRIVE) {
        log_trace("Getting contents of drives");
        *count = changer->drive_count;
    } else if (kind == TAPE_ELEMENT_SLOT) {
        log_trace("Getting contents of slots");
        *count = changer->slot_count;
    } else {
        errno = EINVAL;
        return NULL;
    }

    if (*count == 0) {
        return NULL;
    }

    TapeElement *result = calloc(*count, sizeof(*result));
    unsigned char *status_data = calloc(*count, sizeof(*status_data));

    struct changer_element_status status = {
        .ces_type = kind,
        .ces_data = status_data,
    };

    if (ioctl(changer->fd, CHIOGSTATUS, &status) < 0) {
        log_perror();
        free(result);
        free(status_data);
        return NULL;
    }
    for (int i = 0; i < *count; ++i) {
        if ((status_data[i] & CESTATUS_FULL) == 0) {
            continue;
        }
        struct changer_get_element element = {
            .cge_type = kind,
            .cge_unit = i,
        };
        if (ioctl(changer->fd, CHIOGELEM, &element) < 0) {
            log_perror();
            free(result);
            free(status_data);
            return NULL;
        }
        result[i].full = 1;
        memcpy(result[i].tag, element.cge_pvoltag, TAPE_VOLUME_TAG_SIZE);
        result[i].tag[TAPE_VOLUME_TAG_SIZE-1] = '\0';
    }
    free(status_data);
    return result;
}
