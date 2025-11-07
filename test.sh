#!/bin/bash

# test on bash(2025_11_07)

set -euo pipefail

SLOW_RESULT_FILE="/MARIA_LOG/slow/mysql-slow-query.log"

CURRENT_MONTH="$(date +%Y-%m)"
LAST_MONTH="$(date -d 'last month' +%Y-%m)"
TWO_MONTHS_AGO="$(date -d '2 months ago' +%Y-%m)"

RE_DASH='[0-9]{4}-[0-9]{2}-[0-9]{2}'
RE_COMPACT='[0-9]{8}'

count_current=$(grep -E "(${CURRENT_MONTH}|${CURRENT_MONTH//-/})" "$SLOW_RESULT_FILE" \
                | grep -Eo "(${RE_DASH}|${RE_COMPACT})" \
                | grep -E "^(${CURRENT_MONTH}|${CURRENT_MONTH//-/})" \
                | wc -l)

count_last=$(grep -E "(${LAST_MONTH}|${LAST_MONTH//-/})" "$SLOW_RESULT_FILE" \
             | grep -Eo "(${RE_DASH}|${RE_COMPACT})" \
             | grep -E "^(${LAST_MONTH}|${LAST_MONTH//-/})" \
             | wc -l)

count_twoago=$(grep -E "(${TWO_MONTHS_AGO}|${TWO_MONTHS_AGO//-/})" "$SLOW_RESULT_FILE" \
               | grep -Eo "(${RE_DASH}|${RE_COMPACT})" \
               | grep -E "^(${TWO_MONTHS_AGO}|${TWO_MONTHS_AGO//-/})" \
               | wc -l)

echo "파일명: $SLOW_RESULT_FILE"
echo "Number of SLOW LOG $CURRENT_MONTH :  $count_current"
echo "Number of SLOW LOG $LAST_MONTH :  $count_last"
echo "Number of SLOW LOG $TWO_MONTHS_AGO :  $count_twoago"
