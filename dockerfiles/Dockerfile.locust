FROM locustio/locust:0.13.1

USER root
RUN apk add --no-cache bash

RUN mkdir /bench
ADD ./runlocust.sh /bench/runlocust.sh
RUN chmod +x /bench/runlocust.sh

USER locust
CMD /bin/sh -c '/bench/runlocust.sh'