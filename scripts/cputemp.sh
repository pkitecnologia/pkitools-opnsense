#!/usr/local/bin/bash
/sbin/sysctl dev.cpu.0 | /usr/bin/grep temperature | /usr/bin/grep -o '[0-9]\?[0-9][0-9]\.[0-9]'
