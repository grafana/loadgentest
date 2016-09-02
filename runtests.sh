#!/bin/bash

# Try to guess TESTDIR if it is not set
[ -z $TESTDIR ] && export TESTDIR=/loadgentests

# Check that we have some needed tools
checkfor() {
  which $1 >/dev/null
  if [ $? -ne 0 ]; then
    echo "Error: failed to find \"${1}\" (PATH=$PATH)"
    exit 1
  fi
}
checkfor which
checkfor cp
checkfor mv
checkfor rm
checkfor bc
checkfor tee
checkfor awk
checkfor sed
checkfor cut
checkfor grep
checkfor expr
checkfor echo
checkfor tail
checkfor egrep
checkfor mkdir
checkfor column

export TARGETURL=""
export CONCURRENT=20
export REQUESTS=1000
export DURATION=10

# replace fname str replace-str
replace() {
  FNAME=$1
  STR=$2
  REPLACE=$3
  awk -v rep="${REPLACE}" '{gsub("'${STR}'", rep);print $0}' ${FNAME} >/tmp/_replace.tmp
  mv -f /tmp/_replace.tmp ${FNAME}
}

# replace_all $source_cfg $target_cfg
replace_all() {
  SRC=$1
  DEST=$2
  cp -f $SRC $DEST
  REQS_PER_VU=`expr ${REQUESTS} \/ ${CONCURRENT}`
  TARGETHOST=`echo ${TARGETURL} |sed 's/https:\/\///' |sed 's/http:\/\///' |cut -d\/ -f1`
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
  ab -k -t ${CONCURRENT} -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  export APACHEBENCH_REQUESTS=`grep '^Complete\ requests:' ${RESULTS}/stdout.log |awk '{print $3}'`
  export APACHEBENCH_RPS=`grep '^Requests\ per\ second:' ${RESULTS}/stdout.log |awk '{print $4}'`
  export APACHEBENCH_RTT=`grep '^Time\ per\ request:' ${RESULTS}/stdout.log |grep '(mean)' |awk '{print $4}'`
  echo "apachebench_static: requests=${APACHEBENCH_REQUESTS} rps=${APACHEBENCH_RPS} rtt_avg=${APACHEBENCH_RTT}"
  echo "apachebench_static: done"
  sleep 3
}
boom_static() {
  echo ""
  echo "boom_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/boom/static
  mkdir -p ${RESULTS}
  echo "boom_static: Executing boom -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} ... "
  boom -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  export BOOM_RPS=`grep -A 5 '^Summary:' ${RESULTS}/stdout.log |grep 'Requests/sec:' |awk '{print $2}'`
  export BOOM_RTT=`grep -A 5 '^Summary:' ${RESULTS}/stdout.log |grep 'Average:' |awk '{print $2}'`
  BOOM_DURATION=`grep -A 5 '^Summary:' ${RESULTS}/stdout.log |grep 'Total:' |awk '{print $2}'`
  export BOOM_REQUESTS=`echo "${BOOM_DURATION}*${BOOM_RPS}" |bc |awk -F\. '{print $1}'`
  # Note: we *calculate* # of requests, which may result in small errors due to floating point precision issues.
  # TODO: extract # of requests from boom output instead.
  echo "boom_static: requests=${BOOM_REQUESTS} rps=${BOOM_RPS} rtt_avg=${BOOM_RTT}"
  echo "boom_static: done"
  sleep 3
}
wrk_static() {
  echo ""
  echo "wrk_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/wrk/static
  mkdir -p ${RESULTS}
  # Note that we supply TARGETURL on the cmd line as wrk requires that, but the cmd line parameter will
  # not be used as our script decides what URL to load (which will of course be the same TARGETURL though)
  echo "wrk_static: Executing wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} ${TARGETURL} ... "
  ${TESTDIR}/wrk/wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  export WRK1_RPS=`grep -A 5 'Thread Stats' ${RESULTS}/stdout.log |grep '^Requests/sec:' |awk '{print $2}'`
  export WRK1_RTT=`grep -A 5 'Thread Stats' ${RESULTS}/stdout.log |grep 'Latency' |awk '{print $2}' |egrep -o '[0-9]*\.?[0-9]*'`
  export WRK1_REQUESTS=`grep -A 5 'Thread Stats' ${RESULTS}/stdout.log |grep ' requests in ' |awk '{print $1}'`
  echo "wrk_static: requests=${WRK1_REQUESTS} rps=${WRK1_RPS} rtt_avg=${WRK1_RTT}"
  echo "wrk_static: done"
  sleep 3
}
artillery_static() {
  echo ""
  echo "artillery_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/artillery/static
  REQS_PER_VU=`expr ${REQUESTS} \/ ${CONCURRENT}`
  mkdir -p ${RESULTS}
  echo "artillery_static: Executing artillery quick --count ${CONCURRENT} -n ${REQS_PER_VU} -o ${RESULTS}/artillery_report.json ${TARGETURL} ... "
  ARTILLERY_START=`date +%s`
  artillery quick --count ${CONCURRENT} -n ${REQS_PER_VU} -o ${RESULTS}/artillery_report.json ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  ARTILLERY_END=`date +%s`
  ARTILLERY_DURATION=`expr $ARTILLERY_END - $ARTILLERY_START`
  export ARTILLERY_REQUESTS=`grep -A 20 '^Complete report @' ${RESULTS}/stdout.log |grep 'Requests completed:' |awk '{print $3}'`
  export ARTILLERY_RPS=`grep -A 20 '^Complete report @' ${RESULTS}/stdout.log |grep 'RPS sent:' |awk '{print $3}'`
  #export ARTILLERY_RTTMED=`grep -A 20 '^Complete report @' stdout.log |grep -A 5 'Request latency:' |grep "median:" |awk '{print $2}'`
  # Artillery only reports median RTT, so we attempt to calculate the average here
  # TODO: Use the artillery_report.json logfile that contains individual transaction times, to calculate average RTT
  export ARTILLERY_RTT=`echo "1000/((${ARTILLERY_REQUESTS}/${CONCURRENT})/${ARTILLERY_DURATION})" |bc`
  echo "artillery_static: requests=${ARTILLERY_REQUESTS} rps=${ARTILLERY_RPS} rtt_avg=${ARTILLERY_RTT}"
  echo "artillery_static: done"
  sleep 3
}
vegeta_static() {
  echo ""
  echo "vegeta_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/vegeta/static
  # Vegeta only supports static request rates. You might want to change the REQUESTS parameter until you get the highest throughput w/o errors.
  RATE=`expr ${REQUESTS} \/ ${DURATION}`
  mkdir -p ${RESULTS}
  echo "vegeta_static: Executing echo \"GET ${TARGETURL}\" vegeta attack -rate=${RATE} -connections=${CONCURRENT} -duration=${DURATION}s ... "
  echo "GET ${TARGETURL}" |vegeta attack -rate=${RATE} -connections=${CONCURRENT} -duration=${DURATION}s |vegeta report > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  export VEGETA_REQUESTS=`grep '^Requests' ${RESULTS}/stdout.log |awk '{print $4}' |cut -d\, -f1 |awk '{print $1}'`
  export VEGETA_RPS=`grep '^Requests' ${RESULTS}/stdout.log |awk '{print $5}'`
  export VEGETA_RTT=`grep '^Latencies' ${RESULTS}/stdout.log |awk '{print $7}' |egrep -o '[0-9]*\.?[0-9]*'`
  echo "vegeta_static: requests=${VEGETA_REQUESTS} rps=${VEGETA_RPS} rtt_avg=${VEGETA_RTT}"
  echo "vegeta_static: done"
  sleep 3
}
siege_static() {
  echo ""
  echo "siege_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/siege/static
  mkdir -p ${RESULTS}
  echo "siege_static: Executing siege -b -t ${DURATION}S -q -c ${CONCURRENT} ${TARGETURL} ... "
  siege -b -t ${DURATION}S -q -c ${CONCURRENT} ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  # Doesnt seem possible to tell siege where to write its logfile
  mv -f /var/log/siege.log ${RESULTS}
  export SIEGE_REQUESTS=`grep '^Transactions:' ${RESULTS}/stderr.log |awk '{print $2}'`
  export SIEGE_RPS=`grep '^Transaction rate:' ${RESULTS}/stderr.log |awk '{print $3}'`
  SIEGE_RTT_SECS=`grep '^Response time:' ${RESULTS}/stderr.log |awk '{print $3}'`
  # Siege reports response time in seconds, with only 2 decimals of precision. In a benchmark it is not unlikely
  # you will see it report 0.00s response times, or response times that never changes. Given this lack of precision 
  # it may perhaps be better to calculate average response time, like we do for Artillery?
  export SIEGE_RTT=`echo "${SIEGE_RTT_SECS}*1000" |bc`
  echo "siege_static: requests=${SIEGE_REQUESTS} rps=${SIEGE_RPS} rtt_avg=${SIEGE_RTT}"
  echo "siege_static: done"
  sleep 3
}
tsung_static() {
  echo ""
  echo "tsung_static: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/tsung/static
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/tsung_${STARTTIME}.xml
  replace_all ${TESTDIR}/configs/tsung.xml ${CFG}
  echo "tsung_static: Executing tsung -l ${RESULTS} -f ${CFG} start ... "
  TSUNG_START=`date +%s`
  tsung -l ${RESULTS} -f ${CFG} start > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  TSUNG_END=`date +%s`
  TSUNG_DURATION=`expr $TSUNG_END - $TSUNG_START`
  TSUNG_LOGDIR=`grep '^Log directory is:' ${RESULTS}/stdout.log |awk '{print $4}'`
  export TSUNG_RTT=`grep '^stats: request ' ${TSUNG_LOGDIR}/tsung.log |tail -1 |awk '{print $8}'`
  export TSUNG_REQUESTS=`grep '^stats: request ' ${TSUNG_LOGDIR}/tsung.log |tail -1 |awk '{print $9}'`
  export TSUNG_RPS=`echo "${TSUNG_REQUESTS}/${TSUNG_DURATION}" |bc`
  echo "tsung_static: requests=${TSUNG_REQUESTS} rps=${TSUNG_RPS} rtt_avg=${TSUNG_RTT}"
  echo "tsung_static: done"
  sleep 3
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
  ${TESTDIR}/apache-jmeter-3.0/bin/jmeter -n -t ${CFG} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  export JMETER_REQUESTS=`grep '^summary ' ${RESULTS}/stdout.log |tail -1 |awk '{print $3}'`
  export JMETER_RPS=`grep '^summary ' ${RESULTS}/stdout.log |tail -1 |awk '{print $7}' |cut -d\/ -f1`
  export JMETER_RTT=`grep '^summary ' ${RESULTS}/stdout.log |tail -1 |awk '{print $9}'`
  echo "jmeter_static: requests=${JMETER_REQUESTS} rps=${JMETER_RPS} rtt_avg=${JMETER_RTT}"
  echo "jmeter_static: done"
  sleep 3
}

# Scripting tests
locust_scripting() {
  echo ""
  echo "locust_scripting: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/locust/scripting
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/locust_${STARTTIME}.py
  # TODO: we only support plain HTTP here also
  replace_all ${TESTDIR}/configs/locust.py ${CFG}
  TARGETHOST=`echo ${TARGETURL} |sed 's/https:\/\///' |sed 's/http:\/\///' |cut -d\/ -f1`
  echo "locust_scripting: Executing locust --host=\"http://${TARGETHOST}\" --locustfile=${CFG} --no-web --clients=${CONCURRENT} --hatch-rate=${CONCURRENT} --num-request=${REQUESTS} ... "
  locust --host="http://${TARGETHOST}" --locustfile=${CFG} --no-web --clients=${CONCURRENT} --hatch-rate=${CONCURRENT} --num-request=${REQUESTS} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  export LOCUST_REQUESTS=`grep -A 10 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep '^ Total' |awk '{print $2}'`
  export LOCUST_RPS=`grep -A 10 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep '^ Total' |awk '{print $4}'`
  export LOCUST_RTT=`grep -A 10 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep '^ GET' |head -1 |awk '{print $5}'`
  echo "locust_scripting: requests=${LOCUST_REQUESTS} rps=${LOCUST_RPS} rtt_avg=${LOCUST_RTT}"
  echo "locust_scripting: done"
  sleep 3
}
grinder_scripting() {
  echo ""
  echo "grinder_scripting: starting at "`date +%y%m%d-%H:%M:%S`
  export RESULTS=${TESTDIR}/results/${STARTTIME}/grinder/scripting
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
  java net.grinder.Grinder ${CFG2} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  # Grinder only logs durations for individual requests. I don't think there is any simple way of making it
  # output aggregated statistics to the console, so we have to first find out what our workers are called
  TMP=${RESULTS}/_metrics.`date +%s`
  for WORKER in `egrep 'INFO  agent: worker .* started' ${RESULTS}/stdout.log |awk '{print $6}'`
  do
    # Then we extract all the response time metrics from the logfiles
    awk 'NR>1{print $5}' ${RESULTS}/${WORKER}-data.log |sed 's/\,//' >>${TMP}
  done
  # How many requests did we see
  export GRINDER_REQUESTS=`wc -l ${TMP} |awk '{print $1}'`
  # Calculate RPS. We assume we ran for the exact DURATION.
  export GRINDER_RPS=`echo "${GRINDER_REQUESTS}/${DURATION}" |bc`
  # Calculate the average for all the response times. 
  export GRINDER_RTT=`awk 'BEGIN{num=0;tot=0}{num=num+1;tot=tot+$1}END{print tot/num}' ${TMP}`
  echo "grinder_scripting: requests=${GRINDER_REQUESTS} rps=${GRINDER_RPS} rtt_avg=${GRINDER_RTT}"
  echo "grinder_scripting: done"
  sleep 3
}
gatling_scripting() {
  echo ""
  echo "gatling_scripting: starting at "`date +%y%m%d-%H:%M:%S`
  RESULTS=${TESTDIR}/results/${STARTTIME}/gatling/scripting
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/gatling_${STARTTIME}.scala  
  replace_all ${TESTDIR}/configs/gatling.scala ${CFG}
  echo "gatling_scripting: Executing gatling ... "
  # TODO - fix Gatlings tricky config setup...  
  echo "gatling_scripting: done"
  sleep 3
}
wrk_scripting() {
  echo ""
  echo "wrk_scripting: starting at "`date +%y%m%d-%H:%M:%S`
  RESULTS=${TESTDIR}/results/${STARTTIME}/wrk/scripting
  mkdir -p ${RESULTS}
  CFG=${TESTDIR}/configs/wrk_${STARTTIME}.lua
  replace_all ${TESTDIR}/configs/wrk.lua ${CFG}
  echo "wrk_scripting: Executing wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} --script ${CFG} ${TARGETURL} ... "
  ${TESTDIR}/wrk/wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} --script ${CFG} ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  export WRK2_RPS=`grep -A 5 'Thread Stats' ${RESULTS}/stdout.log |grep '^Requests/sec:' |awk '{print $2}'`
  export WRK2_RTT=`grep -A 5 'Thread Stats' ${RESULTS}/stdout.log |grep 'Latency' |awk '{print $2}' |egrep -o '[0-9]*\.?[0-9]*'`
  export WRK2_REQUESTS=`grep -A 5 'Thread Stats' ${RESULTS}/stdout.log |grep ' requests in ' |awk '{print $1}'`
  echo "wrk_scripting: requests=${WRK2_REQUESTS} rps=${WRK2_RPS} rtt_avg=${WRK2_RTT}"
  echo "wrk_scripting: done"
  sleep 3
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
  echo ""
  echo "------------------------ Static URL test results -------------------------"
  ( echo "Apachebench   requests=${APACHEBENCH_REQUESTS} rps=${APACHEBENCH_RPS}  rtt_avg=${APACHEBENCH_RTT}"
    echo "Boom          requests=${BOOM_REQUESTS} rps=${BOOM_RPS}  rtt_avg=${BOOM_RTT}"
    echo "Wrk           requests=${WRK1_REQUESTS} rps=${WRK1_RPS}  rtt_avg=${WRK1_RTT}"
    echo "Artillery     requests=${ARTILLERY_REQUESTS} rps=${ARTILLERY_RPS}  rtt_avg=${ARTILLERY_RTT}"
    echo "Vegeta        requests=${VEGETA_REQUESTS} rps=${VEGETA_RPS}  rtt_avg=${VEGETA_RTT}"
    echo "Siege         requests=${SIEGE_REQUESTS} rps=${SIEGE_RPS}  rtt_avg=${SIEGE_RTT}"
    echo "Tsung         requests=${TSUNG_REQUESTS} rps=${TSUNG_RPS}  rtt_avg=${TSUNG_RTT}"
    echo "Jmeter        requests=${JMETER_REQUESTS} rps=${JMETER_RPS}  rtt_avg=${JMETER_RTT}" ) | column -t
  echo "--------------------------------------------------------------------------"
  echo ""
}

scriptingtests() {
  locust_scripting
  grinder_scripting
  #gatling_scripting
  wrk_scripting
  echo ""
  echo "------------------------ Scripting test results -------------------------"
  ( echo "Locust   requests=${LOCUST_REQUESTS} rps=${LOCUST_RPS}  rtt_avg=${LOCUST_RTT}"
    echo "Grinder  requests=${GRINDER_REQUESTS} rps=${GRINDER_RPS}  rtt_avg=${GRINDER_RTT}"
    echo "Wrk      requests=${WRK2_REQUESTS} rps=${WRK2_RPS}  rtt_avg=${WRK2_RTT}" ) | column -t
  echo "-------------------------------------------------------------------------"
  echo ""
}

clear
while [ 1 ]
do
  echo ""
  echo "################################################"
  echo "#  Load Impact load generator test suite V1.0  #"
  echo "################################################"
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
  # Record start time
  export STARTTIME=`date +%y%m%d-%H%M%S`
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
