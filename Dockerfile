FROM ubuntu/14.04

RUN apt-get update

ENV testdir /loadgentests

# Make dir where we will put all our loadgen tools, data and dependencies
RUN mkdir ${testdir}

# C compiler, make, libssl
RUN apt-get install gcc libssl-dev

# install latest Golang to ${testdir}/go1.7, set GOHOME to ${testdir}/go
RUN mkdir ${testdir}/go1.7 ${testdir}/go
RUN wget -O - 'https://storage.googleapis.com/golang/go1.7.linux-amd64.tar.gz' |tar -C ${testdir}/go1.7 -xzf -
ENV GOROOT ${testdir}/go1.7/go
ENV PATH ${GOROOT}/bin:${PATH}
ENV GOHOME ${testdir}/go

# Create .gitconfig
COPY Gitconfig ${HOME}/.gitconfig

# Install JDK or JRE
# ...TODO...

# Get and compile wrk
RUN cd ${testdir} && git clone 'git@github.com:wg/wrk.git'
RUN cd ${testdir}/wrk && make

# Get and compile boom
RUN go get -u github.com/rakyll/boom

# Get and compile vegeta
RUN go get -u github.com/tsenart/vegeta

# Install Apachebench
RUN apt-get install apache2-utils





