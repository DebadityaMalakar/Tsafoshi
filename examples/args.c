#include <stdio.h>

/* Every argument the command line handed this program.
 *
 * argc() and argv() rather than main(int argc, char **argv): naming that
 * second parameter needs a pointer type, and pointers are stage 3.3. The
 * information is the same either way, and argv(argc()) is a null pointer for
 * exactly the reason it is in C. */

int main(void)
{
    int i;

    printf("%d argument", argc());
    if (argc() != 1)
        printf("s");
    printf(":\n");

    for (i = 0; i < argc(); i = i + 1)
        printf("  %d  %s\n", i, argv(i));

    return 0;
}
