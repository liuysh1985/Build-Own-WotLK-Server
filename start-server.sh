#!/bin/bash
CURRENT_DIR=$(cd `dirname $0`;pwd)

usage() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]

Bootstrap the WotLK runtime (dirs, conf files, DB password), then launch the
stack with docker compose. --dry-run prints the environment and launch
command instead of starting anything.

Canonical layout (one base dir owns both pieces):
  <base-dir>/azerothcore-wotlk   clone of mod-playerbots/azerothcore-wotlk (Playerbot);
                                 its docker-compose.yml is the compose base file
  <base-dir>/runtime             conf, db, data, logs, db.password

Options:
  --base-dir <dir>           Base directory                      (default: \$HOME/WotLK or \$WOTLK_BASE_DIR)
  --image-tag <tag>          Docker image tag                    (default: master)
  --runtime-dir <dir>        Runtime directory                   (default: <base-dir>/runtime)
  --azerothcore-dir <dir>    azerothcore-wotlk clone directory   (default: <base-dir>/azerothcore-wotlk)
  --db-password-file <file>  DB root password file               (default: <runtime-dir>/db.password)
  --compose-file <file>      Custom base compose file            (default: <azerothcore-dir>/docker-compose.yml;
                               this repo's docker-compose.override.yml is still merged on top)
  --modules-dir <dir>        Bind-mount this host modules dir to ac-worldserver:/azerothcore/modules
                             (skipped entirely when the option is omitted)
  --refresh-conf             Overwrite runtime conf files with the repo's conf/ (repo wins)
  --dry-run                  Print the env block + launch command, start nothing
  -h, --help                 Show this help and exit
EOF
}

DOCKER_IMAGE_TAG=""
BASE_DIR=""
RUNTIME_DIR=""
AZEROOTHCORE_DIR=""
DB_PASSWORD_FILE=""
BASE_COMPOSE_FILE=""
MODULES_DIR=""
REFRESH_CONF=0
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --image-tag)
            DOCKER_IMAGE_TAG="$2"; shift 2 ;;
        --base-dir)
            BASE_DIR="$2"; shift 2 ;;
        --runtime-dir)
            RUNTIME_DIR="$2"; shift 2 ;;
        --azerothcore-dir)
            AZEROOTHCORE_DIR="$2"; shift 2 ;;
        --db-password-file)
            DB_PASSWORD_FILE="$2"; shift 2 ;;
        --compose-file)
            BASE_COMPOSE_FILE="$2"; shift 2 ;;
        --modules-dir)
            MODULES_DIR="$2"; shift 2 ;;
        --refresh-conf)
            REFRESH_CONF=1; shift ;;
        --dry-run)
            DRY_RUN=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1 ;;
    esac
done

if [ -n "${BASE_COMPOSE_FILE}" ]; then
    if [ ! -f "${BASE_COMPOSE_FILE}" ]; then
        echo "Compose file not found: ${BASE_COMPOSE_FILE}" >&2
        exit 1
    fi
    # Normalize to an absolute path so the printed command works from any cwd
    case "${BASE_COMPOSE_FILE}" in
        /*) : ;;
        *) BASE_COMPOSE_FILE="$(cd "$(dirname "${BASE_COMPOSE_FILE}")";pwd)/$(basename "${BASE_COMPOSE_FILE}")" ;;
    esac
fi

if [ -n "${MODULES_DIR}" ]; then
    case "${MODULES_DIR}" in
        /*) : ;;
        *) MODULES_DIR="$(cd "$(dirname "${MODULES_DIR}")" && pwd)/$(basename "${MODULES_DIR}")" ;;
    esac
    if [ ! -d "${MODULES_DIR}" ]; then
        echo "Modules dir not found: ${MODULES_DIR}" >&2
        exit 1
    fi
fi

[ -n "${DOCKER_IMAGE_TAG}" ] || DOCKER_IMAGE_TAG="master"
# One base dir owns both the azerothcore clone and the runtime dir:
#   <base-dir>/azerothcore-wotlk   <base-dir>/runtime
# Explicit --runtime-dir / --azerothcore-dir still win over the derivation.
[ -n "${BASE_DIR}" ] || BASE_DIR="${WOTLK_BASE_DIR:-$HOME/WotLK}"
BASE_DIR="${BASE_DIR/#~/${HOME}}"
case "${BASE_DIR}" in
    /*) : ;;
    *)  BASE_DIR="$(cd "$(dirname "${BASE_DIR}")" 2>/dev/null && pwd)/$(basename "${BASE_DIR}")" ;;
esac
[ -n "${RUNTIME_DIR}" ]      || RUNTIME_DIR="${BASE_DIR}/runtime"
# Resolve after --runtime-dir so the default tracks a custom dir
[ -n "${DB_PASSWORD_FILE}" ] || DB_PASSWORD_FILE="${RUNTIME_DIR}/db.password"
[ -n "${AZEROOTHCORE_DIR}" ] || AZEROOTHCORE_DIR="${BASE_DIR}/azerothcore-wotlk"
case "${AZEROOTHCORE_DIR}" in
    /*) : ;;
    *)  AZEROOTHCORE_DIR="$(cd "$(dirname "${AZEROOTHCORE_DIR}")" 2>/dev/null && pwd)/$(basename "${AZEROOTHCORE_DIR}")" ;;
esac
if [ ! -f "${AZEROOTHCORE_DIR}/docker-compose.yml" ]; then
    echo "AzerothCore clone not found: ${AZEROOTHCORE_DIR}" >&2
    echo "Clone it there (module setup in docs/server.md):" >&2
    echo "  git clone https://github.com/mod-playerbots/azerothcore-wotlk --branch Playerbot --depth 1 ${AZEROOTHCORE_DIR}" >&2
    echo "or point at an existing clone with --azerothcore-dir <dir>" >&2
    exit 1
fi

if [ ! -d "${RUNTIME_DIR}" ];then
    echo "Ensure that the runtime folders exist..."
    mkdir -p ${RUNTIME_DIR}/{conf,db,data,logs}
fi

# Optional modules bind mount for ac-worldserver: generated only when
# --modules-dir is given, and appended last to COMPOSE_FILE (compose merges
# `volumes` additively by container path). Omitted option => no mount at all.
MODULES_COMPOSE_FILE=""
if [ -n "${MODULES_DIR}" ]; then
    MODULES_COMPOSE_FILE="${RUNTIME_DIR}/docker-compose.modules.yml"
    cat > "${MODULES_COMPOSE_FILE}" <<EOF
# Generated by start-server.sh --modules-dir ${MODULES_DIR} — do not edit.
# Merged over the base compose file; adds one bind mount to ac-worldserver.
services:
  ac-worldserver:
    volumes:
      - "${MODULES_DIR}:/azerothcore/modules"
EOF
fi

# Sync template conf files from the repo into the runtime conf dir, recursing
# into subdirs such as conf/modules/.
#   default          : prompt once, copy only files missing in the runtime dir
#   --refresh-conf   : no prompt, repo wins - overwrite files that differ
TEMPLATE_CONF_DIR="${CURRENT_DIR}/conf"
if [ -d "${TEMPLATE_CONF_DIR}" ]; then
    if [ "${REFRESH_CONF}" -eq 1 ]; then
        (cd "${TEMPLATE_CONF_DIR}" && find . -type f) | while read -r REL; do
            if [ -f "${RUNTIME_DIR}/conf/${REL}" ] && cmp -s "${TEMPLATE_CONF_DIR}/${REL}" "${RUNTIME_DIR}/conf/${REL}"; then
                continue
            fi
            mkdir -p "${RUNTIME_DIR}/conf/$(dirname "${REL}")"
            cp "${TEMPLATE_CONF_DIR}/${REL}" "${RUNTIME_DIR}/conf/${REL}"
            echo "  refreshed ${REL#./}"
        done
    else
        MISSING_CONF=$(cd "${TEMPLATE_CONF_DIR}" && find . -type f | while read -r REL; do
            [ -f "${RUNTIME_DIR}/conf/${REL}" ] || echo "${REL}"
        done)
        if [ -n "${MISSING_CONF}" ]; then
            printf "Copy %s/* into %s/conf? [Y/n] " "${TEMPLATE_CONF_DIR}" "${RUNTIME_DIR}"
            read -r ANSWER || ANSWER="y"   # no TTY: default yes on first-time copy
            case "${ANSWER}" in
                [nN]*)
                    echo "Skipped copying conf templates." ;;
                *)
                    echo "${MISSING_CONF}" | while read -r REL; do
                        mkdir -p "${RUNTIME_DIR}/conf/$(dirname "${REL}")"
                        cp "${TEMPLATE_CONF_DIR}/${REL}" "${RUNTIME_DIR}/conf/${REL}"
                        echo "  copied  ${REL#./}"
                    done ;;
            esac
        fi
    fi
fi

export DOCKER_AC_ENV_FILE="${RUNTIME_DIR}/conf/env.ac"
export MYSQL_CNF="${RUNTIME_DIR}/conf/mysql.cnf"

DOCKER_VOL_DB="${RUNTIME_DIR}/db"
DOCKER_VOL_ETC="${RUNTIME_DIR}/conf"
DOCKER_VOL_LOGS="${RUNTIME_DIR}/logs"
DOCKER_VOL_DATA="${RUNTIME_DIR}/data"
DOCKER_DB_ROOT_PASSWORD=""

if [ "${DB_PASSWORD_FILE}" == "" ] || [ ! -f ${DB_PASSWORD_FILE} ];then
    echo "Couldn't find the ${DB_PASSWORD_FILE}, will generate a new one and put it into the file"
    DOCKER_DB_ROOT_PASSWORD=`openssl rand -base64 24`
    echo -n ${DOCKER_DB_ROOT_PASSWORD} > ${DB_PASSWORD_FILE}
else
    DOCKER_DB_ROOT_PASSWORD=`cat ${DB_PASSWORD_FILE}`
fi

export DOCKER_IMAGE_TAG DOCKER_VOL_DB DOCKER_VOL_ETC DOCKER_VOL_LOGS DOCKER_VOL_DATA DOCKER_DB_ROOT_PASSWORD

echo ""
echo "Base dir    : ${BASE_DIR}"
echo "Runtime dir : ${RUNTIME_DIR}"
echo "AzerothCore : ${AZEROOTHCORE_DIR}"
echo "Image tag   : ${DOCKER_IMAGE_TAG}"
echo "DB password : ${DB_PASSWORD_FILE}"
if [ -n "${BASE_COMPOSE_FILE}" ]; then
    echo "Base compose: ${BASE_COMPOSE_FILE}"
fi
# Compose layering: clone's base file + this repo's override + the generated
# modules file last (compose merges `volumes` additively by container path).
COMPOSE_PROJECT_NAME="wotlk"
COMPOSE_FILES="${BASE_COMPOSE_FILE:-${AZEROOTHCORE_DIR}/docker-compose.yml}"
if [ -f "${CURRENT_DIR}/docker-compose.override.yml" ]; then
    COMPOSE_FILES="${COMPOSE_FILES}:${CURRENT_DIR}/docker-compose.override.yml"
fi
if [ -n "${MODULES_COMPOSE_FILE}" ]; then
    COMPOSE_FILES="${COMPOSE_FILES}:${MODULES_COMPOSE_FILE}"
    echo "Modules     : ${MODULES_DIR} -> ac-worldserver:/azerothcore/modules"
fi

if [ "${DRY_RUN}" -eq 1 ]; then
    echo ""
    echo "Dry run — would launch with:"
    echo ""
    echo "  export DOCKER_IMAGE_TAG=\"${DOCKER_IMAGE_TAG}\" \\"
    echo "         DOCKER_AC_ENV_FILE=\"${DOCKER_AC_ENV_FILE}\" \\"
    echo "         MYSQL_CNF=\"${MYSQL_CNF}\" \\"
    echo "         DOCKER_VOL_DB=\"${DOCKER_VOL_DB}\" \\"
    echo "         DOCKER_VOL_ETC=\"${DOCKER_VOL_ETC}\" \\"
    echo "         DOCKER_VOL_LOGS=\"${DOCKER_VOL_LOGS}\" \\"
    echo "         DOCKER_VOL_DATA=\"${DOCKER_VOL_DATA}\" \\"
    echo "         DOCKER_DB_ROOT_PASSWORD=\"\$(cat ${DB_PASSWORD_FILE})\""
    echo "  export COMPOSE_PROJECT_NAME=\"${COMPOSE_PROJECT_NAME}\" \\"
    echo "         COMPOSE_FILE=\"${COMPOSE_FILES}\""
    echo "  cd ${AZEROOTHCORE_DIR} && docker compose up -d"
    exit 0
fi

# Export in this process only: inherited by the compose child, never printed.
export COMPOSE_PROJECT_NAME COMPOSE_FILE="${COMPOSE_FILES}"

echo ""
echo "Launching '${COMPOSE_PROJECT_NAME}' stack from ${AZEROOTHCORE_DIR}..."
cd "${AZEROOTHCORE_DIR}" || exit 1
docker compose up -d
STATUS=$?
if [ "${STATUS}" -ne 0 ]; then
    echo "docker compose up failed (exit ${STATUS})" >&2
    exit "${STATUS}"
fi
echo ""
docker compose ps
echo ""
echo "  follow logs : docker compose logs -f ac-worldserver   # first boot: ac-db-import is slow, world/auth wait on it"
echo "  RAS console : docker compose attach ac-worldserver    # detach: Ctrl-P then Ctrl-Q"
echo "  stop        : bash ${CURRENT_DIR}/stop-server.sh      # add --down to also remove containers"
exit 0
