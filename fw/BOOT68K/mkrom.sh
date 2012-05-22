#!/bin/sh
#  Output data in the format:
#	AAA:	romdata[15:0]=16'hDDDD;

hexdump -v -e '"        %04_ad:  romdata[15:0]=16^h"' -e '2/1 "%02X"' -e'";\n"' $*

