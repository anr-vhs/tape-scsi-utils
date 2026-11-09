#include "tapelib.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include "logger.h"

LogLevel log_level = INFO;

void set_log_level(LogLevel level) {
    log_level = level;
}

static int library_validate_index(size_t index, size_t count) {
    if (index >= count) {
        errno = ERANGE;
        return -1;
    }
    return 0;
}

int library_init(Library *library, const char *changer_path,
                 const char *const *drive_paths, size_t drive_count) {
    TapeElement *drive_contents = NULL;
    TapeElement *slot_contents = NULL;
    size_t contents_count = 0;
    memset(library, 0, sizeof(*library));
    library->changer.fd = -1;
    if (changer_init(&library->changer, changer_path) < 0) {
        log_perror();
        return -1;
    }
    if (library->changer.drive_count != drive_count) {
        errno = EINVAL;
        log_error("Drive counts not matching %lu != %lu", library->changer.drive_count, drive_count);
        goto fail;
    }
    library->drive_count = drive_count;
    library->slot_count = library->changer.slot_count;
    library->drives = calloc(drive_count, sizeof(*library->drives));
    library->slots = calloc(library->slot_count, sizeof(*library->slots));
    if (changer_get_contents(&library->changer, TAPE_ELEMENT_DRIVE,
                             &drive_contents, &contents_count) < 0) {
                                 log_perror();
        goto fail;
    }
    for (size_t i = 0; i < drive_count; ++i) {
        library->drives[i].path = strdup(drive_paths[i]);
        if (library->drives[i].path == NULL) {
            goto fail;
        }
        library->drives[i].content = drive_contents[i];
        if (drive_contents[i].full) {
            library->drives[i].drive = malloc(sizeof(Drive));
            if (library->drives[i].drive == NULL) {
                goto fail;
            }
            if (drive_init(library->drives[i].drive, drive_paths[i]) < 0) {
                goto fail;
            }
        }
    }
    free(drive_contents);
    drive_contents = NULL;
    if (changer_get_contents(&library->changer, TAPE_ELEMENT_SLOT,
                             &slot_contents, &contents_count) < 0) {
        goto fail;
    }
    for (size_t i = 0; i < library->slot_count; ++i) {
        library->slots[i].content = slot_contents[i];
    }
    free(slot_contents);
    return 0;

fail:
    free(drive_contents);
    free(slot_contents);
    library_deinit(library);
    return -1;
}

void library_deinit(Library *library) {
    if (library == NULL) {
        return;
    }
    for (size_t i = 0; i < library->drive_count; ++i) {
        if (library->drives != NULL) {
            if (library->drives[i].drive != NULL) {
                drive_deinit(library->drives[i].drive);
                free(library->drives[i].drive);
            }
            free(library->drives[i].path);
        }
    }
    free(library->drives);
    free(library->slots);
    changer_deinit(&library->changer);
    memset(library, 0, sizeof(*library));
    library->changer.fd = -1;
}

int library_load(Library *library, size_t slot, size_t drive) {
    if (library_validate_index(slot, library->slot_count) < 0 ||
        library_validate_index(drive, library->drive_count) < 0) {
        return -1;
    }
    if (!library->slots[slot].content.full ||
        library->drives[drive].content.full) {
        errno = !library->slots[slot].content.full ? ENODATA : ENOSPC;
        return -1;
    }
    if (changer_load(&library->changer, slot, drive) < 0) {
        return -1;
    }
    Drive *opened = malloc(sizeof(*opened));
    if (opened == NULL) {
        int saved_errno = errno;
        (void)changer_store(&library->changer, drive, slot);
        errno = saved_errno;
        return -1;
    }
    if (drive_init(opened, library->drives[drive].path) < 0) {
        int saved_errno = errno;
        free(opened);
        (void)changer_store(&library->changer, drive, slot);
        errno = saved_errno;
        return -1;
    }
    library->drives[drive].drive = opened;
    library->drives[drive].content = library->slots[slot].content;
    library->slots[slot].content.full = 0;
    return 0;
}

int library_store(Library *library, size_t drive, size_t slot) {
    if (library_validate_index(drive, library->drive_count) < 0 ||
        library_validate_index(slot, library->slot_count) < 0) {
        return -1;
    }
    if (!library->drives[drive].content.full ||
        library->slots[slot].content.full) {
        errno = !library->drives[drive].content.full ? ENODATA : ENOSPC;
        return -1;
    }
    drive_deinit(library->drives[drive].drive);
    if (changer_store(&library->changer, drive, slot) < 0) {
        int saved_errno = errno;
        if (drive_init(library->drives[drive].drive,
                       library->drives[drive].path) < 0) {
            free(library->drives[drive].drive);
            library->drives[drive].drive = NULL;
        }
        errno = saved_errno;
        return -1;
    }
    free(library->drives[drive].drive);
    library->drives[drive].drive = NULL;
    library->slots[slot].content = library->drives[drive].content;
    library->drives[drive].content.full = 0;
    return 0;
}

int library_move(Library *library, TapeElementKind source_kind,
                 size_t source_id, TapeElementKind dest_kind, size_t dest_id) {
    if (source_kind == TAPE_ELEMENT_SLOT && dest_kind == TAPE_ELEMENT_DRIVE) {
        return library_load(library, source_id, dest_id);
    }
    if (source_kind == TAPE_ELEMENT_DRIVE && dest_kind == TAPE_ELEMENT_SLOT) {
        return library_store(library, source_id, dest_id);
    }
    if (source_kind == TAPE_ELEMENT_SLOT && dest_kind == TAPE_ELEMENT_SLOT) {
        if (library_validate_index(source_id, library->slot_count) < 0 ||
            library_validate_index(dest_id, library->slot_count) < 0) {
            return -1;
        }
        if (!library->slots[source_id].content.full ||
            library->slots[dest_id].content.full) {
            errno = !library->slots[source_id].content.full ? ENODATA : ENOSPC;
            return -1;
        }
        if (changer_move(&library->changer, source_kind, source_id, dest_kind,
                         dest_id) < 0) {
            return -1;
        }
        library->slots[dest_id].content = library->slots[source_id].content;
        library->slots[source_id].content.full = 0;
        return 0;
    }
    if (source_kind == TAPE_ELEMENT_DRIVE && dest_kind == TAPE_ELEMENT_DRIVE) {
        if (library_validate_index(source_id, library->drive_count) < 0 ||
            library_validate_index(dest_id, library->drive_count) < 0) {
            return -1;
        }
        if (!library->drives[source_id].content.full ||
            library->drives[dest_id].content.full) {
            errno = !library->drives[source_id].content.full ? ENODATA : ENOSPC;
            return -1;
        }
        if (library->drives[source_id].drive != NULL) {
            drive_deinit(library->drives[source_id].drive);
            free(library->drives[source_id].drive);
            library->drives[source_id].drive = NULL;
        }
        if (changer_move(&library->changer, source_kind, source_id, dest_kind,
                         dest_id) < 0) {
            Drive *restored = malloc(sizeof(*restored));
            if (restored != NULL &&
                drive_init(restored, library->drives[source_id].path) == 0) {
                library->drives[source_id].drive = restored;
            } else {
                free(restored);
            }
            return -1;
        }
        Drive *opened = malloc(sizeof(*opened));
        if (opened == NULL ||
            drive_init(opened, library->drives[dest_id].path) < 0) {
            free(opened);
            return -1;
        }
        library->drives[dest_id].drive = opened;
        library->drives[dest_id].content = library->drives[source_id].content;
        library->drives[source_id].content.full = 0;
        return 0;
    }
    errno = EINVAL;
    return -1;
}
