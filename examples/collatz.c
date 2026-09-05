#include <stdio.h>

/* The longest Collatz chain for any start below 1000. No arrays yet, so the
   record is kept in two plain variables -- which is all it ever needed. */

int chain(int n)
{
    int steps = 0;
    while (n != 1) {
        if (n % 2 == 0)
            n = n / 2;
        else
            n = 3 * n + 1;
        steps = steps + 1;
    }
    return steps;
}

int main(void)
{
    int best = 0;
    int longest = 0;

    for (int i = 1; i < 1000; i = i + 1) {
        int len = chain(i);
        if (len > longest) {
            longest = len;
            best = i;
        }
    }

    printf("%d has the longest chain below 1000: %d steps\n", best, longest);
    return 0;
}
