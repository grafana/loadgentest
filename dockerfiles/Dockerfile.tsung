FROM erlang:alpine

RUN apk add --update --no-cache \
	autoconf \
	make \
	perl \
	bash \
	git

RUN cd /tmp                                           && \
    git clone https://github.com/processone/tsung         && \
    cd tsung                                          && \
    ./configure                                       && \
    make install                                      

ENTRYPOINT ["tsung"]
