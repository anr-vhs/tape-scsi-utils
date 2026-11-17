REMOTE := "bran:/home/delyon/tape-scsi-utils"

sync:
    rsync -r include src CMakeLists.txt {{REMOTE}}

sync_back:
    rsync -r {{REMOTE}}/include {{REMOTE}}/src {{REMOTE}}/CMakeLists.txt .

setup_build:
    mkdir -p build
    cmake -B build

[working-directory('build')]
build: setup_build
    make -j
