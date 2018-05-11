// When being compiled with -Wextra -Werror, the comparison in the return
// statemant should trigger a compilation error

int main() { unsigned u = 0; int i = 3; return u < i; }
