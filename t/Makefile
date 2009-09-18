all: conf
test: test.conf
	prove -I.. .
conf: test.conf
test.conf: test.conf.tt *.t mkconf.pl
	./mkconf.pl --input $< --output $@
clean:
	rm -f test.conf
.PHONY: conf clean test
