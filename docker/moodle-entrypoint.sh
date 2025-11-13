#!/usr/bin/env bash
set -euo pipefail

REDIS_HOST=${REDIS_HOST:-redis}
REDIS_PORT=${REDIS_PORT:-6379}
REDIS_DB=${REDIS_DB:-0}
REDIS_TIMEOUT=${REDIS_TIMEOUT:-2.5}
REDIS_READ_TIMEOUT=${REDIS_READ_TIMEOUT:-2.5}
REDIS_SESSION_LOCKING=${REDIS_SESSION_LOCKING:-1}
REDIS_SESSION_LOCK_RETRIES=${REDIS_SESSION_LOCK_RETRIES:-200}
REDIS_SESSION_LOCK_WAIT=${REDIS_SESSION_LOCK_WAIT:-20000}
REDIS_PCONNECT_POOLING=${REDIS_PCONNECT_POOLING:-1}
ENABLE_REDIS_SESSION=${ENABLE_REDIS_SESSION:-1}

configure_redis_session() {
    local php_conf_dir="/usr/local/etc/php/conf.d"
    local redis_ini="${php_conf_dir}/redis-session.ini"

    if [[ "${ENABLE_REDIS_SESSION}" != "1" ]]; then
        rm -f "${redis_ini}"
        return
    fi

    local session_path="tcp://${REDIS_HOST}:${REDIS_PORT}?persistent=1&weight=1&timeout=${REDIS_TIMEOUT}&read_timeout=${REDIS_READ_TIMEOUT}&database=${REDIS_DB}"
    if [[ -n "${REDIS_PASSWORD:-}" ]]; then
        session_path="${session_path}&auth=${REDIS_PASSWORD}"
    fi

    cat > "${redis_ini}" <<EOF
session.save_handler = redis
session.save_path = "${session_path}"
redis.session.locking_enabled = ${REDIS_SESSION_LOCKING}
redis.session.lock_retries = ${REDIS_SESSION_LOCK_RETRIES}
redis.session.lock_wait_time = ${REDIS_SESSION_LOCK_WAIT}
redis.pconnect.pooling_enabled = ${REDIS_PCONNECT_POOLING}
EOF
}

configure_redis_session

service cron start

exec docker-php-entrypoint "$@"
