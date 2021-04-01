#!/bin/bash

source /etc/os-release
if [ -f run.$VERSION_CODENAME.sh ]; then
  source run.$VERSION_CODENAME.sh
else
  source run.focal.sh
fi
