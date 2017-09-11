FROM golang:alpine

RUN apk --update --no-cache add \
	git

RUN go get -u github.com/tsenart/vegeta

ENTRYPOINT [ "vegeta" ]
CMD [ "-h" ]
