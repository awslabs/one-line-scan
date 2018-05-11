// In this file a buffer overflow is present

#include <stdio.h>
#include <string.h>

char *to_lower(char *orig)
{
	char lower[4];
	int i = 0;
	// original variant has a faulty implementation:
	//strcpy(orig, lower);
	// to produce something readable, lets actually copy the content to the string!
	strcpy(lower, orig);
	for ( ; i <= strlen(lower); ++i) {
		// this reads/writes out of bounds
		if (lower[i] >= 'A' && lower[i] <= 'Z') {
			// this overflows, as + is served first and 'Z' + 'a' is beyond 128
			lower[i] = lower[i] + 'a';
			lower[i] = lower[i] - 'A';
		}
	}
	// returning the pointer to a stack variable is not handled by CBMC yet
	// however, gcc already complains with a warning, so we do not use this return here
	// return &lower[0];
	return orig;
}


int main(int argc, char **argv )
{
	char uninitialized_buffer [16];

	if (argc < 2 ) return 0;

	char *text = argv[1];
	if (argc > 1 && argc % 2) {
		printf("use uninit buffer\n");
		text = uninitialized_buffer;
	}

	char *lower = to_lower( text );
	printf( "sequence %d: %s\n", 0, text );
	printf( "sequence %d: %s\n", 1, lower );

	return 0;
}
