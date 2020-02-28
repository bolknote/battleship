CC=gcc
CFLAGS=-Wall -framework CoreFoundation -framework IOKit \
	-framework ApplicationServices \
	$(shell pkg-config --cflags lua) -llua

SYS := $(shell $(CC) -dumpmachine)

ifeq (, $(findstring darwin, $(SYS)))
$(error This program for the Darwin platform only)
endif

all :
	$(shell \
		printf '#define PROGRAM "%s"' \
		`hexdump -ve '1/1 "x%.2x"' battleship.lua | sed 's/x/\\\\x/g'` \
		> battleship.h \
	)

	$(CC) $(CFLAGS) -o battleship battleship.c


debug :
	$(shell echo > battleship.h)
	$(CC) $(CFLAGS) -o battleship battleship.c


clean :
	-rm -f battleship battleship.h
