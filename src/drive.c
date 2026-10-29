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

static int write_all_record(int fd, const void *data, size_t size) {
    ssize_t written = write(fd, data, size);
    if (written < 0 || (size_t)written != size) {
        if (written >= 0) {
            errno = EIO;
        }
        perror("write");
        return -1;
    }
    return 0;
}

int drive_init(Drive *drive, const char *device_path) {
    struct mtget info;
    memset(drive, 0, sizeof(*drive));
    drive->fd = open(device_path, O_RDWR | O_CLOEXEC);
    if (drive->fd < 0) {
        perror(device_path);
        return -1;
    }
    if (ioctl(drive->fd, MTIOCGET, &info) < 0) {
        perror("ioctl MTIOCGET");
        close(drive->fd);
        drive->fd = -1;
        return -1;
    }
    drive->block_size =
        (size_t)((info.mt_dsreg & MT_ST_BLKSIZE_MASK) >> MT_ST_BLKSIZE_SHIFT);
    return 0;
}

void drive_deinit(Drive *drive) {
    if (drive != NULL && drive->fd >= 0) {
        close(drive->fd);
        drive->fd = -1;
    }
}

int drive_seek(Drive *drive, size_t block) {
    struct mtop op = {.mt_op = MTSEEK, .mt_count = (int)block};
    if (block > INT32_MAX) {
        errno = EOVERFLOW;
        return -1;
    }
    if (ioctl(drive->fd, MTIOCTOP, &op) < 0) {
        perror("ioctl MTIOCTOP seek");
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
    struct mtop op;
    if (block_size > INT32_MAX) {
        errno = EOVERFLOW;
        return -1;
    }
    op.mt_op = MTSETBLK;
    op.mt_count = (int)block_size;
    if (ioctl(drive->fd, MTIOCTOP, &op) < 0) {
        perror("ioctl MTIOCTOP block size");
        return -1;
    }
    drive->block_size = block_size;
    return 0;
}

int drive_write_bytes(const Drive *drive, const void *data, size_t size) {
    return write_all_record(drive->fd, data, size);
}

int drive_read_bytes(const Drive *drive, void *data, size_t size) {
    ssize_t received = read(drive->fd, data, size);
    if (received < 0 || (size_t)received != size) {
        if (received >= 0) {
            errno = EIO;
        }
        perror("read");
        return -1;
    }
    return 0;
}

int drive_write(Drive *drive, const void *data, size_t size) {
    if (drive->block_size == 0) {
        return write_all_record(drive->fd, data, size);
    }

    size_t blocks = size / drive->block_size + 1;
    if (blocks > SIZE_MAX / drive->block_size) {
        errno = EOVERFLOW;
        return -1;
    }
    size_t buffer_size = blocks * drive->block_size;
    void *buffer = calloc(1, buffer_size);
    if (buffer == NULL) {
        return -1;
    }
    memcpy(buffer, data, size);
    int result = drive_write_bytes(drive, buffer, buffer_size);
    free(buffer);
    return result;
}

int drive_read(Drive *drive, void *data, size_t size) {
    if (drive->block_size == 0) {
        return drive_read_bytes(drive, data, size);
    }

    size_t blocks = size / drive->block_size + 1;
    if (blocks > SIZE_MAX / drive->block_size) {
        errno = EOVERFLOW;
        return -1;
    }
    size_t buffer_size = blocks * drive->block_size;
    void *buffer = malloc(buffer_size);
    if (buffer == NULL) {
        return -1;
    }
    int result = drive_read_bytes(drive, buffer, buffer_size);
    if (result == 0) {
        memcpy(data, buffer, size);
    }
    free(buffer);
    return result;
}
