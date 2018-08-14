#!/bin/bash

set -eux
dub build -b debug
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:./arch_libs/"
export ALSOFT_CONF="./alsoft.ini"
./dsubs_client
