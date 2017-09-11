FROM java:8-jdk-alpine

ENV GRINDER_VERSION 3.11

RUN apk --update --no-cache add \
	wget

RUN mkdir -p /opt/grinder

RUN cd /tmp && \
    wget 'http://downloads.sourceforge.net/project/grinder/The%20Grinder%203/'${GRINDER_VERSION}/grinder-${GRINDER_VERSION}-binary.zip && \
    ls -al /opt/grinder && \
    cd /opt/grinder && unzip /tmp/grinder-${GRINDER_VERSION}-binary.zip

ENV CLASSPATH /opt/grinder/grinder-${GRINDER_VERSION}/lib/grinder.jar

ENTRYPOINT ["java", "net.grinder.Grinder"]

