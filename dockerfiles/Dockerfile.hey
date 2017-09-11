FROM golang:alpine

RUN apk --update --no-cache add \
	git

RUN go get -u github.com/rakyll/hey

ENTRYPOINT [ "hey" ]
CMD [ "-h" ]
