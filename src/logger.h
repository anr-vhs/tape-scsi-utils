#pragma once

#include <errno.h>
#include <stdio.h>
#include <string.h>

typedef enum {
    TRACE,
    DEBUG,
    INFO,
    WARN,
    ERROR
} LogLevel;

extern LogLevel log_level;

#define ESC "\x1B"
#define ESC_RESET ESC "[0m"
#define BOLD ESC "[1m"
#define RED ESC "[31m"
#define YELLOW ESC "[33m"
#define CYAN ESC "[36m"
#define GRAY ESC "[90m"

#define log_trace(format, ...) if (log_level <= TRACE) {fprintf(stderr, BOLD GRAY "[TRACE]" ESC_RESET " %s (%s:%d) : " format "\n", __func__, __FILE__, __LINE__, ##__VA_ARGS__);}
#define log_debug(format, ...) if (log_level <= DEBUG) {fprintf(stderr, BOLD "[DEBUG]" ESC_RESET " %s (%s:%d) : " format "\n", __func__, __FILE__, __LINE__, ##__VA_ARGS__);}
#define log_info(format, ...) if (log_level <= INFO) {fprintf(stderr, BOLD CYAN "[INFO]" ESC_RESET " %s (%s:%d) : " format "\n", __func__, __FILE__, __LINE__, ##__VA_ARGS__);}
#define log_warn(format, ...) if (log_level <= WARN) {fprintf(stderr, BOLD YELLOW "[WARN]" ESC_RESET " %s (%s:%d) : " format "\n", __func__, __FILE__, __LINE__, ##__VA_ARGS__);}
#define log_error(format, ...) if (log_level <= ERROR) {fprintf(stderr, BOLD RED "[ERROR]" ESC_RESET " %s (%s:%d) : " format "\n", __func__, __FILE__, __LINE__, ##__VA_ARGS__);}
#define log_perror() log_error("%s", strerror(errno))
