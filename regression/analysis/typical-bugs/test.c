// In this file a buffer overflow is present, that can be triggered when adding
// a string to the command line that contains more than 128 characters
// Furthermore, a pointer to a stack variable is returned in a function.

#include <stdio.h>
#include <string.h>

char *to_lower(char *orig)
{
	char lower[128];
	int i = 0;
	// original variant has a faulty implementation:
	//strcpy(orig, lower);
	// to produce something readable, lets actually copy the content to the string!
	strcpy(lower, orig);
	for ( ; i <= strlen(lower); ++i) {
		if (lower[i] >= 'A' && lower[i] <= 'Z') {
			lower[i] = lower[i] - 'A' + 'a';
		}
	}
	return &lower[0];
}


int main(int argc, char **argv )
{
	int i = 0;
	// make sure the loop is not called too often
	int max = argc > 3 ? 3 : argc;
	for ( ; i + 1 < argc; ++ i )
	{
		char *lower = to_lower( argv[i+1] );
		printf( "sequence %d: %s\n", i, lower );
	}
	return 0;
}
