// The package's smoke test: compiled with the packaged ceresc against the packaged C library (--stdlib) and run
// on the packaged ceres. What it prints is compared with hello.expected.
#include <stdio.h>
#include <string.h>
#include <math.h>

int main(int argc, char** argv)
{
    printf("Hello from Ceres: %d argument(s), sqrt(2) = %.6f, %zu\n", argc, sqrt(2.0), strlen("ceres"));
    return argc == 2 && strcmp(argv[1], "smoke") == 0 ? 0 : 1;
}
