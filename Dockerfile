FROM ubuntu:14.04

RUN apt-get update

ENV TESTDIR /loadgentests

# Make dir where we will put all our loadgen tools, data and dependencies
RUN mkdir ${TESTDIR}

# C compiler, make, libssl, autoconf, etc
RUN apt-get -y install gcc libssl-dev autoconf erlang-dev erlang-nox nodejs npm openjdk-7-jre unzip wget git python-pip python-dev python-zmq bc bsdmainutils jq

# Update nodejs
RUN npm cache clean -f
RUN npm install -g n
RUN n stable

# Symlink to nodejs
RUN ln -s `which nodejs` /usr/bin/node

# install latest Golang to ${TESTDIR}/go1.7, set GOPATH to ${TESTDIR}/go
RUN mkdir ${TESTDIR}/go1.7 ${TESTDIR}/go
RUN wget -O - 'https://storage.googleapis.com/golang/go1.7.linux-amd64.tar.gz' |tar -C ${TESTDIR}/go1.7 -xzf -
ENV GOROOT ${TESTDIR}/go1.7/go
ENV GOPATH ${TESTDIR}/go
ENV PATH ${GOPATH}/bin:${GOROOT}/bin:/usr/local/bin:${PATH}

# Create .gitconfig
COPY Gitconfig ${HOME}/.gitconfig

# Get and compile wrk (latest snapshot)
RUN cd ${TESTDIR} && git clone 'https://github.com/wg/wrk.git'
RUN cd ${TESTDIR}/wrk && make

# Get and compile boom (latest snapshot)
RUN go get -u github.com/rakyll/boom

# Get and compile vegeta (latest snapshot)
RUN go get -u github.com/tsenart/vegeta

# Install Apachebench (>=2.3)
RUN apt-get -y install apache2-utils

# Get and compile Siege (latest snapshot)
RUN apt-get -y install siege
#RUN cd ${TESTDIR} && git clone 'https://github.com/JoeDog/siege.git'
#RUN cd ${TESTDIR}/siege && autoconf && ./configure && make

# Install Tsung (1.6.0)
RUN cd ${TESTDIR} && wget -O - 'http://tsung.erlang-projects.org/dist/tsung-1.6.0.tar.gz' |tar -xzf -
RUN cd ${TESTDIR}/tsung-1.6.0 && ./configure && make install

# Install Locust (>=0.7.5)
RUN pip install locustio

# Gatling 2.2.2
RUN cd ${TESTDIR} && wget 'https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/2.2.2/gatling-charts-highcharts-bundle-2.2.2-bundle.zip' && \
  unzip gatling-charts-highcharts-bundle-2.2.2-bundle.zip && rm gatling-charts-highcharts-bundle-2.2.2-bundle.zip

# Jmeter 3.0
RUN cd ${TESTDIR} && wget -O - 'http://apache.mirrors.spacedump.net//jmeter/binaries/apache-jmeter-3.0.tgz' |tar -zxf -

# Grinder 3.11
RUN cd ${TESTDIR} && wget 'http://downloads.sourceforge.net/project/grinder/The%20Grinder%203/3.11/grinder-3.11-binary.zip' && \
  unzip grinder-3.11-binary.zip && rm grinder-3.11-binary.zip

# Artillery (>=1.5.0-12)
RUN npm install -g artillery

COPY runtests.sh ${TESTDIR}
RUN chmod 755 ${TESTDIR}/runtests.sh

RUN mkdir ${TESTDIR}/configs

COPY configs/tsung.xml ${TESTDIR}/configs
COPY configs/jmeter.xml ${TESTDIR}/configs
COPY configs/gatling.scala ${TESTDIR}/configs
COPY configs/grinder.py ${TESTDIR}/configs
COPY configs/grinder.properties ${TESTDIR}/configs
COPY configs/locust.py ${TESTDIR}/configs
COPY configs/wrk.lua ${TESTDIR}/configs

CMD ${TESTDIR}/runtests.sh

