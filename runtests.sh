#!/bin/bash

export TARGET="none"

# Try to guess TESTDIR if it is not set
[ -z $TESTDIR ] && export TESTDIR=/loadgentests

# Record start time
export STARTTIME=`date +%y%m%d-%H%M%S`

# Static-URL tests
apachebench_static() {
  RESULTS=${TESTDIR}/results/${STARTTIME}/apachebench/static
  mkdir -p ${RESULTS}
  ab -k -t 10 -n 1000000 -c 20 ${TARGET} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
}
boom_static() {
  RESULTS=${TESTDIR}/results/${STARTTIME}/boom/static
  mkdir -p ${RESULTS}
  boom -n 1000000 -c 20 ${TARGET} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
}
wrk_static() {
  RESULTS=${TESTDIR}/results/${STARTTIME}/wrk/static
  mkdir -p ${RESULTS}
  ${TESTDIR}/wrk/wrk -c 20 -t 20 -d 30 ${TARGET} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
}
artillery_static() {
  RESULTS=${TESTDIR}/results/${STARTTIME}/artillery/static
  mkdir -p ${RESULTS}
  artillery quick --count 100 -n 1000 ${TARGET} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
}
vegeta_static() {
  RESULTS=${TESTDIR}/results/${STARTTIME}/vegeta/static
  mkdir -p ${RESULTS}
  # Vegeta only supports static request rates. You might want to change the -rate parameter until you get max throughput without errors
  echo "GET ${TARGET}" |vegeta attack -rate=13000 -connections=20 -duration=30s |vegeta report > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
}
siege_static() {
  RESULTS=${TESTDIR}/results/${STARTTIME}/siege/static
  mkdir -p ${RESULTS}
  siege -b -t 30S -q -c 20 > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
}
tsung_static() {
  RESULTS=${TESTDIR}/results/${STARTTIME}/tsung/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/tsung_${STARTTIME}.xml
  sed 's/TARGETURL/'${TARGETURL}'/' ${TESTDIR}/configs/tsung.xml >${CFG}
  tsung -n -f ${CFG} start > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
}
jmeter_static() {
  RESULTS=${TESTDIR}/results/${STARTTIME}/jmeter/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/jmeter_${STARTTIME}.xml
  # TODO: support for protocols other than plain HTTP... we dont specify protocol in the test plan ATM
  HOST=`echo ${TARGETURL} |sed 's/https:\/\///' |sed 's/http:\/\///' |cut -d\/ -f1`
  PATH=/`echo ${TARGETURL} |awk -F\/ '{print $NF}'`
  sed 's/TARGETHOST/'${HOST}'/' ${TESTDIR}/configs/jmeter.xml |sed 's/TARGETPATH/'${PATH}'/' >${CFG}
  jmeter -n -t ${CFG} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
}
# Scripting tests
locust_scripting() {
  RESULTS=${TESTDIR}/results/${STARTTIME}/locust/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/locust_${STARTTIME}.py
  # TODO: we only support plain HTTP here also
  HOST=`echo ${TARGETURL} |sed 's/https:\/\///' |sed 's/http:\/\///' |cut -d\/ -f1`
  PATH=/`echo ${TARGETURL} |awk -F\/ '{print $NF}'`
  sed 's/TARGETPATH/'${PATH}'/' ${TESTDIR}/configs/locust.py >${CFG}
  locust --host="http://${HOST}" --locustfile=${CFG} --no-web --clients=20 --hatch-rate=20 --num-requests=100000 > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
}
grinder_scripting() {
  RESULTS=${TESTDIR}/results/${STARTTIME}/grinder/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/grinder_${STARTTIME}.py
  CFG2=${TESTDIR}/configs/grinder_${STARTTIME}.properties
  sed 's/TARGETURL/'${TARGETURL}'/' ${TESTDIR}/configs/grinder.py >${CFG}
  sed 's/LOGDIR/'${RESULTS}'/' ${TESTDIR}/configs/grinder.properties |sed 's/SCRIPT/grinder_'${STARTTIME}'.properties' >${CFG2}
  cd ${TESTDIR}/configs
  java net.grinder.Grinder ${CFG2} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
}
gatling_scripting() {
  RESULTS=${TESTDIR}/results/${STARTTIME}/gatling/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/gatling_${STARTTIME}.scala  
  HOST=`echo ${TARGETURL} |sed 's/https:\/\///' |sed 's/http:\/\///' |cut -d\/ -f1`
  PATH=/`echo ${TARGETURL} |awk -F\/ '{print $NF}'`
  sed 's/TARGETHOST/'${HOST}'/' ${TESTDIR}/configs/gatling.scala |sed 's/TARGETPATH/'${PATH}'/' >${CFG}
  # TODO - fix Gatlings tricky config setup...  
}
wrk_scripting() {
  RESULTS=${TESTDIR}/results/${STARTTIME}/wrk/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/wrk_${STARTTIME}.lua
  sed 's/TARGETURL/'${TARGETURL}'/' ${TESTDIR}/configs/wrk.lua >${CFG}
  ${TESTDIR}/wrk/wrk -c20 -t20 -d30 --script ${CFG} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
}

staticurltests() {
  apachebench_static
  boom_static
  wrk_static
  artillery_static
  vegeta_static
  siege_static
  tsung_static
  jmeter_static
}

scriptingtests() {
  locust_scripting
  grinder_scripting
  #gatling_scripting
  wrk_scripting
}

while true do
  clear
  echo "Load Impact load generator test suite V1.0"
  echo ""
  echo "1. Choose target URL (current: ${TARGET})"
  echo ""
  echo "2. Run all tests"
  echo "3. Run all static-URL tests"
  echo "4. Run all scripting tests"
  echo ""
  echo "a. Run Apachebench static-URL test"
  echo "b. Run Wrk static-URL test"
  echo "c. Run Boom static-URL test"
  echo "d. Run Artillery static-URL test"
  echo "e. Run Vegeta static-URL test"
  echo "f. Run Siege static-URL test"
  echo "g. Run Tsung static-URL test"
  echo "h. Run Jmeter static-URL test"
  echo ""
  echo "A. Run Locust scripting test"
  echo "B. Run Grinder scripting test"
  echo "C. Run Gatling scripting test"
  echo "D. Run Wrk scripting test"
  echo ""
  echo -n "Select (1-4,a-h,A-D): "
  read ans
  case $ans in
    1)
      echo "Enter target URL: "
      read ans
      export TARGET=$ans
      ;;
    2)
      staticurltests
      scriptingtests
      ;;
    3)
      staticurltests
      ;;
    4)
      scriptingtests
      ;;
    a)
      apachebench_static
      ;;
    b)
      wrk_static
      ;;
    c)
      boom_static
      ;;
    d)
      artillery_static
      ;;
    e)
      vegeta_static
      ;;
    f)
      siege_static
      ;;
    g)
      tsung_static
      ;;
    h)
      jmeter_static
      ;;
    A)
      locust_scripting
      ;;
    B)
      grinder_scripting
      ;;
    C)
      gatling_scripting
      ;;
    D)
      wrk_scripting
      ;;
  esac
done
