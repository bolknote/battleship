CC=gcc
CFLAGS=-Wall -framework CoreFoundation -framework IOKit -I/usr/local/include/lua/ -llua

all:
	$(CC) $(CFLAGS) -o samuel samuel.c

clean:
	/bin/rm -rf samuel
