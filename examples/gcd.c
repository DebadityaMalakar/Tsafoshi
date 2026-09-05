#include <stdio.h>

int gcd(int a, int b)
{
    while (b != 0) {
        int t = b;
        b = a % b;
        a = t;
    }
    return a;
}

int lcm(int a, int b)
{
    return a / gcd(a, b) * b;
}

int main(void)
{
    printf("gcd(1071, 462) = %d\n", gcd(1071, 462));
    printf("lcm(21, 6)     = %d\n", lcm(21, 6));
    return 0;
}
