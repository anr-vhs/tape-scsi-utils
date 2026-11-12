cmake_minimum_required(VERSION 3.10)

project(tape_scsi_utils C)

set(INCLUDEDIR "include")

include_directories(${INCLUDEDIR})

##### Library #####
add_library(tapelibrary SHARED)

target_sources(tapelibrary
  PRIVATE
    src/changer.c
    src/drive.c
    src/drive.c
    src/library.c

  PUBLIC
    FILE_SET HEADERS
    BASE_DIRS
      include
    FILES
      include/tapelib.h
)

##### Tape manipulation util #####
add_executable(tape)
target_sources(tape
  PRIVATE
    src/tape.c
)
target_link_libraries(tape tapelibrary)

##### Benchmark #####
add_executable(bench)
target_sources(bench
  PRIVATE
    src/bench.c
    src/stopwatch_utils.c
)
target_link_libraries(bench tapelibrary)
target_link_libraries(bench m)

install(TARGETS tapelibrary)
install(TARGETS tape)
