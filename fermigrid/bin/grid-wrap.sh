#!/bin/bash
# WC_WRAP on a FermiGrid worker: the job already runs inside the SL7 image (+SingularityImage), so
# only the (relocated) run setup is sourced -- run_pair.py passes it as SL7_SETUP -- in the same
# shell as the command (setup-dlvtx.sh needs the path-prepend function).
source "${SL7_SETUP:?}" >/dev/null 2>&1
exec "$@"
