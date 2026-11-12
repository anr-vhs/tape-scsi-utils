sync:
    rsync -r include src bran:/home/delyon/tape-scsi-utils

setup_build:
    mkdir -p build
    cmake -B build

[working-directory('build')]
build: setup_build
    make -j
