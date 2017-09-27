FROM ubuntu:14.04

RUN apt-get update

ENV TESTDIR /loadgentests

# Make dir where we will put all our loadgen tools, data and dependencies
RUN mkdir ${TESTDIR}

# Java8
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys DA1A4A13543B466853BAF164EB9B1D8886F44E2A
RUN touch /etc/apt/sources.list.d/openjdk.list
RUN echo "deb http://ppa.launchpad.net/openjdk-r/ppa/ubuntu trusty main " >>/etc/apt/sources.list.d/openjdk.list
RUN echo "deb-src http://ppa.launchpad.net/openjdk-r/ppa/ubuntu trusty main" >>/etc/apt/sources.list.d/openjdk.list
RUN apt-get update
RUN apt-get -y install openjdk-8-jdk
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64

# C compiler, make, libssl, autoconf, etc
RUN apt-get -y install gcc libssl-dev autoconf erlang-dev erlang-nox nodejs npm unzip wget git python-pip python-dev python-zmq bc bsdmainutils jq

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

# Get and compile wrk 
RUN cd ${TESTDIR} && git clone 'https://github.com/wg/wrk'
RUN cd ${TESTDIR}/wrk && make
# Checkout specific commit that we know runtest.sh is compatible with
# RUN cd ${TESTDIR}/wrk && git checkout 50305ed1d89408c26067a970dcd5d9dbea19de9d && make

# Get and compile boom (latest snapshot)
RUN go get -u github.com/rakyll/boom
# runtest.sh works with this commit: https://github.com/rakyll/boom/commit/e99ce27f0878c1d266c8a3c266029038e78c5380

# Get and compile vegeta (latest snapshot)
RUN go get -u github.com/tsenart/vegeta
# runtest.sh works with this commit: https://github.com/tsenart/vegeta/commit/7cff4dc0ed44f0a8b9777caf050950eb67972f43

# Get and compile k6 (latest snapshop)
RUN go get -u github.com/loadimpact/k6

# Install Apachebench (>=2.3)
#RUN apt-get -y install apache2-utils
# How install specific version of ab?

# Get and compile Siege (latest snapshot)
RUN apt-get -y install siege
#RUN cd ${TESTDIR} && git clone 'https://github.com/JoeDog/siege.git'
#RUN cd ${TESTDIR}/siege && checkout xxxxxxxxxxx && autoconf && ./configure && make install

# Install Tsung (1.6.0)
RUN cd ${TESTDIR} && wget -O - 'http://tsung.erlang-projects.org/dist/tsung-1.6.0.tar.gz' |tar -xzf -
RUN cd ${TESTDIR}/tsung-1.6.0 && ./configure && make install

# Install Locust (>=0.7.5)
RUN pip install locustio
# RUN cd ${TESTDIR} && git clone 'https://github.com/locustio/locust'
# RUN cd ${TESTDIR}/locust && checkout 16140b0680cd7ab5d580aa2a1578a6349f988876 && python setup.py

# Gatling 2.2.2
RUN cd ${TESTDIR} && wget 'https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/2.2.2/gatling-charts-highcharts-bundle-2.2.2-bundle.zip' && \
  unzip gatling-charts-highcharts-bundle-2.2.2-bundle.zip && rm gatling-charts-highcharts-bundle-2.2.2-bundle.zip

# Jmeter 3.2
RUN cd ${TESTDIR} && wget -O - 'http://apache.mirrors.spacedump.net//jmeter/binaries/apache-jmeter-3.2.tgz' |tar -zxf -

# Grinder 3.11
RUN cd ${TESTDIR} && wget 'http://downloads.sourceforge.net/project/grinder/The%20Grinder%203/3.11/grinder-3.11-binary.zip' && \
  unzip grinder-3.11-binary.zip && rm grinder-3.11-binary.zip

# Artillery (>=1.5.0-12)
RUN npm install -g artillery
# git clone 'https://github.com/shoreditch-ops/artillery' && git checkout ... && ...

COPY runtests.sh ${TESTDIR}
RUN chmod 755 ${TESTDIR}/runtests.sh

RUN mkdir ${TESTDIR}/configs

COPY configs/tsung.xml ${TESTDIR}/configs
COPY configs/jmeter.xml ${TESTDIR}/configs
COPY configs/artillery.json ${TESTDIR}/configs
COPY configs/gatling.scala ${TESTDIR}/configs
COPY configs/grinder.py ${TESTDIR}/configs
COPY configs/grinder.properties ${TESTDIR}/configs
COPY configs/locust.py ${TESTDIR}/configs
COPY configs/wrk.lua ${TESTDIR}/configs
COPY configs/k6.js ${TESTDIR}/configs

CMD ${TESTDIR}/runtests.sh

