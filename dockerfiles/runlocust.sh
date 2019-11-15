#!/bin/bash

CPU_COUNT=$(grep ^cpu\\scores /proc/cpuinfo | uniq |  awk '{print $4}')

echo CPU count: $CPU_COUNT
for i in $( seq 1 $CPU_COUNT )
do
    (locust -f $LOCUST_FILE --slave &) 2> /dev/null
done

locust -f $LOCUST_FILE --no-web -H $LOCUST_HOST -c $LOCUST_COUNT -r $LOCUST_HATCH_RATE -t=$LOCUST_DURATION --master --expect-slaves=$CPU_COUNT
