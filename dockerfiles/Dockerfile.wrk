FROM alpine:latest

RUN apk add --update --no-cache \
	alpine-sdk \
	libgcc \
	linux-headers \
	perl

RUN cd /tmp                                                     && \
    git clone https://github.com/wg/wrk                         && \
    cd wrk                                                      && \
    sed -i 's/OPENSSL_OPTS\ \=\ no-shared/OPENSSL_OPTS\ \=\ no-async\ no-shared/' Makefile && \
    make                                                        && \
    mv ./wrk /bin                                     && \
    rm -rf /tmp/wrk                                             && \
    apk del --purge alpine-sdk perl

ENTRYPOINT [ "/bin/wrk" ]
CMD [ "-h" ]
