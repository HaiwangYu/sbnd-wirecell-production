#!/bin/bash
# one.sh <idx> <sample> <kind> <file>
source /home/xqian/toolkit-dev/local/bin/thisroot.sh 2>/dev/null
cd "$(dirname "$0")"
/home/xqian/toolkit-dev/local/bin/root -l -b -q "rse_list.C(\"$4\")" 2>/dev/null \
 | awk -v s="$2" -v k="$3" -v f="$(basename "$4")" '$1=="RSE"{print s"\t"k"\t"f"\t"$2"\t"$3"\t"$4"\t"$5}' > rows/$1.tsv
[ -s rows/$1.tsv ] || echo "FAIL $4"
