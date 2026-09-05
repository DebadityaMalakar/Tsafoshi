#include <stdio.h>

int factorial(int n)
{
    if (n <= 1) {
        return 1;
    }
    return n * factorial(n - 1);
}

int main(void)
{
    for (int i = 1; i <= 10; i = i + 1) {
        printf("%2d! = %d\n", i, factorial(i));
    }
    return 0;
}
