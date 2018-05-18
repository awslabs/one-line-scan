// In this file a buffer overflow is present, that can be triggered when calling
// the binary and do not begin the input to the program with a number. When the
// number is too high, or the input is too long, invalid memory accesses can
// happen as well.

#include <stdio.h>
#include <string.h>
#include <assert.h>

int main(int argc, char **argv )
{
  int i = 0, index = -1, number = 0;
  char buffer [16];
  int elements = scanf("%s", buffer);

  if ( buffer[0] == 'A' ) index = -256;

  while( buffer[i] >= '0' && buffer[i] <= '9' )
  {
    number = number * 10 + (buffer[i] - '0');
    index = i;
    ++i;
  }

  printf("number: %d\n", number);
  printf("last digit: %c at %d \n", buffer[index], index);

  assert( (index < -100 || index >= 0) && "wonder whether we can ever get here after the buffer access above" );

  if (elements % 8 == 0 ) {
    buffer[elements] = 'A';
    printf("new buffer: %s\n", buffer);
  }

  return 0;
}
