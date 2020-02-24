CC=gcc
CFLAGS=-Wall -framework CoreFoundation -framework IOKit -I/usr/local/include/lua/ -llua

SYS := $(shell $(CC) -dumpmachine)

ifeq (, $(findstring darwin, $(SYS)))
$(error This program is for the Darwin platform only)
endif

all:
	$(CC) $(CFLAGS) -o samuel samuel.c

clean:
	/bin/rm -rf samuel
