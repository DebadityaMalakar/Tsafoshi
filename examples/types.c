#include <stdio.h>

/* What a type is for, in an interpreter where every value is a 64-bit cell.
 *
 * The cell never changes width. The type says how wide the value in it is
 * allowed to be, and the narrowing happens once, where the value is stored --
 * so a char holding 300 really does hold 44, and says so afterwards. */

int main(void)
{
    char c;
    short s;
    int i;
    unsigned int u;
    long l;
    _Bool b;

    printf("sizeof: char %d, short %d, int %d, long %d, _Bool %d\n",
           sizeof(char), sizeof(short), sizeof(int), sizeof(long),
           sizeof(_Bool));

    c = 300;                            /* 300 does not fit in a char */
    s = 70000;                          /* nor 70000 in a short */
    i = 2147483648;                     /* nor this in an int */
    printf("narrowed: %d %d %d\n", c, s, i);

    u = -1;                             /* the same bits, read as unsigned */
    l = -1;
    printf("as unsigned: %u   as signed: %ld\n", u, l);
    printf("-1 > 0 is %d, but (unsigned)-1 > 0 is %d\n", l > 0, u > 0);

    b = 256;                            /* _Bool is a test, not a truncation */
    printf("_Bool of 256 is %d\n", b);

    printf("signed -8 >> 1 = %d, unsigned 4294967288 >> 1 = %u\n",
           -8 >> 1, (unsigned)-8 >> 1);

    printf("'A' is %d, and 'a' - 'A' is %d\n", 'A', 'a' - 'A');

    return 0;
}
