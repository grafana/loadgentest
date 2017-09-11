FROM alpine:latest

RUN apk --update --no-cache add \
	python \
        python-dev \
        build-base \
        py-pip

RUN pip install locustio pyzmq

ENTRYPOINT ["/usr/bin/locust"]
CMD ["--help"]
