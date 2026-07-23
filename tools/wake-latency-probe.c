#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void usage(FILE *stream)
{
    fprintf(stream,
            "Usage: wake-latency-probe --duration SECONDS --output FILE "
            "[--interval-ms MILLISECONDS]\n");
}

static int parse_positive_int(const char *text, const char *option)
{
    char *end = NULL;
    long value;

    errno = 0;
    value = strtol(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' || value < 1 ||
        value > INT_MAX) {
        fprintf(stderr, "%s must be a positive integer\n", option);
        exit(2);
    }

    return (int)value;
}

static struct timespec add_milliseconds(struct timespec value, int milliseconds)
{
    value.tv_sec += milliseconds / 1000;
    value.tv_nsec += (long)(milliseconds % 1000) * 1000000L;
    if (value.tv_nsec >= 1000000000L) {
        value.tv_sec++;
        value.tv_nsec -= 1000000000L;
    }
    return value;
}

static long long difference_nanoseconds(struct timespec later,
                                        struct timespec earlier)
{
    return (long long)(later.tv_sec - earlier.tv_sec) * 1000000000LL +
           (long long)later.tv_nsec - earlier.tv_nsec;
}

int main(int argc, char **argv)
{
    int duration = 0;
    int interval_ms = 10;
    const char *output_path = NULL;
    FILE *output;
    struct timespec start;
    struct timespec deadline;
    long long sample_count;

    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], "--help") == 0 ||
            strcmp(argv[index], "-h") == 0) {
            usage(stdout);
            return 0;
        }
        if (strcmp(argv[index], "--duration") == 0 && index + 1 < argc) {
            duration = parse_positive_int(argv[++index], "--duration");
            continue;
        }
        if (strcmp(argv[index], "--interval-ms") == 0 && index + 1 < argc) {
            interval_ms =
                parse_positive_int(argv[++index], "--interval-ms");
            continue;
        }
        if (strcmp(argv[index], "--output") == 0 && index + 1 < argc) {
            output_path = argv[++index];
            continue;
        }

        fprintf(stderr, "Unknown or incomplete argument: %s\n", argv[index]);
        usage(stderr);
        return 2;
    }

    if (duration < 1) {
        fprintf(stderr, "--duration must be a positive integer\n");
        return 2;
    }
    if (interval_ms > 1000) {
        fprintf(stderr, "--interval-ms must be between 1 and 1000\n");
        return 2;
    }
    if (output_path == NULL) {
        fprintf(stderr, "--output is required\n");
        return 2;
    }

    output = fopen(output_path, "w");
    if (output == NULL) {
        fprintf(stderr, "Cannot open %s: %s\n", output_path, strerror(errno));
        return 2;
    }

    if (clock_gettime(CLOCK_MONOTONIC, &start) != 0) {
        fprintf(stderr, "clock_gettime failed: %s\n", strerror(errno));
        fclose(output);
        return 1;
    }
    deadline = start;
    sample_count = (long long)duration * 1000 / interval_ms;

    fprintf(output, "sample,elapsed_ms,latency_us\n");

    for (long long sample = 1; sample <= sample_count; sample++) {
        struct timespec actual;
        long long elapsed_ns;
        long long latency_ns;
        int result;

        deadline = add_milliseconds(deadline, interval_ms);
        do {
            result = clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &deadline,
                                     NULL);
        } while (result == EINTR);
        if (result != 0) {
            fprintf(stderr, "clock_nanosleep failed: %s\n", strerror(result));
            fclose(output);
            return 1;
        }
        if (clock_gettime(CLOCK_MONOTONIC, &actual) != 0) {
            fprintf(stderr, "clock_gettime failed: %s\n", strerror(errno));
            fclose(output);
            return 1;
        }

        elapsed_ns = difference_nanoseconds(actual, start);
        latency_ns = difference_nanoseconds(actual, deadline);
        if (latency_ns < 0) {
            latency_ns = 0;
        }

        fprintf(output, "%lld,%.3f,%.3f\n", sample,
                (double)elapsed_ns / 1000000.0,
                (double)latency_ns / 1000.0);
    }

    if (fclose(output) != 0) {
        fprintf(stderr, "Cannot close %s: %s\n", output_path, strerror(errno));
        return 1;
    }

    printf("Wrote %lld samples to %s\n", sample_count, output_path);
    return 0;
}
