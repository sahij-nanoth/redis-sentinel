#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-redis}"
REDIS_CONF="/opt/redis/conf/redis.conf"
SENTINEL_CONF="/opt/redis/conf/sentinel.conf"
HAPROXY_CONF="/opt/redis/conf/haproxy.cfg"

POD_NAME="${HOSTNAME:-redis-0}"
POD_IP="$(hostname -i | awk '{print $1}')"
NAMESPACE="${POD_NAMESPACE:-redis-sentinel}"
HEADLESS_SERVICE="${REDIS_HEADLESS_SERVICE:-redis-headless}"
SENTINEL_HEADLESS_SERVICE="${SENTINEL_HEADLESS_SERVICE:-sentinel-headless}"
MASTER_NAME="${MASTER_NAME:-mymaster}"
MASTER_HOST="${MASTER_HOST:-redis-0.${HEADLESS_SERVICE}.${NAMESPACE}.svc.cluster.local}"
MASTER_PORT="${MASTER_PORT:-6379}"
QUORUM="${SENTINEL_QUORUM:-2}"

REDIS_SERVER_BIN="$(command -v redis-server || true)"
REDIS_SENTINEL_BIN="$(command -v redis-sentinel || true)"
REDIS_CLI_BIN="$(command -v redis-cli || true)"
HAPROXY_BIN="$(command -v haproxy || true)"

if [[ "${MODE}" == "redis" || "${MODE}" == "sentinel" ]]; then
  if [[ -z "${REDIS_SERVER_BIN}" ]]; then
    echo "redis-server binary not found in PATH"
    exit 1
  fi
fi

if [[ -z "${REDIS_SENTINEL_BIN}" ]]; then
  REDIS_SENTINEL_BIN="${REDIS_SERVER_BIN}"
fi

echo "Starting mode=${MODE} pod=${POD_NAME} ip=${POD_IP} namespace=${NAMESPACE}"

ordinal_from_hostname() {
  local name="$1"
  echo "${name##*-}"
}

wait_for_master() {
  local host="$1"
  local port="$2"
  local retries="${3:-60}"
  local sleep_seconds="${4:-2}"

  if [[ -z "${REDIS_CLI_BIN}" ]]; then
    echo "redis-cli not found; skipping master reachability wait"
    return 0
  fi

  for _ in $(seq 1 "${retries}"); do
    if "${REDIS_CLI_BIN}" -h "${host}" -p "${port}" PING >/dev/null 2>&1; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  echo "Master ${host}:${port} not reachable after retries"
  return 1
}

patch_haproxy_backend_hosts() {
  cp "${HAPROXY_CONF}" /tmp/haproxy.cfg
  sed -i "s/redis-headless\.redis-sentinel\.svc\.cluster\.local/${HEADLESS_SERVICE}.${NAMESPACE}.svc.cluster.local/g" /tmp/haproxy.cfg
}

if [[ "${MODE}" == "redis" ]]; then
  ORDINAL="$(ordinal_from_hostname "${POD_NAME}")"
  cp "${REDIS_CONF}" /tmp/redis.conf

  cat >> /tmp/redis.conf <<EOF2
replica-announce-ip ${POD_NAME}.${HEADLESS_SERVICE}.${NAMESPACE}.svc.cluster.local
replica-announce-port 6379
EOF2

  if [[ "${ORDINAL}" != "0" ]]; then
    wait_for_master "${MASTER_HOST}" "${MASTER_PORT}" || true
    cat >> /tmp/redis.conf <<EOF2
replicaof ${MASTER_HOST} ${MASTER_PORT}
EOF2
  fi

  exec "${REDIS_SERVER_BIN}" /tmp/redis.conf

elif [[ "${MODE}" == "sentinel" ]]; then
  cp "${SENTINEL_CONF}" /tmp/sentinel.conf

  sed -i "s|^sentinel monitor .*|sentinel monitor ${MASTER_NAME} ${MASTER_HOST} ${MASTER_PORT} ${QUORUM}|g" /tmp/sentinel.conf || true

  cat >> /tmp/sentinel.conf <<EOF2
sentinel announce-ip ${POD_NAME}.${SENTINEL_HEADLESS_SERVICE}.${NAMESPACE}.svc.cluster.local
sentinel announce-port 26379
EOF2

  exec "${REDIS_SENTINEL_BIN}" /tmp/sentinel.conf --sentinel

elif [[ "${MODE}" == "haproxy" ]]; then
  if [[ -z "${HAPROXY_BIN}" ]]; then
    echo "haproxy binary not found in PATH"
    exit 1
  fi

  patch_haproxy_backend_hosts
  exec "${HAPROXY_BIN}" -W -db -f /tmp/haproxy.cfg

else
  echo "Unknown mode: ${MODE}"
  exit 1
fi
