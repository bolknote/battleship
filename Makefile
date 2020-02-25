CC=gcc
CFLAGS=-Wall -framework CoreFoundation -framework IOKit $(shell pkg-config --cflags lua) -llua

SYS := $(shell $(CC) -dumpmachine)

ifeq (, $(findstring darwin, $(SYS)))
$(error This program is for the Darwin platform only)
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
	-rm battleship battleship.h
