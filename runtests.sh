#!/bin/bash

#
# This script runs all the various load testing tools, and attempts to extract
# useful statistics from whatever output is generated.
#
# TODO: Many, many things, but here are a couple of wanted fixes
#
# - Refactor this script and make it more consistent. E.g. how to count # of
#   lines in a file is sometimes using `wc` + `awk` and sometimes just `awk`
#   (we should probably skip using `wc` at all, because its output sucks).
#   Another example: when invoking bc we sometimes use -l (mathlib) and 
#   sometimes not, pretty randomly.
#
# - Refactor this script and use more modern bash syntax, e.g. $(cmd) instead of `cmd`
#
# - Decide whether only 200-responses should be used to calculate RPS numbers
#   and implement the same method for all tests (currently, some do it, some don't)
#
# - Big one: Collect latency statistics by sniffing network traffic, rather than accept
#   tool output. Would both give us a more objective view of things, and also
#   make it possible to collect all stats for all tools.
#
# - Fix: network delay cannot be enabled again after setting it to 0 (zero)
#
# - Make Github issues of these comments instead!
#
#

# Try to guess TESTDIR if it is not set
[ -z $TESTDIR ] && export TESTDIR=`pwd`

# Check that we have some needed tools
checkfor() {
  which $1 >/dev/null
  FOUND=$?
  if [ $FOUND -ne 0 ]; then
    echo "WARNING: Failed to find \"${1}\" (PATH=$PATH)"
  fi
  return $FOUND
}
checkfor which || exit 1
checkfor cp || exit 1
checkfor mv || exit 1
checkfor rm || exit 1
checkfor bc || exit 1
checkfor jq || exit 1
checkfor wc || exit 1
checkfor tc || export NO_TC=1
checkfor cat || exit 1
checkfor tee || exit 1
checkfor awk || exit 1
checkfor sed || exit 1
checkfor cut || exit 1
checkfor grep || exit 1
checkfor expr || exit 1
checkfor echo || exit 1
checkfor tail || exit 1
checkfor ping || exit 1
checkfor egrep || exit 1
checkfor mkdir || exit 1
checkfor uname || exit 1
checkfor column || exit 1
checkfor docker || exit 1

# Default settings
if [ -z $TARGETURL ]; then
  export TARGETURL=""
fi
if [ -z $CONCURRENT ]; then
  export CONCURRENT=20
fi
if [ -z $REQUESTS ]; then
  export REQUESTS=1000
fi
if [ -z $DURATION ]; then
  export DURATION=10
fi
export NETWORK_DELAY=0

# Check which OS we're on
export OS=`uname -s`

# Compute various useful parameters from REQUESTS, CONCURRENT, DURATION and TARGETURL
export_testvars() {
  export REQS_PER_VU=`expr ${REQUESTS} \/ ${CONCURRENT}`
  export RATE=`expr ${REQUESTS} \/ ${DURATION}`
  # Special case for Tsung, which otherwise sometimes fails
  export TSUNG_MU=`expr ${CONCURRENT} \* 2`
  if [ "${TARGETURL}x" = "x" ] ; then
    unset TARGETPROTO
    unset TARGETHOST
    unset TARGETPATH
    unset TARGETBASEURL
  else
    export TARGETPROTO=`echo ${TARGETURL} |egrep -o '^https?'`
    export TARGETHOST=`echo ${TARGETURL} |sed 's/https:\/\///' |sed 's/http:\/\///' |cut -d\/ -f1`
    export TARGETPATH=/`echo ${TARGETURL} |awk -F\/ '{print $NF}'`
    export TARGETBASEURL="${TARGETPROTO}://${TARGETHOST}"
  fi
}

# replace occurrences of a string in a file
# replace fname str replace-str
replace() {
  FNAME=$1
  STR=$2
  REPLACE=$3
  awk -v rep="${REPLACE}" '{gsub("'${STR}'", rep);print $0}' ${FNAME} >/tmp/_replace.tmp
  mv -f /tmp/_replace.tmp ${FNAME}
}

# perform a number of string replacements inside a config file
# replace_all $source_cfg $target_cfg
replace_all() {
  SRC=$1
  DEST=$2
  cp -f $SRC $DEST
  replace $DEST "REQS_PER_VU" "${REQS_PER_VU}"
  replace $DEST "CONCURRENT" "${CONCURRENT}"
  replace $DEST "DURATION" "${DURATION}"
  replace $DEST "RATE" "${RATE}"
  replace $DEST "TARGETHOST" "${TARGETHOST}"
  replace $DEST "TARGETPATH" "${TARGETPATH}"
  replace $DEST "TARGETURL" "${TARGETURL}"
  replace $DEST "TARGETBASEURL" "${TARGETBASEURL}"
  replace $DEST "LOGDIR" "${RESULTS_D}"
  replace $DEST "TSUNG_MAXUSERS" "${TSUNG_MU}"
}

# round down to nearest integer
toint() {
  read X
  echo "scale=0; ${X}/1" |bc
}

# Take a decimal or integer number and strip it to at most 2-digit precision
stripdecimals() {
  X=`egrep -o '^[0-9]*\.?[0-9]?[0-9]?' |awk 'NR==1{print $1}'`
  echo "if (${X}>0 && ${X}<1) print 0; ${X}" |bc
}

# utility func to interpret "Xs", "Xms", "Xus", "Xns" durations and translate them to ms
# with max 2 decimals of precision (depending on the precision of the original number -
# i.e. "0.3s" becomes "300" [ms] but not "300.00" because that implies more precision
# in the original number than we actually have)
duration2ms() {
  read X
  UNIT=`echo $X |egrep -o '[mun]?s'`
  if [ "${UNIT}x" = "x" ] ; then
    NUM=$X
  else
    NUM=`echo $X |sed 's/'${UNIT}'//'`
  fi
  # Check that NUM is an actual number. If not, it might be e.g. "NaN" reported by Artillery
  # and we consider that to be a "not reported" metric. It might also be some strange error
  # of course. We should probably try harder to detect errors.
  echo "${NUM}" |egrep '^[0-9]*\.?[0-9]*$' >/dev/null 2>&1
  if [ $? -eq 1 ] ; then
    echo "-"
    return 0
  fi
  PRECISION=`echo "scale(${NUM})" |bc -l`
  if [ "${UNIT}x" = "sx" -o "${UNIT}x" = "x" ] ; then
    # Seconds
    OUTPUT=`echo "if (${PRECISION}<3) scale=0; if (${PRECISION}>=3) scale=${PRECISION}-3; if (scale>2) scale=2; x=${NUM}/0.001; if (x<1) print 0; x" |bc -l`
  elif [ "${UNIT}x" = "msx" ] ; then
    OUTPUT=`echo "scale=${PRECISION}; if (scale>2) scale=2; x=${NUM}/1; if (x<1) print 0; x" |bc -l`
  elif [ "${UNIT}x" = "usx" ] ; then
    OUTPUT=`echo "scale=2; x=${NUM}/1000; if (x<1) print 0; x" |bc -l`
  elif [ "${UNIT}x" = "nsx" ] ; then
    OUTPUT=`echo "scale=2; x=${NUM}/1000000; if (x<1) print 0; x" |bc -l`
  else
    echo "error: unknown unit in duration: ${1}"
    return 1
  fi
  # Should we output "-" when OUTPUT==0 ?   Maybe "-" should signify that we are not even trying to
  # compute that metric, and "0" for any duration should be output as just "0", to indicate that the
  # value should be viewed with suspicion, and perhaps need manual verification.
  #if [ `echo "${OUTPUT}==0" |bc` -eq 1 ] ; then
  #  echo "-"
  #else
  #  echo ${OUTPUT}
  #fi
  if [ `echo "${OUTPUT}==0" |bc` -eq 1 ] ; then
    echo "0"
  else
    echo ${OUTPUT}
  fi
}

#
# Extract a percentile based on an input stream with samples
# awk -F\, 'NR>1{print $13}' $1 |percentile 50
#
percentile() {
  PCT=$1
  TMPFILE=/tmp/percentile.$$.sorted
  sort -n >$TMPFILE
  LINES=`wc -l ${TMPFILE} |awk '{print $1}'`
  TARGETLINE=`echo "scale=0; (${PCT}*${LINES})/100" |bc`
  awk 'NR=='${TARGETLINE}'{print $1}' ${TMPFILE}
  rm -f ${TMPFILE}
}

# param 1: filename containing test data from one or more tests, in this format (one test result per line):
# TESTNAME RUNTIME REQUESTS ERRORS RPS RTTMIN RTTMAX RTTAVG(mean) RTTp50(median) RTTp75 RTTp90 RTTp95 RTTp99
# Use "-" if there is no result for that param
# optional 2nd param is a header to also be sent to column
report() {
  ( if [ $# -gt 1 ]; then
      echo "$2"
      cat $1
    else
      awk '{printf $1" "; \
        if ($2=="-")printf "- "; else printf "runtime="$2" "; \
        if ($3=="-")printf "- "; else printf "requests="$3" "; \
        if ($4=="-")printf "- "; else printf "errors="$4" "; \
        if ($5=="-")printf "- "; else printf "rps="$5" "; \
        if ($6=="-")printf "- "; else printf "rttmin="$6" "; \
        if ($7=="-")printf "- "; else printf "rttmax="$7" "; \
        if ($8=="-")printf "- "; else printf "rttavg="$8" "; \
        if ($9=="-")printf "- "; else printf "rtt50="$9" "; \
        if ($10=="-")printf "- "; else printf "rtt75="$10" "; \
        if ($11=="-")printf "- "; else printf "rtt90="$11" "; \
        if ($12=="-")printf "- "; else printf "rtt95="$12" "; \
        if ($13=="-")print "-"; else print "rtt99="$13}' $1
    fi ) |column -t
}

gettimestamp() {
  if [ "${OS}x" = "Darwinx" ]; then
      # Seconds since epoch, with nanosecond resolution, for MacOS
      cat <<EOF |perl
        #!/usr/bin/env perl
        use strict;
        use warnings;
        use Time::HiRes qw(gettimeofday);
        use POSIX       qw(strftime);
        my (\$s,\$us) = gettimeofday();
        printf "%s.%06d\n", \$s, \$us;
EOF
      return
  else
    date '+%s.%N'
  fi
}

#
# And here comes the actual tests!
#

# Static-URL tests
apachebench_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to results on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS=${RESULTS}/timings
  PERCENTAGES=${RESULTS}/percentages
  # Paths to results in Docker instance
  RESULTS_D=/loadgentest/results/${STARTTIME}/${TESTNAME}
  PERCENTAGES_D=${RESULTS_D}/percentages
  echo "${TESTNAME}: Executing docker run -v ${TESTDIR}:/loadgentest loadimpact/loadgentest-apachebench -k -e ${PERCENTAGES_D} -t ${DURATION} -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} ... "
  _START=`gettimestamp`
  docker run -v ${TESTDIR}:/loadgentest loadimpact/loadgentest-apachebench -k -e ${PERCENTAGES_D} -t ${DURATION} -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`gettimestamp`
  echo "${_END} - ${_START}" |bc
  _DURATION=`echo "${_END} - ${_START}" |bc |stripdecimals`
  _REQUESTS=`grep '^Complete\ requests:' ${RESULTS}/stdout.log |awk '{print $3}'`
  _RPS=`grep '^Requests\ per\ second:' ${RESULTS}/stdout.log |awk '{print $4}' |toint`
  _RTTAVG=`grep '^Time\ per\ request:' ${RESULTS}/stdout.log |grep '(mean)' |awk '{print $4}' |stripdecimals`
  _ERRORS=`grep '^Failed\ requests:' ${RESULTS}/stdout.log |awk '{print $3}'`
  _RTTMIN=`awk -F\, 'NR==2{print $2}' ${PERCENTAGES} |stripdecimals`
  _RTTMAX="-"
  _RTTp50=`grep '^50,' ${PERCENTAGES} |cut -d\, -f2 |awk '{print $1}' |stripdecimals`
  _RTTp75=`grep '^75,' ${PERCENTAGES} |cut -d\, -f2 |awk '{print $1}' |stripdecimals`
  _RTTp90=`grep '^90,' ${PERCENTAGES} |cut -d\, -f2 |awk '{print $1}' |stripdecimals`
  _RTTp95=`grep '^95,' ${PERCENTAGES} |cut -d\, -f2 |awk '{print $1}' |stripdecimals`
  _RTTp99=`grep '^99,' ${PERCENTAGES} |cut -d\, -f2 |awk '{print $1}' |stripdecimals`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

wrk_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to results on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS=${RESULTS}/timings
  # Paths to results in Docker instance
  RESULTS_D=/loadgentest/results/${STARTTIME}/${TESTNAME}
  # Note that we supply TARGETURL on the cmd line as wrk requires that, but the cmd line parameter will
  # not be used as our script decides what URL to load (which will of course be the same TARGETURL though)
  echo "${TESTNAME}: Executing docker run -v ${TESTDIR}:/loadgentest loadimpact/loadgentest-wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} --latency ${TARGETURL} ... "
  _START=`gettimestamp`
  docker run -v ${TESTDIR}:/loadgentest loadimpact/loadgentest-wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} --latency ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`gettimestamp`
  _DURATION=`echo "${_END} - ${_START}" |bc |stripdecimals`
  _RPS=`grep '^Requests/sec:' ${RESULTS}/stdout.log |awk '{print $2}' |toint`
  _RTTAVG=`grep -A 2 'Thread Stats' ${RESULTS}/stdout.log |grep 'Latency' |awk '{print $2}' |duration2ms |stripdecimals`
  _REQUESTS=`grep ' requests in ' ${RESULTS}/stdout.log |tail -1 |awk '{print $1}'`
  _ERRORS="-"
  _RTTMIN="-"
  _RTTMAX=`grep -A 2 'Thread Stats' ${RESULTS}/stdout.log |grep 'Latency' |awk '{print $4}' |duration2ms |stripdecimals`
  _RTTp50=`grep -A 4 'Latency Distribution' ${RESULTS}/stdout.log |awk '$1=="50%"{print $2}' |duration2ms |stripdecimals`
  _RTTp75=`grep -A 4 'Latency Distribution' ${RESULTS}/stdout.log |awk '$1=="75%"{print $2}' |duration2ms |stripdecimals`
  _RTTp90=`grep -A 4 'Latency Distribution' ${RESULTS}/stdout.log |awk '$1=="90%"{print $2}' |duration2ms |stripdecimals`
  _RTTp95="-"
  _RTTp99=`grep -A 4 'Latency Distribution' ${RESULTS}/stdout.log |awk '$1=="99%"{print $2}' |duration2ms |stripdecimals`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

hey_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to results on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS=${RESULTS}/timings
  # Paths to results in Docker instance
  RESULTS_D=/loadgentest/results/${STARTTIME}/${TESTNAME}
  echo "${TESTNAME}: Executing docker run -v ${TESTDIR}:/loadgentest loadimpact/loadgentest-hey -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} ... "
  docker run -v ${TESTDIR}:/loadgentest loadimpact/loadgentest-hey -n ${REQUESTS} -c ${CONCURRENT} ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _RPS=`grep -A 5 '^Summary:' ${RESULTS}/stdout.log |grep 'Requests/sec:' |awk '{print $2}' |toint`
  _DURATION=`grep -A 5 '^Summary:' ${RESULTS}/stdout.log |grep 'Total:' |awk '{print $2}' |stripdecimals`
  _REQUESTS=`grep '\[200\]' ${RESULTS}/stdout.log |grep ' responses' |awk '{print $2}'`
  _ERRORS=`grep -A 10 '^Status code distribution:' ${RESULTS}/stdout.log |grep -v '\[200\]' |grep ' responses' |awk 'BEGIN{tot=0}{tot=tot+$2}END{print tot}'`
  _RTTMIN=`egrep 'Fastest:.* secs$' ${RESULTS}/stdout.log |awk '{print $2*1000}' |stripdecimals`
  _RTTMAX=`egrep 'Slowest:.* secs$' ${RESULTS}/stdout.log |awk '{print $2*1000}' |stripdecimals`
  _RTTAVG=`egrep 'Average:.* secs$' ${RESULTS}/stdout.log |awk '{print $2*1000}' |stripdecimals`
  _RTTp50=`egrep '50% in .* secs$' ${RESULTS}/stdout.log |awk '{print $3*1000}' |stripdecimals`
  _RTTp75=`egrep '75% in .* secs$' ${RESULTS}/stdout.log |awk '{print $3*1000}' |stripdecimals`
  _RTTp90=`egrep '90% in .* secs$' ${RESULTS}/stdout.log |awk '{print $3*1000}' |stripdecimals`
  _RTTp95=`egrep '95% in .* secs$' ${RESULTS}/stdout.log |awk '{print $3*1000}' |stripdecimals`
  _RTTp99=`egrep '99% in .* secs$' ${RESULTS}/stdout.log |awk '{print $3*1000}' |stripdecimals`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

artillery_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to things on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  CONFIGS=${TESTDIR}/configs
  mkdir -p ${CONFIGS}
  TIMINGS=${RESULTS}/timings
  CFG=${CONFIGS}/artillery_${STARTTIME}.json
  # Paths to things in Docker instance
  RESULTS_D=/loadgentest/results/${STARTTIME}/${TESTNAME}
  CONFIGS_D=/loadgentest/configs
  CFG_D=${CONFIGS_D}/artillery_${STARTTIME}.json
  replace_all ${CONFIGS}/artillery.json ${CFG}
  # artillery writes its report to disk after the test has finished, which means performance during the
  # test should not be affected
  echo "${TESTNAME}: Executing docker run -v ${TESTDIR}:/loadgentest loadimpact/loadgentest-artillery run -o ${RESULTS_D}/artillery_report.json ${CFG_D}"
  _START=`gettimestamp`
  docker run -v ${TESTDIR}:/loadgentest loadimpact/loadgentest-artillery run -o ${RESULTS_D}/artillery_report.json ${CFG_D} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`gettimestamp`
  _DURATION=`echo "${_END}-${_START}" |bc |stripdecimals`
  _TMPDATA=${RESULTS}/transaction_log
  jq -c '.intermediate[] |.latencies[] |{rtt:.[2],code:.[3],ts:.[0]}' ${RESULTS}/artillery_report.json >${_TMPDATA}
  _REQUESTS=`wc -l ${_TMPDATA} |awk '{print $1}'`
  _START_TS=`head -1 ${_TMPDATA} |egrep -o '"ts":[0-9]*' |awk -F: '{print $2}'`
  _END_TS=`tail -1 ${_TMPDATA} |egrep -o '"ts":[0-9]*' |awk -F: '{print $2}'`
  _DURATION_MS=`echo "${_END_TS}-${_START_TS}" |bc`
  _RPS=`echo "scale=0; (${_REQUESTS}*1000)/${_DURATION_MS}" |bc`
  _OKNUM=`grep '"code":200' ${_TMPDATA} |wc -l |awk '{print $1}'`
  _OKRTTTOTUS=`grep '"code":200' ${_TMPDATA} |egrep -o '"rtt":[0-9]*' |awk -F: '{print int($2/1000)}' |paste -sd+ - |bc -l`
  _RTTAVGUS=`echo "${_OKRTTTOTUS}/${_OKNUM}" |bc -l |toint`
  _RTTAVG=`echo "${_RTTAVGUS}us" |duration2ms`
  _ERRORS=`expr ${_REQUESTS} - ${_OKNUM}`
  _RTTMINUS=`grep '"code":200' ${_TMPDATA} |egrep -o '"rtt":[0-9]*\.?[0-9]*[eE]?\+?[0-9]*' |awk -F: '{print int($2/1000)}' |sort -n |head -1`
  _RTTMIN=`echo "${_RTTMINUS}us" |duration2ms`
  _RTTMAXUS=`grep '"code":200' ${_TMPDATA} |egrep -o '"rtt":[0-9]*\.?[0-9]*[eE]?\+?[0-9]*' |awk -F: '{print int($2/1000)}' |sort -n |tail -1`
  _RTTMAX=`echo "${_RTTMAXUS}us" |duration2ms`
  _RTTp50US=`grep '"code":200' ${_TMPDATA} |egrep -o '"rtt":[0-9]*\.?[0-9]*[eE]?\+?[0-9]*' |awk -F: '{print int($2/1000)}' |percentile 50`
  _RTTp50=`echo "${_RTTp50US}us" |duration2ms`
  _RTTp75US=`grep '"code":200' ${_TMPDATA} |egrep -o '"rtt":[0-9]*\.?[0-9]*[eE]?\+?[0-9]*' |awk -F: '{print int($2/1000)}' |percentile 75`
  _RTTp75=`echo "${_RTTp75US}us" |duration2ms`
  _RTTp90US=`grep '"code":200' ${_TMPDATA} |egrep -o '"rtt":[0-9]*\.?[0-9]*[eE]?\+?[0-9]*' |awk -F: '{print int($2/1000)}' |percentile 90`
  _RTTp90=`echo "${_RTTp90US}us" |duration2ms`
  _RTTp95US=`grep '"code":200' ${_TMPDATA} |egrep -o '"rtt":[0-9]*\.?[0-9]*[eE]?\+?[0-9]*' |awk -F: '{print int($2/1000)}' |percentile 95`
  _RTTp95=`echo "${_RTTp95US}us" |duration2ms`
  _RTTp99US=`grep '"code":200' ${_TMPDATA} |egrep -o '"rtt":[0-9]*\.?[0-9]*[eE]?\+?[0-9]*' |awk -F: '{print int($2/1000)}' |percentile 99`
  _RTTp99=`echo "${_RTTp99US}us" |duration2ms`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

vegeta_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to things on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS=${RESULTS}/timings
  # Paths to things in Docker instance
  RESULTS_D=/loadgentest/results/${STARTTIME}/${TESTNAME}
  # Vegeta only supports static request rates. You might want to change the REQUESTS parameter until you get the highest throughput w/o errors.
  echo "${TESTNAME}: Executing echo \"GET ${TARGETURL}\" | docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-vegeta attack -rate=${RATE} -connections=${CONCURRENT} -duration=${DURATION}s ... "
  _START=`gettimestamp`
  echo "GET ${TARGETURL}" |docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-vegeta attack -rate=${RATE} -connections=${CONCURRENT} -duration=${DURATION}s >${RESULTS}/stdout.log 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`gettimestamp`
  _DURATION=`echo "${_END}-${_START}" |bc |stripdecimals`
  #
  # Vegeta does not report redirect responses, like many other tools. But this means that considering any
  # reported response codes !=200 to be errors is not completely stupid.
  #
  # Vegeta managed to do 4000 RPS over a 10ms RTT network connection while being configured to 
  # use 20 concurrent connections. Or so I thought. The -connections option is only a STARTING value
  # that Vegeta may change at runtime as it sees fit. Aargh. This means there is no practical way
  # to control concurrrency in Vegeta.
  #
  #json dumper: {"code":200,"timestamp":"2016-10-17T09:30:53.991690378Z","latency":490871,"bytes_out":0,"bytes_in":103,"error":""}
  #csv dumper: 1476696644001690668,200,2124978,0,103,""
  # (note that Vegeta inserts no CSV header in the CSV dump; the first line is the first data point)
  #
  _CSV=${RESULTS}/vegeta_dump.csv
  docker run -i loadimpact/loadgentest-vegeta dump -dumper csv <${RESULTS}/stdout.log >${_CSV}
  _REQUESTS=`awk 'END{print NR}' ${_CSV}`
  _STARTNS=`head -1 ${_CSV} |awk -F\, '{print $1}'`
  _ENDNS=`tail -1 ${_CSV} |awk -F\, '{print $1}'`
  _DURATIONMS=`echo "(${_ENDNS}-${_STARTNS})/1000000" |bc`
  _RPS=`echo "(${_REQUESTS}*1000)/${_DURATIONMS}" |bc`
  _RTTTOTMS=`awk -F\, '{print $3/1000000}' ${_CSV} |paste -sd+ - |bc -l`
  _RTTAVG=`echo "${_RTTTOTMS}/${_REQUESTS}" |bc -l |stripdecimals`
  _RTTMIN=`awk -F\, '{print $3/1000000}' ${_CSV} |sort -n |head -1 |stripdecimals`
  _RTTMAX=`awk -F\, '{print $3/1000000}' ${_CSV} |sort -n |tail -1 |stripdecimals`
  _RTTp50=`awk -F\, '{print $3/1000000}' ${_CSV} |percentile 50 |stripdecimals`
  _RTTp75=`awk -F\, '{print $3/1000000}' ${_CSV} |percentile 75 |stripdecimals`
  _RTTp90=`awk -F\, '{print $3/1000000}' ${_CSV} |percentile 90 |stripdecimals`
  _RTTp95=`awk -F\, '{print $3/1000000}' ${_CSV} |percentile 95 |stripdecimals`
  _RTTp99=`awk -F\, '{print $3/1000000}' ${_CSV} |percentile 99 |stripdecimals`
  _OKREQUESTS=`awk -F\, '$2==200{print $0}' ${_CSV} |awk 'END{print NR}'`
  _ERRORS=`expr ${_REQUESTS} - ${_OKREQUESTS}`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

siege_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to things on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  TIMINGS=${RESULTS}/timings
  CONFIGS_D=/loadgentest/configs
  SIEGERC_D=${CONFIGS_D}/siegerc
  # We don't need paths in the Docker instance as it seems more or less impossible
  # to get Siege to create a logfile. At the very least it seems to blatantly ignore
  # the -l flag.
  echo "${TESTNAME}: Executing docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-siege -b -t ${DURATION}S -c ${CONCURRENT} -R ${SIEGERC_D} ${TARGETURL} ... "
  _START=`gettimestamp`
  # -q flag now (since Siege v4?) suppresses ALL useful output to stdout and stderr (but retains some three lines of
  # useless text? - e.g. "The server is now under siege..." - sent to stderr). This means we can't use -q 
  # anymore, or we get no statistics. Problem is, without the flag we get one line of output to stdout for each and 
  # every HTTP transaction. There doesn't seem to be a mode in which we get summary statistics without also enabling
  # per-request statistics output. We don't know if output from the Docker instance sent stdout on the host machine 
  # could become a bottleneck here, so to be on the safe side we disable stdout output to the user and just store
  # it in a file, for later processing.
  # Siege also seems to have a built-in limit that says it will simulate
  # 255 VUs tops, which is a bit low. We'll up it. Note though that Siege
  # becomes progressively more unstable when simulating more VUs. At least
  # in earlier versions, going over 500 VUs would make it core dump regularly.
  docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-siege -b -t ${DURATION}S -R ${SIEGERC_D} -c ${CONCURRENT} ${TARGETURL} > ${RESULTS}/stdout.log 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`gettimestamp`
  _DURATION=`echo "${_END}-${_START}" |bc |stripdecimals`
  _REQUESTS=`grep '^Transactions:' ${RESULTS}/stderr.log |awk '{print $2}'`
  _RPS=`grep '^Transaction rate:' ${RESULTS}/stderr.log |awk '{print $3}' |toint`
  # Siege reports response time in seconds, with only 2 decimals of precision. In a benchmark it is not unlikely
  # you will see it report 0.00s response times, or response times that never change. 
  _RTTAVG=`grep '^Response time:' ${RESULTS}/stderr.log |awk '{print $3}' |duration2ms`
  # Just like Vegeta, Siege does not report redirect responses. When redirects happen, they are considered part of a
  # "successful transaction". Also interesting is how a 3xx response will increase the "successful transactions" counter
  # but if the redirected response does then not return 2xx or 3xx, the counter will be decreased again and the error
  # counter increased instead. This means you can see more "Successful transactions" than "Transactions" (because some
  # were redirected and did not have time to complete the redirected request).
  _ERRORS=`grep '^Failed transactions:' ${RESULTS}/stderr.log |awk '{print $3}' |toint`
  _RTTMIN=`grep '^Shortest transaction:' ${RESULTS}/stderr.log |awk '{print $3}' |duration2ms`
  _RTTMAX=`grep '^Longest transaction:' ${RESULTS}/stderr.log |awk '{print $3}' |duration2ms`
  _RTTp50=`grep "secs:" ${RESULTS}/stdout.log |awk '$2=="200"{print $3*1000}' |percentile 50 |stripdecimals`
  _RTTp75=`grep "secs:" ${RESULTS}/stdout.log |awk '$2=="200"{print $3*1000}' |percentile 75 |stripdecimals`
  _RTTp90=`grep "secs:" ${RESULTS}/stdout.log |awk '$2=="200"{print $3*1000}' |percentile 90 |stripdecimals`
  _RTTp95=`grep "secs:" ${RESULTS}/stdout.log |awk '$2=="200"{print $3*1000}' |percentile 95 |stripdecimals`
  _RTTp99=`grep "secs:" ${RESULTS}/stdout.log |awk '$2=="200"{print $3*1000}' |percentile 99 |stripdecimals`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

tsung_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to things on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  CONFIGS=${TESTDIR}/configs
  mkdir -p ${CONFIGS}
  TIMINGS=${RESULTS}/timings
  CFG=${CONFIGS}/tsung_${STARTTIME}.xml
  # Paths to things in Docker instance
  RESULTS_D=/loadgentest/results/${STARTTIME}/${TESTNAME}
  CONFIGS_D=/loadgentest/configs
  CFG_D=${CONFIGS_D}/tsung_${STARTTIME}.xml
  replace_all ${CONFIGS}/tsung.xml ${CFG}
  # Hard to get good stats from Tsung unless we make it log each transaction, but the transaction log format
  # is pretty compact, with maybe 80 characters / transaction, so a test with a million or so requests
  # should not incur a large overhead for transaction log writing
  echo "${TESTNAME}: Executing docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-tsung -l ${RESULTS_D} -f ${CFG_D} start ... "
  _START=`gettimestamp`
  docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-tsung -l ${RESULTS_D} -f ${CFG_D} start > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`gettimestamp`
  _DURATION=`echo "${_END}-${_START}" |bc |stripdecimals`
  _LOGDIR="${RESULTS}/"`grep '^Log directory is:' ${RESULTS}/stdout.log |awk '{print $4}' |awk -F\/ '{print $NF}'`
  _STARTMS=`head -2 ${_LOGDIR}/tsung.dump | tail -1 |awk -F\; '{print $1}' |cut -c1-14 |sed 's/\.//'`
  _ENDMS=`tail -1 ${_LOGDIR}/tsung.dump |awk -F\; '{print $1}' |cut -c1-14 |sed 's/\.//'`
  _REQUESTS=`awk 'END{print NR-1}' ${_LOGDIR}/tsung.dump`
  _RPS=`echo "(${_REQUESTS}*1000)/(${_ENDMS}-${_STARTMS})" |bc`
  _RTTAVG=`awk -F\; 'BEGIN{tot=0;num=0}NR>1{tot=tot+$9; num=num+1}END{print tot/num}' ${_LOGDIR}/tsung.dump |stripdecimals`
  #
  # Tsung actually bothers to correctly report 3xx redirect responses (as opposed to many other tools)
  # So we only count something as an "error" if the response code is less than 200 or 400+
  #
  _OKREQUESTS=`awk -F\; 'BEGIN{num=0}NR>1{if ($7>=200 && $7<400) num=num+1}END{print num}' ${_LOGDIR}/tsung.dump`
  _ERRORS=`expr ${_REQUESTS} - ${_OKREQUESTS}`
  _RTTMAX=`awk -F\; 'NR>1{print $9}' ${_LOGDIR}/tsung.dump |sort -n |tail -1 |stripdecimals`
  _RTTMIN=`awk -F\; 'NR>1{print $9}' ${_LOGDIR}/tsung.dump |sort -n |head -1 |stripdecimals`
  _RTTp50=`awk -F\; 'NR>1{print $9}' ${_LOGDIR}/tsung.dump |percentile 50 |stripdecimals`
  _RTTp75=`awk -F\; 'NR>1{print $9}' ${_LOGDIR}/tsung.dump |percentile 75 |stripdecimals`
  _RTTp90=`awk -F\; 'NR>1{print $9}' ${_LOGDIR}/tsung.dump |percentile 90 |stripdecimals`
  _RTTp95=`awk -F\; 'NR>1{print $9}' ${_LOGDIR}/tsung.dump |percentile 95 |stripdecimals`
  _RTTp99=`awk -F\; 'NR>1{print $9}' ${_LOGDIR}/tsung.dump |percentile 99 |stripdecimals`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

jmeter_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to things on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  CONFIGS=${TESTDIR}/configs
  mkdir -p ${CONFIGS}
  TIMINGS=${RESULTS}/timings
  CFG=${CONFIGS}/jmeter_${STARTTIME}.xml
  JMETERLOG=${RESULTS}/jmeter.log
  TXLOG=${RESULTS}/transactions.csv
  # Paths to things in Docker instance
  RESULTS_D=/loadgentest/results/${STARTTIME}/${TESTNAME}
  CONFIGS_D=/loadgentest/configs
  CFG_D=${CONFIGS_D}/jmeter_${STARTTIME}.xml
  replace_all ${CONFIGS}/jmeter.xml ${CFG}
  # TODO: support for protocols other than plain HTTP... we dont specify protocol in the test plan ATM
  JMETERLOG_D=${RESULTS_D}/jmeter.log
  TXLOG_D=${RESULTS_D}/transactions.csv
  #
  # useNanoTime=true doesn't seem to work. I'm probably doing something wrong.
  #
  # Like Tsung, the Jmeter transaction log is in a compact CSV format that should not affect RPS
  # numbers too much
  echo "${TESTNAME}: Executing docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-jmeter jmeter -n -t ${CFG_D} -j ${JMETERLOG_D} -l ${TXLOG_D} -D sampleresult.useNanoTime=true ... "
  _START=`gettimestamp`
  docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-jmeter jmeter -n -t ${CFG_D} -j ${JMETERLOG_D} -l ${TXLOG_D} -D sampleresult.useNanoTime=true > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`gettimestamp`
  _DURATION=`echo "${_END}-${_START}" |bc |stripdecimals`
  # TXLOG:
  #timeStamp,elapsed,label,responseCode,responseMessage,threadName,dataType,success,failureMessage,bytes,grpThreads,allThreads,Latency,IdleTime
  #1476361406039,92,HTTP Request,200,OK,Thread Group 1-1,text,true,,311,4,4,92,0
  #1476361406039,92,HTTP Request,200,OK,Thread Group 1-2,text,true,,311,4,4,92,0
  _STARTMS=`head -2 ${TXLOG} |tail -1 |cut -c1-13`
  _ENDMS=`tail -1 ${TXLOG} |cut -c1-13`
  _REQUESTS=`awk 'END{print NR-1}' ${TXLOG}`
  _RPS=`echo "(${_REQUESTS}*1000)/(${_ENDMS}-${_STARTMS})" |bc`
  _RTTAVG=`awk -F\, 'BEGIN{tot=0;num=0;}NR>1{num=num+1;tot=tot+$14}END{printf "%.2f", tot/num}' ${TXLOG}`
  _RTTMIN=`awk -F\, 'NR>1{print $14}' ${TXLOG} |sort -n | head -1`
  _RTTMAX=`awk -F\, 'NR>1{print $14}' ${TXLOG} |sort -n | tail -1`
  _ERRORS=`awk -F\, 'NR>1&&($4<200||$4>=400){print $0}' ${TXLOG} |wc -l |awk '{print $1}'`
  _RTTp50=`awk -F\, 'NR>1{print $14}' ${TXLOG} |percentile 50`
  _RTTp75=`awk -F\, 'NR>1{print $14}' ${TXLOG} |percentile 75`
  _RTTp90=`awk -F\, 'NR>1{print $14}' ${TXLOG} |percentile 90`
  _RTTp95=`awk -F\, 'NR>1{print $14}' ${TXLOG} |percentile 95`
  _RTTp99=`awk -F\, 'NR>1{print $14}' ${TXLOG} |percentile 99`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

gatling_static() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to things on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  CONFIGS=${TESTDIR}/configs
  mkdir -p ${CONFIGS}
  SIMULATIONDIR=${CONFIGS}/Gatling_${STARTTIME}
  mkdir -p ${SIMULATIONDIR}
  TIMINGS=${RESULTS}/timings
  SIMULATIONCLASS=GatlingSimulation
  CFG=${SIMULATIONDIR}/${SIMULATIONCLASS}.scala
  # Paths to things in Docker instance
  RESULTS_D=/loadgentest/results/${STARTTIME}/${TESTNAME}
  CONFIGS_D=/loadgentest/configs
  SIMULATIONDIR_D=${CONFIGS_D}/Gatling_${STARTTIME}
  CFG_D=${CONFIGS_D}/jmeter_${STARTTIME}.xml
  replace_all ${CONFIGS}/gatling.scala ${CFG}
  JAVA_OPTS="-Dvus=${CONCURRENT} -Dduration=${DURATION} -Dtargetproto=${TARGETPROTO} -Dtargethost=${TARGETHOST} -Dtargetpath=${TARGETPATH}"
  echo "${TESTNAME}: Executing gatling ... "
  _START=`gettimestamp`
  docker run -v ${TESTDIR}:/loadgentest -i -e "JAVA_OPTS=${JAVA_OPTS}" loadimpact/loadgentest-gatling -sf ${SIMULATIONDIR_D} -s ${SIMULATIONCLASS} -rf ${RESULTS_D} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`gettimestamp`
  _DURATION=`echo "${_END}-${_START}" |bc |stripdecimals`
  # Please open the following file: /loadgentests/results/161013-122223/gatling_static/gatlingsimulation-1476361428999/index.html
  _SIMULATIONLOG=${TESTDIR}/`grep "Please open the following file" ${RESULTS}/stdout.log |cut -d\: -f2- |awk '{print $1}' |sed 's/\/index.html//' |cut -c14-`/simulation.log
  #REQUEST	Scenario Name	5		request_1	1476361429927	1476361429947	OK
  #REQUEST	Scenario Name	6		request_1	1476361429929	1476361429956	OK
  #REQUEST	Scenario Name	2		request_1	1476361429914	1476361429932	OK
  #REQUEST	Scenario Name	8		request_1	1476361429935	1476361429949	OK
  _REQUESTS=`grep '^REQUEST' ${_SIMULATIONLOG} |wc -l |awk '{print $1}'`
  _STARTMS=`grep '^REQUEST' ${_SIMULATIONLOG} |head -1 |awk '{print $6}'`
  _ENDMS=`grep '^REQUEST' ${_SIMULATIONLOG} |tail -1 |awk '{print $7}'`
  _OKREQS=`awk '$1=="REQUEST"&&$8=="OK" {print $0}' ${_SIMULATIONLOG} |wc -l |awk '{print $1}'`
  _ERRORS=`expr ${_REQUESTS} - ${_OKREQS}`
  _RPS=`echo "(${_REQUESTS}*1000)/(${_ENDMS}-${_STARTMS})" | bc`
  _RTTAVG=`awk 'BEGIN{tot=0; num=0}$1=="REQUEST"{tot=tot+($7-$6); num=num+1}END{print tot/num}' ${_SIMULATIONLOG} |stripdecimals`
  _RTTMIN=`awk '$1=="REQUEST"{print $7-$6}' ${_SIMULATIONLOG} |sort -n |head -1 |stripdecimals`
  _RTTMAX=`awk '$1=="REQUEST"{print $7-$6}' ${_SIMULATIONLOG} |sort -n |tail -1 |stripdecimals`
  _RTTp50=`awk '$1=="REQUEST"{print $7-$6}' ${_SIMULATIONLOG} |percentile 50 |stripdecimals`
  _RTTp75=`awk '$1=="REQUEST"{print $7-$6}' ${_SIMULATIONLOG} |percentile 75 |stripdecimals`
  _RTTp90=`awk '$1=="REQUEST"{print $7-$6}' ${_SIMULATIONLOG} |percentile 90 |stripdecimals`
  _RTTp95=`awk '$1=="REQUEST"{print $7-$6}' ${_SIMULATIONLOG} |percentile 95 |stripdecimals`
  _RTTp99=`awk '$1=="REQUEST"{print $7-$6}' ${_SIMULATIONLOG} |percentile 99 |stripdecimals`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}


# Scripting tests
locust_scripting() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to things on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  CONFIGS=${TESTDIR}/configs
  mkdir -p ${CONFIGS}
  CFG=${TESTDIR}/configs/locust_${STARTTIME}.py
  TIMINGS=${RESULTS}/timings
  # Paths to things in Docker instance
  RESULTS_D=/loadgentest/results/${STARTTIME}/${TESTNAME}
  CONFIGS_D=/loadgentest/configs
  CFG_D=${CONFIGS_D}/locust_${STARTTIME}.py
  replace_all ${CONFIGS}/locust.py ${CFG}
  _START=`gettimestamp`
  echo "${TESTNAME}: Executing docker run -v ${TESTDIR}:/loadgentest -i -e LOCUST_HOST="${TARGETPROTO}://${TARGETHOST}" -e LOCUST_FILE=${CFG_D} -e LOCUST_COUNT=${CONCURRENT} -e LOCUST_HATCH_RATE=${CONCURRENT} -e LOCUST_DURATION=${DURATION} heyman/locust-bench ... "
  docker run -v ${TESTDIR}:/loadgentest -i -e LOCUST_HOST="${TARGETPROTO}://${TARGETHOST}" -e LOCUST_FILE=${CFG_D} -e LOCUST_COUNT=${CONCURRENT} -e LOCUST_HATCH_RATE=${CONCURRENT} -e LOCUST_DURATION=${DURATION} heyman/locust-bench > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`gettimestamp`
  _DURATION=`echo "${_END}-${_START}" |bc |stripdecimals`
  _REQUESTS=`grep -A 10 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep '^ Aggregated' |awk '{print $2}'`
  _ERRORS=`grep -A 10 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep '^ Aggregated' |awk '{print $3}' |cut -d\( -f1`
  # Locust RPS reporting is not reliable for short test durations (it can report 0 RPS)
  _RPS=`grep -A 10 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep '^ Aggregated' |awk '{print $9}' |toint`
  if [ `echo "${_RPS}==0" |bc` -eq 1 ] ; then
    # Calculate some average RPS instead
    _RPS=`echo "scale=2; x=${_REQUESTS}/${_DURATION}; if (x<1) print 0; x" |bc |toint`
  fi
  _RTTAVG=`grep -A 10 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep '^ GET' |head -1 |awk '{print $5}' |stripdecimals`
  _RTTMIN=`grep -A 10 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep '^ GET' |head -1 |awk '{print $6}' |stripdecimals`
  _RTTMAX=`grep -A 20 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep "GET ${TARGETPATH}" |tail -1 |awk '{print $12}'`
  _RTTp50=`grep -A 20 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep "GET ${TARGETPATH}" |tail -1 |awk '{print $4}'`
  _RTTp75=`grep -A 20 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep "GET ${TARGETPATH}" |tail -1 |awk '{print $6}'`
  _RTTp90=`grep -A 20 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep "GET ${TARGETPATH}" |tail -1 |awk '{print $8}'`
  _RTTp95=`grep -A 20 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep "GET ${TARGETPATH}" |tail -1 |awk '{print $9}'`
  _RTTp99=`grep -A 20 'locust.main: Shutting down' ${RESULTS}/stderr.log |grep "GET ${TARGETPATH}" |tail -1 |awk '{print $11}'`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

grinder_scripting() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to things on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  CONFIGS=${TESTDIR}/configs
  mkdir -p ${CONFIGS}
  TIMINGS=${RESULTS}/timings
  CFG=${CONFIGS}/grinder_${STARTTIME}.py
  CFG2=${CONFIGS}/grinder_${STARTTIME}.properties
  TMPCFG2=/tmp/grinder_${STARTTIME}.properties
  # Paths to things in Docker instance
  # export RESULTS_D as it is referenced in replace_all()
  export RESULTS_D=/loadgentest/results/${STARTTIME}/${TESTNAME}
  CONFIGS_D=/loadgentest/configs
  CFG2_D=${CONFIGS_D}/grinder_${STARTTIME}.properties
  CFG_D=${CONFIGS_D}/grinder_${STARTTIME}.py
  replace_all ${CONFIGS}/grinder.py ${CFG}
  cp ${CONFIGS}/grinder.properties $TMPCFG2
  # Grinder specifies thread duration in ms
  _DURATION=`expr ${DURATION} \* 1000`
  replace $TMPCFG2 "DURATION" "${_DURATION}"
  replace $TMPCFG2 "SCRIPT" "${CFG_D}"
  replace_all $TMPCFG2 $CFG2
  rm $TMPCFG2
  echo "${TESTNAME}: Executing docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-grinder ${CFG2_D} ... "
  _START=`gettimestamp`
  docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-grinder ${CFG2_D} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`gettimestamp`
  _DURATION=`echo "${_END}-${_START}" |bc |stripdecimals`
  # Grinder only logs durations for individual requests. I don't think there is any simple way of making it
  # output aggregated statistics to the console, so we have to first find out what our workers are called
  TMP=${RESULTS}/_metrics.`date +%s`
  for WORKER in `egrep 'INFO  agent: worker .* started' ${RESULTS}/stdout.log |awk '{print $6}'`
  do
    # Then we extract all the response time metrics from the logfiles
    awk 'NR>1{print $5}' ${RESULTS}/${WORKER}-data.log |sed 's/\,//' >>${TMP}
  done
  # How many requests did we see
  _REQUESTS=`wc -l ${TMP} |awk '{print $1}'`
  # Grinder also reports redirects correctly, so here also we will count transactions as "errors"
  # if the error column was not "0" or if the response code was outside the 200..399 range
  _OKREQUESTS=`sed 's/\,//g' ${RESULTS}/*data.log |grep -v Thread |awk 'BEGIN{num=0}NR>1{if ($6==0 && ($7>=200 && $7<400)) num=num+1}END{print num}'`
  _ERRORS=`expr ${_REQUESTS} - ${_OKREQUESTS}`
  # Calculate RPS. We assume we ran for the exact DURATION.
  _RPS=`echo "scale=0; ${_REQUESTS}/${DURATION};" |bc`
  # Calculate the average for all the response times. 
  _RTTAVG=`awk 'BEGIN{num=0;tot=0}{num=num+1;tot=tot+$1}END{print tot/num}' ${TMP} |stripdecimals`
  _RTTMIN=`cat ${TMP} |sort -n |head -1 |awk '{print $1}'`
  _RTTMAX=`cat ${TMP} |sort -n |tail -1 |awk '{print $1}'`
  _RTTp50=`cat ${TMP} |percentile 50`
  _RTTp75=`cat ${TMP} |percentile 75`
  _RTTp90=`cat ${TMP} |percentile 90`
  _RTTp95=`cat ${TMP} |percentile 95`
  _RTTp99=`cat ${TMP} |percentile 99`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

wrk_scripting() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to things on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  CONFIGS=${TESTDIR}/configs
  mkdir -p ${CONFIGS}
  TIMINGS=${RESULTS}/timings
  CFG=${CONFIGS}/wrk_${STARTTIME}.lua
  # Paths to things in Docker instance
  RESULTS_D=/loadgentest/results/${STARTTIME}/${TESTNAME}
  CONFIGS_D=/loadgentest/configs
  CFG_D=${CONFIGS_D}/wrk_${STARTTIME}.lua
  replace_all ${TESTDIR}/configs/wrk.lua ${CFG}
  echo "${TESTNAME}: Executing docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} --latency --script ${CFG_D} ${TARGETURL} ... "
  _START=`gettimestamp`
  docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-wrk -c ${CONCURRENT} -t ${CONCURRENT} -d ${DURATION} --latency --script ${CFG_D} ${TARGETURL} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`gettimestamp`
  _DURATION=`echo "${_END}-${_START}" |bc |stripdecimals`
  _RPS=`grep '^Requests/sec:' ${RESULTS}/stdout.log |awk '{print $2}' |toint`
  _RTTAVG=`grep -A 2 'Thread Stats' ${RESULTS}/stdout.log |grep 'Latency' |awk '{print $2}' |duration2ms |stripdecimals`
  _REQUESTS=`grep ' requests in ' ${RESULTS}/stdout.log |tail -1 |awk '{print $1}'`
  _ERRORS="-"
  _RTTMIN="-"
  _RTTMAX=`grep -A 2 'Thread Stats' ${RESULTS}/stdout.log |grep 'Latency' |awk '{print $4}' |duration2ms |stripdecimals`
  _RTTp50=`grep -A 4 'Latency Distribution' ${RESULTS}/stdout.log |awk '$1=="50%"{print $2}' |duration2ms |stripdecimals`
  _RTTp75=`grep -A 4 'Latency Distribution' ${RESULTS}/stdout.log |awk '$1=="75%"{print $2}' |duration2ms |stripdecimals`
  _RTTp90=`grep -A 4 'Latency Distribution' ${RESULTS}/stdout.log |awk '$1=="90%"{print $2}' |duration2ms |stripdecimals`
  _RTTp95="-"
  _RTTp99=`grep -A 4 'Latency Distribution' ${RESULTS}/stdout.log |awk '$1=="99%"{print $2}' |duration2ms |stripdecimals`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}

k6_scripting() {
  TESTNAME=${FUNCNAME[0]}
  echo ""
  echo "${TESTNAME}: starting at "`date +%y%m%d-%H:%M:%S`
  # Paths to things on host machine
  RESULTS=${TESTDIR}/results/${STARTTIME}/${TESTNAME}
  mkdir -p ${RESULTS}
  CONFIGS=${TESTDIR}/configs
  mkdir -p ${CONFIGS}
  TIMINGS=${RESULTS}/timings
  CFG=${CONFIGS}/k6_${STARTTIME}.js
  # Paths to things in Docker instance
  RESULTS_D=/loadgentest/results/${STARTTIME}/${TESTNAME}
  CONFIGS_D=/loadgentest/configs
  CFG_D=${CONFIGS_D}/k6_${STARTTIME}.js
  replace_all ${CONFIGS}/k6.js ${CFG}
  echo "${TESTNAME}: Executing docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-k6 run --vus ${CONCURRENT} --duration ${DURATION}s ${CFG_D} ... "
  _START=`gettimestamp`
  docker run -v ${TESTDIR}:/loadgentest -i loadimpact/loadgentest-k6 run --vus ${CONCURRENT} --duration ${DURATION}s ${CFG_D} > >(tee ${RESULTS}/stdout.log) 2> >(tee ${RESULTS}/stderr.log >&2)
  _END=`gettimestamp`
  _DURATION=`echo "${_END}-${_START}" |bc |stripdecimals`
  # Would be nice to use JSON output here, but the JSON file can be big (and possibly impact performance while it is being written)
  # which means jq takes forever to parse it, so we parse stdout output instead. This, however, will currently fail for sub-millisecond
  # response times because k6 reports times in microseconds then and uses the greek character "my" to signify "micro".
  #jq -c 'select(.type == "Point") | select(.metric == "http_req_duration") | .data.value' ${RESULTS}/output.json >${TMPTIMINGS}
  #_REQUESTS=`wc -l ${TMPTIMINGS} |awk '{print $1}'`
  #_RPS=`echo "scale=0; ${_REQUESTS}/${DURATION};" |bc`
  #_OKREQUESTS=`jq -c 'select(.type == "Point") | select(.metric == "http_req_duration") | select(.data.tags.status == "200")' |wc -l | awk '{print $1}'`
  #_ERRORS=`expr ${_REQUESTS} - ${_OKREQUESTS}`
  #_RTTAVG=`awk 'BEGIN{num=0;tot=0}{num=num+1;tot=tot+$1}END{print tot/num}' ${TMPTIMINGS} |stripdecimals`
  #_RTTMIN=`cat ${TMPTIMINGS} |sort -n |head -1 |awk '{print $1}'`
  #_RTTMAX=`cat ${TMPTIMINGS} |sort -n |tail -1 |awk '{print $1}'`
  #_RTTp50=`cat ${TMPTIMINGS} |percentile 50`
  #_RTTp75=`cat ${TMPTIMINGS} |percentile 75`
  #_RTTp90=`cat ${TMPTIMINGS} |percentile 90`
  #_RTTp95=`cat ${TMPTIMINGS} |percentile 95`
  #_RTTp99=`cat ${TMPTIMINGS} |percentile 99`
  _REQUESTS=`grep "http_reqs" ${RESULTS}/stdout.log |awk '{print $2}'`
  _RPS=`grep "http_reqs" ${RESULTS}/stdout.log |awk '{print $3}' |egrep -o '[0-9]*\.[0-9]*' |toint`
  _ERRORS="-"
  _RTTp75="-"
  _RTTp99="-"
  _RTTAVG=`grep "http_req_duration" ${RESULTS}/stdout.log |awk '{print $2}' |awk -F\= '{print $2}' |duration2ms |stripdecimals`
  _RTTMAX=`grep "http_req_duration" ${RESULTS}/stdout.log |awk '{print $3}' |awk -F\= '{print $2}' |duration2ms |stripdecimals`
  _RTTp50=`grep "http_req_duration" ${RESULTS}/stdout.log |awk '{print $4}' |awk -F\= '{print $2}' |duration2ms |stripdecimals`
  _RTTMIN=`grep "http_req_duration" ${RESULTS}/stdout.log |awk '{print $5}' |awk -F\= '{print $2}' |duration2ms |stripdecimals`
  _RTTp90=`grep "http_req_duration" ${RESULTS}/stdout.log |awk '{print $6}' |awk -F\= '{print $2}' |duration2ms |stripdecimals`
  _RTTp95=`grep "http_req_duration" ${RESULTS}/stdout.log |awk '{print $7}' |awk -F\= '{print $2}' |duration2ms |stripdecimals`
  echo ""
  echo "${TESTNAME} ${_DURATION}s ${_REQUESTS} ${_ERRORS} ${_RPS} ${_RTTMIN} ${_RTTMAX} ${_RTTAVG} ${_RTTp50} ${_RTTp75} ${_RTTp90} ${_RTTp95} ${_RTTp99}" >${TIMINGS}
  report ${TIMINGS} "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "${TESTNAME}: done"
  echo ""
  sleep 3
}


staticurltests() {
  apachebench_static
  hey_static
  wrk_static
  artillery_static
  vegeta_static
  siege_static
  tsung_static
  jmeter_static
  gatling_static
  # Concat all timing files
  LOGDIR=${TESTDIR}/results/${STARTTIME}
  cat ${LOGDIR}/apachebench_static/timings \
      ${LOGDIR}/hey_static/timings \
      ${LOGDIR}/wrk_static/timings \
      ${LOGDIR}/artillery_static/timings \
      ${LOGDIR}/vegeta_static/timings \
      ${LOGDIR}/siege_static/timings \
      ${LOGDIR}/tsung_static/timings \
      ${LOGDIR}/jmeter_static/timings \
      ${LOGDIR}/gatling_static/timings \
      >${LOGDIR}/staticurltests.timings
  echo ""
  echo "---------------------------------------------------------- Static URL test results ------------------------------------------------------------"
  report ${LOGDIR}/staticurltests.timings "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "-----------------------------------------------------------------------------------------------------------------------------------------------"
  echo ""
}

scriptingtests() {
  locust_scripting
  grinder_scripting
  wrk_scripting
  k6_scripting
  # Concat all timing files
  LOGDIR=${TESTDIR}/results/${STARTTIME}
  cat ${LOGDIR}/locust_scripting/timings \
      ${LOGDIR}/grinder_scripting/timings \
      ${LOGDIR}/wrk_scripting/timings \
      ${LOGDIR}/k6_scripting/timings \
      >${LOGDIR}/scriptingtests.timings
  echo ""
  echo "------------------------------------------------------ Dynamic scripting test results --------------------------------------------------------"
  report ${LOGDIR}/scriptingtests.timings "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "----------------------------------------------------------------------------------------------------------------------------------------------"
  echo ""
}

alltests() {
  staticurltests
  scriptingtests
  # Concat all timing files
  LOGDIR=${TESTDIR}/results/${STARTTIME}
  cat ${LOGDIR}/staticurltests.timings \
      ${LOGDIR}/scriptingtests.timings \
      >${LOGDIR}/alltests.timings
  echo ""
  echo "------------------------------------------------------------- All test results ---------------------------------------------------------------"
  report ${LOGDIR}/alltests.timings "Testname Runtime Requests Errors RPS RTTMIN(ms) RTTMAX(ms) RTTAVG(ms) RTT50(ms) RTT75(ms) RTT90(ms) RTT95(ms) RTT99(ms)"
  echo "----------------------------------------------------------------------------------------------------------------------------------------------"
  echo ""
}


clear
while [ 1 ]
do
  export_testvars
  echo ""
  echo "################################################"
  echo "#  Load Impact load generator test suite V2.0  #"
  echo "################################################"
  echo ""
  echo "1. Choose target URL (current: ${TARGETURL})"
  echo "2. Set concurrent requests/VUs (current: ${CONCURRENT})"
  echo "3. Set total number of requests (current: ${REQUESTS})"
  echo "4. Set test duration (current: ${DURATION})"
  echo ""
  echo "R. Add network delay (netem: +${NETWORK_DELAY}ms)"
  if [ "${TARGETHOST}x" != "x" ] ; then
    if [ ! "${PINGTIME}x" = "x" ] ; then
      echo "P. Ping ${TARGETHOST} (last RTT seen: ${PINGTIME}ms)"
    else
      echo "P. Ping ${TARGETHOST}"
    fi
  fi
  echo ""
  echo "5. Run all tests"
  echo "6. Run all static-URL tests"
  echo "7. Run all scripting tests"
  echo ""
  echo "a. Run Apachebench static-URL test"
  echo "b. Run Wrk static-URL test"
  echo "c. Run Hey static-URL test"
  echo "d. Run Artillery static-URL test"
  echo "e. Run Vegeta static-URL test"
  echo "f. Run Siege static-URL test"
  echo "g. Run Tsung static-URL test"
  echo "h. Run Jmeter static-URL test"
  echo "i. Run Gatling static-URL test"
  echo ""
  echo "A. Run Locust dynamic scripting test"
  echo "B. Run Grinder dynamic scripting test"
  echo "C. Run Wrk dynamic scripting test"
  echo "D. Run k6 dynamic scripting test"
  echo ""
  echo "X. Escape to bash"
  echo ""
  echo -n "Select (1-7,a-i,A-D,R,X): "
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
      [ "${TARGETURL}x" != "x" ] && alltests
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
      [ "${TARGETURL}x" != "x" ] && hey_static
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
    i)
      [ "${TARGETURL}x" != "x" ] && gatling_static
      ;;
    A)
      [ "${TARGETURL}x" != "x" ] && locust_scripting
      ;;
    B)
      [ "${TARGETURL}x" != "x" ] && grinder_scripting
      ;;
    C)
      [ "${TARGETURL}x" != "x" ] && wrk_scripting
      ;;
    D)
      [ "${TARGETURL}x" != "x" ] && k6_scripting
      ;;
    R)
      if [ -z $NO_TC ]; then
        echo -n "Enter extra network delay to add (ms) : "
        read ans
        if [ "${NETWORK_DELAY}x" = "0x" ] ; then
          echo "tc qdisc add dev eth0 root netem delay ${ans}ms"
          tc qdisc add dev eth0 root netem delay ${ans}ms
        else
          echo "tc qdisc change dev eth0 root netem delay ${ans}ms"
          tc qdisc change dev eth0 root netem delay ${ans}ms
        fi
        if [ $? -ne 0 ] ; then 
          echo "Failed to set network delay. Try running docker image with --cap-add=NET_ADMIN"
        else
          export NETWORK_DELAY=$ans
        fi
      else
        echo "There is no netem on this machine, so we can't simulate network delay. Sorry."
      fi
      ;;
    P)
      if [ ! "${TARGETHOST}x" = "x" ] ; then
        PINGTIME=`ping -c2 -i.2 ${TARGETHOST} |tail -1 |awk '{print $4}' |awk -F\/ '{print $1}' |stripdecimals`
      fi
      ;;
    X)
      /bin/bash
      ;;
  esac
done
