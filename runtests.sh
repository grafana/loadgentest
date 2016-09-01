#!/bin/bash

# Try to guess TESTDIR if it is not set
[ -z $TESTDIR ] && export TESTDIR=/loadgentests

SED=/bin/sed
TEE=/usr/bin/tee
AWK=/usr/bin/awk
CLEAR=/usr/bin/clear

export TARGETURL=""
export CONCURRENT=20
export REQUESTS=1000
export DURATION=10

# replace fname str replace-str
replace() {
  FNAME=$1
  STR=$2
  REPLACE=$3
  ${AWK} -v rep="${REPLACE}" '{gsub("'${STR}'", rep);print $0}' ${FNAME} >/tmp/_replace.tmp
  mv -f /tmp/_replace.tmp ${FNAME}
}

# replace_all $source_cfg $target_cfg
replace_all() {
  SRC=$1
  DEST=$2
  cp -f $SRC $DEST
  REQS_PER_VU=`expr ${REQUESTS} \/ ${CONCURRENT}`
  TARGETHOST=`echo ${TARGETURL} |${SED} 's/https:\/\///' |${SED} 's/http:\/\///' |cut -d\/ -f1`
  TARGETPATH=/`echo ${TARGETURL} |awk -F\/ '{print $NF}'`
  RATE=`expr ${REQUESTS} \/ ${DURATION}`
  replace $DEST "REQS_PER_VU" "${REQS_PER_VU}"
  replace $DEST "CONCURRENT" "${CONCURRENT}"
  replace $DEST "DURATION" "${DURATION}"
  replace $DEST "RATE" "${RATE}"
  replace $DEST "TARGETHOST" "${TARGETHOST}"
  replace $DEST "TARGETPATH" "${TARGETPATH}"
  replace $DEST "TARGETURL" "${TARGETURL}"
  replace $DEST "LOGDIR" "${RESULTS}"
}

# Static-URL tests
apachebench_static() {
  echo ""
  echo "apachebench_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/apachebench/static
  mkdir -p ${RESULTS}
  echo "apachebench_static: Executing ab -k -t ${CONCURRENT} -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} ... "
  ab -k -t ${CONCURRENT} -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} > >(${TEE} ${RESULTS}/stdout.log) 2> >(${TEE} ${RESULTS}/stderr.log >&2)
  echo "apachebench_static: done"
}
boom_static() {
  echo ""
  echo "boom_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/boom/static
  mkdir -p ${RESULTS}
  echo "boom_static: Executing boom -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} ... "
  boom -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} > >(${TEE} ${RESULTS}/stdout.log) 2> >(${TEE} ${RESULTS}/stderr.log >&2)
  echo "boom_static: done"
}
wrk_static() {
  echo ""
  echo "wrk_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/wrk/static
  mkdir -p ${RESULTS}
  echo "wrk_static: Executing wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} ${TARGETURL} ... "
  ${TESTDIR}/wrk/wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} ${TARGETURL} > >(${TEE} ${RESULTS}/stdout.log) 2> >(${TEE} ${RESULTS}/stderr.log >&2)
  echo "wrk_static: done"
}
artillery_static() {
  echo ""
  echo "artillery_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/artillery/static
  REQS_PER_VU=`expr ${REQUESTS} \/ ${CONCURRENT}`
  mkdir -p ${RESULTS}
  echo "artillery_static: Executing artillery quick --count ${CONCURRENT} -n ${REQS_PER_VU} ${TARGETURL} ... "
  artillery quick --count ${CONCURRENT} -n ${REQS_PER_VU} ${TARGETURL} > >(${TEE} ${RESULTS}/stdout.log) 2> >(${TEE} ${RESULTS}/stderr.log >&2)
  echo "artillery_static: done"
}
vegeta_static() {
  echo ""
  echo "vegeta_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/vegeta/static
  # Vegeta only supports static request rates. You might want to change the REQUESTS parameter until you get the highest throughput w/o errors.
  RATE=`expr ${REQUESTS} \/ ${DURATION}`
  mkdir -p ${RESULTS}
  echo "vegeta_static: Executing echo \"GET ${TARGETURL}\" vegeta attack -rate=${RATE} -connections=${CONCURRENT} -duration=${DURATION}s ... "
  echo "GET ${TARGETURL}" |vegeta attack -rate=${RATE} -connections=${CONCURRENT} -duration=${DURATION}s |vegeta report > >(${TEE} ${RESULTS}/stdout.log) 2> >(${TEE} ${RESULTS}/stderr.log >&2)
  echo "vegeta_static: done"
}
siege_static() {
  echo ""
  echo "siege_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/siege/static
  mkdir -p ${RESULTS}
  echo "siege_static: Executing siege -b -t ${DURATION}S -q -c ${CONCURRENT} ${TARGETURL} ... "
  siege -b -t ${DURATION}S -q -c ${CONCURRENT} ${TARGETURL} > >(${TEE} ${RESULTS}/stdout.log) 2> >(${TEE} ${RESULTS}/stderr.log >&2)
  # Siege has pretty crappy logging options. Doesnt seem possible to tell it where to write its logfile
  mv -f /var/log/siege.log ${RESULTS}
  echo "siege_static: done"
}
tsung_static() {
  echo ""
  echo "tsung_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/tsung/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/tsung_${STARTTIME}.xml
  replace_all ${TESTDIR}/configs/tsung.xml ${CFG}
  echo "tsung_static: Executing tsung -l ${RESULTS} -f ${CFG} start ... "
  tsung -l ${RESULTS} -f ${CFG} start > >(${TEE} ${RESULTS}/stdout.log) 2> >(${TEE} ${RESULTS}/stderr.log >&2)
  echo "tsung_static: done"
}
jmeter_static() {
  echo ""
  echo "jmeter_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/jmeter/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/jmeter_${STARTTIME}.xml
  # TODO: support for protocols other than plain HTTP... we dont specify protocol in the test plan ATM
  replace_all ${TESTDIR}/configs/jmeter.xml ${CFG}
  echo "jmeter_static: Executing jmeter -n -t ${CFG} ... "
  ${TESTDIR}/apache-jmeter-3.0/bin/jmeter -n -t ${CFG} > >(${TEE} ${RESULTS}/stdout.log) 2> >(${TEE} ${RESULTS}/stderr.log >&2)
  echo "jmeter_static: done"
}

# Scripting tests
locust_scripting() {
  echo ""
  echo "locust_scripting: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/locust/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/locust_${STARTTIME}.py
  # TODO: we only support plain HTTP here also
  replace_all ${TESTDIR}/configs/locust.py ${CFG}
  TARGETHOST=`echo ${TARGETURL} |${SED} 's/https:\/\///' |${SED} 's/http:\/\///' |cut -d\/ -f1`
  echo "locust_scripting: Executing locust --host=\"http://${TARGETHOST}\" --locustfile=${CFG} --no-web --clients=${CONCURRENT} --hatch-rate=${CONCURRENT} --num-request=${REQUESTS} ... "
  locust --host="http://${TARGETHOST}" --locustfile=${CFG} --no-web --clients=${CONCURRENT} --hatch-rate=${CONCURRENT} --num-request=${REQUESTS} > >(${TEE} ${RESULTS}/stdout.log) 2> >(${TEE} ${RESULTS}/stderr.log >&2)
  echo "locust_scripting: done"
}
grinder_scripting() {
  echo ""
  echo "grinder_scripting: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/grinder/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/grinder_${STARTTIME}.py
  replace_all ${TESTDIR}/configs/grinder.py ${CFG}
  CFG2=${TESTDIR}/configs/grinder_${STARTTIME}.properties
  TMPCFG2=/tmp/grinder_${STARTTIME}.properties
  cp ${TESTDIR}/configs/grinder.properties $TMPCFG2
  # Grinder specifies thread duration in ms
  GRINDER_DURATION=`expr ${DURATION} \* 1000`
  replace $TMPCFG2 "DURATION" "${GRINDER_DURATION}"
  replace $TMPCFG2 "SCRIPT" "${CFG}"
  replace_all $TMPCFG2 $CFG2
  rm $TMPCFG2
  cd ${TESTDIR}/configs
  export CLASSPATH=/loadgentests/grinder-3.11/lib/grinder.jar
  echo "grinder_scripting: Executing java net.grinder.Grinder ${CFG2} ... "
  java net.grinder.Grinder ${CFG2} > >(${TEE} ${RESULTS}/stdout.log) 2> >(${TEE} ${RESULTS}/stderr.log >&2)
  echo "grinder_scripting: done"
}
gatling_scripting() {
  echo ""
  echo "gatling_scripting: starting at "`date +%y%m%d-%H:%M:%S`
  RESULTS=${TESTDIR}/results/${STARTTIME}/gatling/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/gatling_${STARTTIME}.scala  
  replace_all ${TESTDIR}/configs/gatling.scala ${CFG}
  echo "gatling_scripting: Executing gatling ... "
  # TODO - fix Gatlings tricky config setup...  
  echo "gatling_scripting: done"
}
wrk_scripting() {
  echo ""
  echo "wrk_scripting: starting at "`date +%y%m%d-%H:%M:%S`
  RESULTS=${TESTDIR}/results/${STARTTIME}/wrk/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/wrk_${STARTTIME}.lua
  replace_all ${TESTDIR}/configs/wrk.lua ${CFG}
  echo "wrk_scripting: Executing wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} --script ${CFG} ${TARGETURL} ... "
  ${TESTDIR}/wrk/wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} --script ${CFG} ${TARGETURL} > >(${TEE} ${RESULTS}/stdout.log) 2> >(${TEE} ${RESULTS}/stderr.log >&2)
  echo "wrk_scripting: done"
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

while true
do
  # Record start time
  export STARTTIME=`date +%y%m%d-%H%M%S`
  ${CLEAR}
  echo "Load Impact load generator test suite V1.0"
  echo ""
  echo "1. Choose target URL (current: ${TARGETURL})"
  echo "2. Set concurrent requests/VUs (current: ${CONCURRENT})"
  echo "3. Set total number of requests (current: ${REQUESTS})"
  echo "4. Set test duration (current: ${DURATION})"
  echo ""
  echo "5. Run all tests"
  echo "6. Run all static-URL tests"
  echo "7. Run all scripting tests"
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
  echo "X. Escape to bash"
  echo ""
  echo -n "Select (1-4,a-h,A-D,X): "
  read ans
  case $ans in
    1)
      echo -n "Enter target URL: "
      read ans
      export TARGETURL=$ans
      ;;
    2)
      echo -n "Enter # of concurrent requests: "
      read ans
      export CONCURRENT=$ans
      ;;
    3)
      echo -n "Enter total # of requests: "
      read ans
      export REQUESTS=$ans
      ;;
    4)
      echo -n "Enter test duration: "
      read ans
      export DURATION=$ans
      ;;

    5)
      [ "${TARGETURL}x" != "x" ] && staticurltests
      [ "${TARGETURL}x" != "x" ] && scriptingtests
      ;;
    6)
      [ "${TARGETURL}x" != "x" ] && staticurltests
      ;;
    7)
      [ "${TARGETURL}x" != "x" ] && scriptingtests
      ;;
    a)
      [ "${TARGETURL}x" != "x" ] && apachebench_static
      ;;
    b)
      [ "${TARGETURL}x" != "x" ] && wrk_static
      ;;
    c)
      [ "${TARGETURL}x" != "x" ] && boom_static
      ;;
    d)
      [ "${TARGETURL}x" != "x" ] && artillery_static
      ;;
    e)
      [ "${TARGETURL}x" != "x" ] && vegeta_static
      ;;
    f)
      [ "${TARGETURL}x" != "x" ] && siege_static
      ;;
    g)
      [ "${TARGETURL}x" != "x" ] && tsung_static
      ;;
    h)
      [ "${TARGETURL}x" != "x" ] && jmeter_static
      ;;
    A)
      [ "${TARGETURL}x" != "x" ] && locust_scripting
      ;;
    B)
      [ "${TARGETURL}x" != "x" ] && grinder_scripting
      ;;
    C)
      [ "${TARGETURL}x" != "x" ] && gatling_scripting
      ;;
    D)
      [ "${TARGETURL}x" != "x" ] && wrk_scripting
      ;;
    X)
      /bin/bash
      ;;
  esac
done
