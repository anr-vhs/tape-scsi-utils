#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <linux/chio.h>

typedef enum { TRACE, DEBUG, INFO, WARN, ERROR } LogLevel;

#define TAPE_VOLUME_TAG_SIZE 36

typedef enum {
    TAPE_ELEMENT_SLOT = CHET_ST,
    TAPE_ELEMENT_DRIVE = CHET_DT,
} TapeElementKind;

typedef struct {
    bool full; /**< Nonzero when the element contains media. */
    unsigned char
        tag[TAPE_VOLUME_TAG_SIZE]; /**< The element's primary volume tag. */
} TapeElement;

/** Open tape drive handle and its current fixed block size. */
typedef struct {
    int fd;            /**< File descriptor for the drive device. */
    size_t block_size; /**< Zero indicates variable block size. */
} Drive;

/** Open media-changer handle and its element counts. */
typedef struct {
    int fd;             /**< File descriptor for the changer device. */
    size_t drive_count; /**< Number of data-transfer elements. */
    size_t slot_count;  /**< Number of storage elements. */
} Changer;

/** A tape drive and its associated device path and media state. */
typedef struct {
    char *path;   /**< Owned copy of the drive device path. */
    Drive *drive; /**< Open drive when media is loaded, otherwise NULL. */
    TapeElement content; /**< Cached media state for the drive. */
} LibraryDrive;

/** Cached media state for one storage slot. */
typedef struct {
    TapeElement content;
} LibrarySlot;

/** Coordinates a changer, its drives, and cached slot contents. */
typedef struct {
    Changer changer;
    LibraryDrive *drives;
    size_t drive_count;
    LibrarySlot *slots;
    size_t slot_count;
} Library;

/**
 * @brief Sets the logging level of the library
 * @param level The now log level
 */
void set_log_level(LogLevel level);

/**
 * @brief Create a drive object for a tape device.
 * @param drive Drive object to initialize.
 * @param device_path Absolute or relative path to the device file.
 * @return 0 on success; -1 on failure. Reports system errors to stderr.
 */
int drive_init(Drive *drive, const char *device_path);
/** Close the tape device and invalidate its file descriptor. */
void drive_deinit(Drive *drive);
/** Rewinds the tape */
int drive_rewind(Drive *drive);
/** Ensures that the driver uses the logical block addresses defined
 * in the SCSI-2 standard when performing the seek and tell operations
 */
int drive_ensure_logical_block(Drive *drive);
/** Seek to a tape block. */
int drive_seek(Drive *drive, size_t block);
/** Tell which block the reader is on. */
size_t drive_tell(const Drive *drive);
/**
 * Set the tape block size. A block size of 0 means variable block size.
 */
int drive_set_block_size(Drive *drive, size_t block_size);
/**
 * Write data to tape, padding it with zeroes to a block boundary when using
 * fixed-size blocks. The data is written as a single record.
 */
int drive_write(Drive *drive, const void *data, size_t size);
/**
 * Read data from tape, discarding any bytes beyond @p size when using
 * fixed-size blocks.
 */
int drive_read(Drive *drive, void *data, size_t size);

/** Open a changer device and read its drive and slot counts. */
int changer_init(Changer *changer, const char *device_path);
/** Close the changer device and invalidate its file descriptor. */
void changer_deinit(Changer *changer);
/** Move a tape from one changer element to another. */
int changer_move(const Changer *changer, TapeElementKind source_kind,
                 size_t source_id, TapeElementKind dest_kind, size_t dest_id);
/** Load a tape from a slot into a drive. */
int changer_load(const Changer *changer, size_t slot, size_t drive);
/** Store a tape from a drive into a slot. */
int changer_store(const Changer *changer, size_t drive, size_t slot);
/** Move the robot arm to the specified element position. */
int changer_move_arm(const Changer *changer, TapeElementKind kind,
                     size_t position);
/**
 * Get the contents of all drives or all storage slots.
 * @param changer Changer to query.
 * @param kind Element kind; must be TAPE_ELEMENT_DRIVE or TAPE_ELEMENT_SLOT.
 * @param[out] count Receives the number of elements in the array.
 * @return An allocated array of element states. The
 * caller owns the array and must release it with free().
 * Returns NULL on failure.
 */
TapeElement *changer_get_contents(const Changer *changer, TapeElementKind kind,
                                  size_t *count);

/**
 * @brief Initialize a library and query its changer's current media state.
 * @param changer_path Path to the media changer device.
 * @param drive_paths Device paths, one for each changer drive.
 * @param drive_count Number of drive paths; must match the changer.
 * @return 0 on success; -1 on failure.
 */
int library_init(Library *library, const char *changer_path,
                 const char *const *drive_paths, size_t drive_count);
/** Close all open devices and release library-owned memory. */
void library_deinit(Library *library);
/** Load a tape from a slot into an empty drive. */
int library_load(Library *library, size_t slot, size_t drive);
/** Store a tape from a drive into an empty slot. */
int library_store(Library *library, size_t drive, size_t slot);
/**
 * Move a tape between slots or drives, updating the library's cached contents.
 */
int library_move(Library *library, TapeElementKind source_kind,
                 size_t source_id, TapeElementKind dest_kind, size_t dest_id);
