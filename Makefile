CC=gcc
CFLAGS=-Wall -framework CoreFoundation -framework IOKit $(shell pkg-config --cflags lua) -llua

SYS := $(shell $(CC) -dumpmachine)

ifeq (, $(findstring darwin, $(SYS)))
$(error This program is for the Darwin platform only)
endif

all:
	$(CC) $(CFLAGS) -o battleship battleship.c

clean:
	/bin/rm -rf battleship
