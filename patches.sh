#!/bin/bash
# Build-time patches for the FOG installer so it runs inside a container
# against an external database. ASCII only. Each patch fails the build if its
# target text is not found, so a future FOG release cannot silently skip it.
set -euo pipefail

F=/opt/fog-src/lib/common/functions.sh

# 1) nginx: "listen <server ip>:443" fails in a container because the server
#    IP is not on any local interface. Listen on all addresses, like port 80.
grep -q 'listen \${NET_fog_server_ip}:443 ' "$F"
sed -i 's/listen \${NET_fog_server_ip}:443 /listen 443 /' "$F"
! grep -q 'listen \${NET_fog_server_ip}:443' "$F"

# 2) External DB: configureMySql() returns early in external mode without
#    setting $host / $sqloptionsuser / $sqloptionsroot. Every later
#    "mysql $sqloptionsuser ..." then runs with no --host and tries the local
#    socket /run/mysqld/mysqld.sock. Set them before that early return.
anchor='        # Return early to skip local DB configuration, preserving existing logic'
grep -qF "$anchor" "$F"
awk -v anchor="$anchor" '
    $0 == anchor {
        print "        host=\"--host=${DB_host}${mysqlsslopt:+ $mysqlsslopt}\""
        print "        sqloptionsuser=\"${host} -s --user=${DB_user}\""
        print "        sqloptionsroot=\"${host} --user=root\""
    }
    { print }
' "$F" > "$F.new"
mv "$F.new" "$F"
grep -q 'sqloptionsuser="\${host} -s --user=\${DB_user}"' "$F"

bash -n "$F"
echo "FOG installer patches applied"
