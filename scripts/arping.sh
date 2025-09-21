#!/usr/local/bin/bash
INTERFACE="$1"
DESTINATION="$2"
PINGPARAM="-w 1 -q -i ${INTERFACE} ${DESTINATION}"
! /pkitools/scripts/arping.bin ${PINGPARAM}
echo $?
