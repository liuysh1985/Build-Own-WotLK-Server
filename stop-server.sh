#!/bin/bash
CURRENT_DIR=$(cd `dirname $0`;pwd)

usage() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]

Stop the 'wotlk' compose stack launched by start-server.sh.
Default: 'docker compose stop' — containers stop but stay defined.
--down also removes the containers. All persistent state lives in
<base-dir>/runtime (bind mounts), so neither mode touches your data.

Canonical layout (same as start-server.sh):
  <base-dir>/azerothcore-wotlk   clone whose docker-compose.yml is the compose base
  <base-dir>/runtime             conf, db, data, logs, db.password

Options:
  --base-dir <dir>           Base directory                      (default: \$HOME/WotLK or \$WOTLK_BASE_DIR)
  --azerothcore-dir <dir>    azerothcore-wotlk clone directory   (default: <base-dir>/azerothcore-wotlk)
  --compose-file <file>      Custom base compose file            (default: <azerothcore-dir>/docker-compose.yml)
  --down                     docker compose down instead of stop
  --dry-run                  Print the command without running it
  -h, --help                 Show this help and exit
EOF
}

BASE_DIR=""
AZEROOTHCORE_DIR=""
BASE_COMPOSE_FILE=""
ACTION="stop"
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --base-dir)
            BASE_DIR="$2"; shift 2 ;;
        --azerothcore-dir)
            AZEROOTHCORE_DIR="$2"; shift 2 ;;
        --compose-file)
            BASE_COMPOSE_FILE="$2"; shift 2 ;;
        --down)
            ACTION="down"; shift ;;
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

[ -n "${BASE_DIR}" ] || BASE_DIR="${WOTLK_BASE_DIR:-$HOME/WotLK}"
BASE_DIR="${BASE_DIR/#~/${HOME}}"
case "${BASE_DIR}" in
    /*) : ;;
    *)  BASE_DIR="$(cd "$(dirname "${BASE_DIR}")" 2>/dev/null && pwd)/$(basename "${BASE_DIR}")" ;;
esac
[ -n "${AZEROOTHCORE_DIR}" ] || AZEROOTHCORE_DIR="${BASE_DIR}/azerothcore-wotlk"
case "${AZEROOTHCORE_DIR}" in
    /*) : ;;
    *)  AZEROOTHCORE_DIR="$(cd "$(dirname "${AZEROOTHCORE_DIR}")" 2>/dev/null && pwd)/$(basename "${AZEROOTHCORE_DIR}")" ;;
esac
if [ -n "${BASE_COMPOSE_FILE}" ]; then
    if [ ! -f "${BASE_COMPOSE_FILE}" ]; then
        echo "Compose file not found: ${BASE_COMPOSE_FILE}" >&2
        exit 1
    fi
    case "${BASE_COMPOSE_FILE}" in
        /*) : ;;
        *) BASE_COMPOSE_FILE="$(cd "$(dirname "${BASE_COMPOSE_FILE}")";pwd)/$(basename "${BASE_COMPOSE_FILE}")" ;;
    esac
fi
AZ_BASE_COMPOSE="${BASE_COMPOSE_FILE:-${AZEROOTHCORE_DIR}/docker-compose.yml}"
if [ ! -f "${AZ_BASE_COMPOSE}" ]; then
    echo "Base compose file not found: ${AZ_BASE_COMPOSE}" >&2
    echo "Point at the clone or a custom file with --azerothcore-dir/--compose-file" >&2
    exit 1
fi

# Same layering as start-server.sh (stop needs no password or runtime conf).
# The LLM layer is always included when present so stop/down also reap ac-llm
# even if the stack was launched without --with-llm awareness; a stack
# without ac-llm simply ignores it. The generated modules file (start-server.sh
# always writes it) is included when present at the default runtime path; it
# is volumes-only, so a custom --runtime-dir missing it is equally fine.
RUNTIME_DIR="${BASE_DIR}/runtime"
COMPOSE_PROJECT_NAME="wotlk"
COMPOSE_FILES="${AZ_BASE_COMPOSE}"
if [ -f "${CURRENT_DIR}/docker-compose.override.yml" ]; then
    COMPOSE_FILES="${COMPOSE_FILES}:${CURRENT_DIR}/docker-compose.override.yml"
fi
if [ -f "${CURRENT_DIR}/docker-compose.llm.yml" ]; then
    COMPOSE_FILES="${COMPOSE_FILES}:${CURRENT_DIR}/docker-compose.llm.yml"
fi
if [ -f "${RUNTIME_DIR}/docker-compose.modules.yml" ]; then
    COMPOSE_FILES="${COMPOSE_FILES}:${RUNTIME_DIR}/docker-compose.modules.yml"
fi

export COMPOSE_PROJECT_NAME COMPOSE_FILE="${COMPOSE_FILES}"

if [ "${DRY_RUN}" -eq 1 ]; then
    echo "Dry run — would run:"
    echo ""
    echo "  export COMPOSE_PROJECT_NAME=\"${COMPOSE_PROJECT_NAME}\" \\"
    echo "         COMPOSE_FILE=\"${COMPOSE_FILES}\""
    echo "  cd ${AZEROOTHCORE_DIR} && docker compose ${ACTION}"
    exit 0
fi

echo "Stopping '${COMPOSE_PROJECT_NAME}' stack (${ACTION}) from ${AZEROOTHCORE_DIR}..."
cd "${AZEROOTHCORE_DIR}" || exit 1
docker compose "${ACTION}"
STATUS=$?
if [ "${STATUS}" -ne 0 ]; then
    echo "docker compose ${ACTION} failed (exit ${STATUS})" >&2
    exit "${STATUS}"
fi
echo ""
echo "Remaining containers:"
docker compose ps
exit 0
