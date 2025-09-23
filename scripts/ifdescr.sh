#!/bin/sh
# FreeBSD LLD: discover only interfaces that have an IP and a description,
# and emit {IFNAME} + {IFDESCR} where the description has any final " (xxx)" removed.

# Set PATH to ensure all commands are available
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# List interfaces (skip loopback by default)
iflist=$(ifconfig -l | tr ' ' '\n' | grep -v '^lo0$')

first=1
printf '['

for ifc in $iflist; do
  # Has at least one IPv4/IPv6?
  has_ip=$(
    ifconfig "$ifc" | awk '
      /^[ \t]*inet6[ \t]/ || /^[ \t]*inet[ \t]/ { ip=1 }
      END { if (ip) print "yes" }'
  )
  [ "$has_ip" = "yes" ] || continue

  # Grab description (accept "description:" or "descr:")
  descr=$(
    ifconfig "$ifc" | awk '
      /^[ \t]*(descr(iption)?):[ \t]*/ {
        sub(/^[ \t]*(descr(iption)?):[ \t]*/, "", $0);
        print; exit
      }'
  )
  # Skip if empty
  [ -n "$descr" ] || continue

  # Strip a trailing " (role)" suffix, e.g. "WAN (wan)" -> "WAN"
  # (only removes a parenthetical at the very end)
  clean_descr=$(printf '%s' "$descr" | sed -E 's/[[:space:]]*\([^()]*\)$//')

  # JSON-escape quotes and backslashes
  esc_descr=$(printf '%s' "$clean_descr" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

  if [ $first -eq 0 ]; then printf ','; fi
  first=0
  printf '{"interface_name":"%s","interface_description":"%s"}' "$ifc" "$esc_descr"
done

printf ']\n'
