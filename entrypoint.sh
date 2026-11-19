#!/bin/bash
# FOG container entrypoint (ASCII only).
# First boot of a container: write /opt/fog/.fogsettings and run the official
# installer unattended against the EXTERNAL database container.
# Later restarts of the same container: just start the services again.

set -u

: "${FOG_IP:?FOG_IP must be set to the LAN IP of the Docker host (what PXE clients can reach)}"
: "${DB_HOST:=db}"
: "${DB_NAME:=fog}"
: "${DB_USER:=fogmaster}"
: "${DB_PASSWORD:?DB_PASSWORD must be set}"
: "${NET_INTERFACE:=eth0}"

MARKER=/var/lib/.fog-installed
SETTINGS=/opt/fog/.fogsettings

setup_openrc() {
    mkdir -p /run/openrc /var/run/fog
    touch /run/openrc/softlevel
    openrc >/dev/null 2>&1 || true
}

wait_for_db() {
    echo " * Waiting for database at ${DB_HOST}:3306"
    for i in $(seq 1 60); do
        (echo > /dev/tcp/"${DB_HOST}"/3306) >/dev/null 2>&1 && return 0
        sleep 2
    done
    echo "Database did not come up in time" >&2
    exit 1
}

write_settings() {
    mkdir -p /opt/fog
    # Key names are the 1.6.0 CATEGORY_lower_snake_case names.
    # Anything not listed here is defaulted by the installer (-y).
    # If .fogsettings already exists (persisted volume) it is an UPGRADE:
    # only refresh the values that must follow the container environment.
    if [ -f "$SETTINGS" ]; then
        for kv in "NET_fog_server_ip=${FOG_IP}" "NET_interface=${NET_INTERFACE}" \
                  "DB_host=${DB_HOST}" "DB_name=${DB_NAME}" "DB_user=${DB_USER}" \
                  "DB_password=${DB_PASSWORD}" "DB_external=yes"; do
            key="${kv%%=*}"; val="${kv#*=}"
            sed -i "/^${key}=/d" "$SETTINGS"
            printf "%s='%s'\n" "$key" "$val" >> "$SETTINGS"
        done
        return
    fi
    cat > "$SETTINGS" <<EOF
FOG_install_type='N'
NET_interface='${NET_INTERFACE}'
NET_fog_server_ip='${FOG_IP}'
DHCP_enabled='0'
DB_host='${DB_HOST}'
DB_name='${DB_NAME}'
DB_user='${DB_USER}'
DB_password='${DB_PASSWORD}'
DB_external='yes'
STORAGE_image_share_path='/images'
PKI_san_dns_names='${FOG_SAN_NAMES:-fogserver}'
EOF
}

first_boot_install() {
    wait_for_db
    write_settings
    cd /opt/fog-src/bin || exit 1
    ./installfog.sh -y --install-mode standard
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "FOG installer failed (exit $rc). See /opt/fog-src/bin/error_logs/" >&2
        tail -n 40 /opt/fog-src/bin/error_logs/* 2>/dev/null
        exit $rc
    fi
    touch "$MARKER"
}

start_services() {
    for s in nginx php-fpm* in.tftpd vsftpd rpcbind nfs FOG*; do
        for f in /etc/init.d/$s; do
            [ -x "$f" ] && rc-service "$(basename "$f")" start >/dev/null 2>&1
        done
    done
}

setup_openrc

if [ ! -f "$MARKER" ]; then
    first_boot_install
else
    wait_for_db
    start_services
fi

echo " * FOG is up. Web UI: https://${FOG_IP}/fog/management"

# Keep PID 1 alive and forward stop signals
trap 'exit 0' TERM INT
while true; do sleep 3600 & wait $!; done