test: src.c subsrc/sub.o
	gcc -o src.o -c src.c
	gcc -o test src.o subsrc/sub.o

subsrc/sub.o:
	gcc -o subsrc/sub.o -c subsrc/sub.c

clean:
	rm -f subsrc/sub.o src.o test
