CC := /usr/bin/gcc
CFLAGS ?= -O2 -Wall -Wextra -Wpedantic -I./include -g
LDFLAGS += -lm

BUILD_DIR := build
OBJ_DIR := $(BUILD_DIR)/obj
BIN_DIR := $(BUILD_DIR)/bin
LIB_DIR := $(BUILD_DIR)/lib

SRCS := src/changer.c src/drive.c src/library.c

LIBNAME = tapelibrary
TAPELIB = $(LIB_DIR)/lib$(LIBNAME).so

.PHONY: all clean

all: $(BIN_DIR)/tape $(BIN_DIR)/bench $(TAPELIB)

$(OBJ_DIR):
	mkdir -p $@
$(BIN_DIR):
	mkdir -p $@
$(LIB_DIR):
	mkdir -p $@

$(OBJ_DIR)/%.o: src/%.c | $(OBJ_DIR)
	$(CC) $(CFLAGS) -fPIC -c $< -o $@

$(TAPELIB): $(OBJ_DIR)/changer.o $(OBJ_DIR)/drive.o $(OBJ_DIR)/library.o | $(LIB_DIR)
	$(CC) -shared $(LDFLAGS) $^ -o $@

$(BIN_DIR)/tape: $(OBJ_DIR)/tape.o $(TAPELIB) | $(BIN_DIR)
	$(CC) $(LDFLAGS) $< -L ./$(LIB_DIR) -l $(LIBNAME) -o $@

$(BIN_DIR)/bench: $(OBJ_DIR)/bench.o $(OBJ_DIR)/stopwatch_utils.o $(TAPELIB) | $(BIN_DIR)
	$(CC) $(LDFLAGS) $(OBJ_DIR)/bench.o $(OBJ_DIR)/stopwatch_utils.o -L ./$(LIB_DIR) -l $(LIBNAME) -o $@

clean:
	rm -r $(BUILD_DIR)
