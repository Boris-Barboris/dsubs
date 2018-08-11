#!/bin/bash

set -eux
dub build -b debug
LD_LIBRARY_PATH="$LD_LIBRARY_PATH:./arch_libs/" ./dsubs_client
