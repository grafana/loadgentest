FROM golang:alpine

RUN apk --update --no-cache add \
	git

RUN go get -u github.com/loadimpact/k6

ENV PATH ${GOPATH}/bin:${PATH}

ENTRYPOINT [ "k6" ]
CMD [ "help" ]
