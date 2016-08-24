FROM ubuntu:14.04

RUN apt-get update

ENV testdir /loadgentests

# Make dir where we will put all our loadgen tools, data and dependencies
RUN mkdir ${testdir}

# C compiler, make, libssl, autoconf
RUN apt-get -y install gcc libssl-dev autoconf erlang-dev erlang-nox nodejs npm openjdk-7-jre unzip wget git python-pip python-dev

# install latest Golang to ${testdir}/go1.7, set GOPATH to ${testdir}/go
RUN mkdir ${testdir}/go1.7 ${testdir}/go
RUN wget -O - 'https://storage.googleapis.com/golang/go1.7.linux-amd64.tar.gz' |tar -C ${testdir}/go1.7 -xzf -
ENV GOROOT ${testdir}/go1.7/go
ENV PATH ${GOROOT}/bin:${PATH}
ENV GOPATH ${testdir}/go

# Create .gitconfig
COPY Gitconfig ${HOME}/.gitconfig

# Get and compile wrk (latest snapshot)
RUN cd ${testdir} && git clone 'https://github.com/wg/wrk.git'
RUN cd ${testdir}/wrk && make

# Get and compile boom (latest snapshot)
RUN go get -u github.com/rakyll/boom

# Get and compile vegeta (latest snapshot)
RUN go get -u github.com/tsenart/vegeta

# Install Apachebench (>=2.3)
RUN apt-get -y install apache2-utils

# Get and compile Siege (latest snapshot)
RUN apt-get -y install siege
#RUN cd ${testdir} && git clone 'https://github.com/JoeDog/siege.git'
#RUN cd ${testdir}/siege && autoconf && ./configure && make

# Install Tsung (>=1.6.0)
RUN apt-get -y install tsung
#RUN cd ${testdir} && wget -O - 'http://tsung.erlang-projects.org/dist/tsung-1.6.0.tar.gz' |tar -xzf -

# Install Locust (>=0.7.5)
RUN pip install locustio

# Gatling 2.2.2
RUN cd ${testdir} && wget 'https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/2.2.2/gatling-charts-highcharts-bundle-2.2.2-bundle.zip' && \
  unzip gatling-charts-highcharts-bundle-2.2.2-bundle.zip && rm gatling-charts-highcharts-bundle-2.2.2-bundle.zip

# Jmeter 3.0
RUN cd ${testdir} && wget -O - 'http://apache.mirrors.spacedump.net//jmeter/binaries/apache-jmeter-3.0.tgz' |tar -zxf -

# Grinder 3.11
RUN cd ${testdir} && wget 'http://downloads.sourceforge.net/project/grinder/The%20Grinder%203/3.11/grinder-3.11-binary.zip' && \
  unzip grinder-3.11-binary.zip && rm grinder-3.11-binary.zip

# Artillery (>=1.5.0-12)
RUN npm install -g artillery





