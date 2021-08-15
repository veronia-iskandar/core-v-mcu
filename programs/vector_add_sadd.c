#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    int errors = 0;
        uint8_t result;
    asm volatile (
        "li t1, 64 \n\t"
        "vsetvli t0, t1, e8, m1 \n\t"
        "vmv.v.i v1, 8 \n\t"
        "vmv.v.i v2, 7 \n\t"
        "vadd.vv v3, v1, v2 \n\t"
        "vmv.x.s %0, v3"
        : "=r" (result) 
    );
    if(result != 15)
        return(1);
    else
        return(0);

}
