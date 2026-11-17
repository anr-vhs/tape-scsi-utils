#define _GNU_SOURCE
#include "tapelib.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/mtio.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "logger.h"

int drive_init(Drive *drive, const char *device_path) {
    struct mtget info;

    memset(drive, 0, sizeof(*drive));
    drive->fd = open(device_path, O_RDWR | O_CLOEXEC);
    if (drive->fd < 0) {
        log_perror();
        return -1;
    }

    if (ioctl(drive->fd, MTIOCGET, &info) < 0) {
        log_perror();
        close(drive->fd);
        drive->fd = -1;
        return -1;
    }
    drive->block_size =
        (size_t)((info.mt_dsreg & MT_ST_BLKSIZE_MASK) >> MT_ST_BLKSIZE_SHIFT);

    log_trace("Drive %s init, block size is %zu", device_path, drive->block_size);

    return 0;
}

void drive_deinit(Drive *drive) {
    if (drive != NULL && drive->fd >= 0) {
        close(drive->fd);
        drive->fd = -1;
    }
}

int drive_rewind(Drive *drive) {
    struct mtop op = {.mt_op = MTREW};
    if (ioctl(drive->fd, MTIOCTOP, &op) < 0) {
        log_perror();
        return -1;
    }
    return 0;
}

int drive_ensure_logical_block(Drive *drive) {
    struct mtop op = {
        .mt_op = MTSETDRVBUFFER,
        .mt_count = MT_ST_BOOLEANS | MT_ST_SCSI2LOGICAL,
    };

    if (ioctl(drive->fd, MTIOCTOP, &op) < 0) {
        log_perror();
        return -1;
    }

    return 0;
}

int drive_seek(Drive *drive, size_t block) {
    struct mtop op = {.mt_op = MTSEEK, .mt_count = (int)block};
    if (ioctl(drive->fd, MTIOCTOP, &op) < 0) {
        log_perror();
        return -1;
    }
    return 0;
}

size_t drive_tell(const Drive *drive) {
    struct mtpos pos;
    if (ioctl(drive->fd, MTIOCPOS, &pos) < 0) {
        log_perror();
        return SIZE_MAX;
    }
    return (size_t)pos.mt_blkno;
}

int drive_set_block_size(Drive *drive, size_t block_size) {
    struct mtop op = {
        .mt_op = MTSETBLK,
        .mt_count = (int)block_size
    };
    if (ioctl(drive->fd, MTIOCTOP, &op) < 0) {
        log_perror();
        return -1;
    }
    drive->block_size = block_size;
    return 0;
}

int drive_write(Drive *drive, const void *data, size_t size) {
    void *to_write = data;
    size_t buffer_size = size;
    if (drive->block_size != 0) {
        size_t blocks = size / drive->block_size + 1;
        buffer_size = blocks * drive->block_size;
        to_write = malloc(buffer_size);
        memcpy(to_write, data, size);
    }

    size_t written = write(drive->fd, to_write, buffer_size);

    if (drive->block_size != 0) {
        free(to_write);
    }

    if (written != buffer_size) {
        log_perror();
        return 1;
    }
    return 0;
}

int drive_read(Drive *drive, void *data, size_t size) {
    void *to_read = data;
    size_t buffer_size = size;
    if (drive->block_size != 0) {
        size_t blocks = size / drive->block_size + 1;
        buffer_size = blocks * drive->block_size;
        to_read = malloc(buffer_size);
        memcpy(to_read, data, size);
    }

    size_t bytes_read = read(drive->fd, to_read, buffer_size);

    if (bytes_read != buffer_size) {
        log_perror();
        if (drive->block_size != 0) {
            free(to_read);
        }
        return 1;
    }

    if (drive->block_size != 0) {
        memcpy(data, to_read, size);
        free(to_read);
    }
    return 0;
}
