char text[] = "Vafgehpgvba frgf jnag gb or serr!";

int wait = 1;

int main()
{
    int a = 2;
    while (wait)
        ;

    int i = 0;
    while (text[i]) {
        char lower = text[i] | 32;
        if (lower >= 'a' && lower <= 'm')
            text[i] += 13;
        else if (lower > 'm' && lower <= 'z')
            text[i] -= 13;
        i++;
    }


done:
    while (!wait)
        ;
}
