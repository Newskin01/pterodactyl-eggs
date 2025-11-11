#!/bin/bash
# Farming Simulator 25 install bootstrap for Pterodactyl
# Server files live under /mnt/server (mounted to /home/container at runtime)

set -euo pipefail

apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl unzip
rm -rf /var/lib/apt/lists/*

BASE_DIR="/mnt/server"
SCRIPT_DIR="${BASE_DIR}/scripts"
DATA_ROOT="${BASE_DIR}/fs-data"
LOG_DIR="${BASE_DIR}/logs"

mkdir -p "${SCRIPT_DIR}" "${DATA_ROOT}" "${LOG_DIR}"

for path in config game dlc installer backups; do
    mkdir -p "${DATA_ROOT}/${path}"
done

cat <<'MEDIA' > "${BASE_DIR}/FS25_MEDIA_README.txt"
===================================================================================================
Farming Simulator 25 media checklist
===================================================================================================
1. Log into https://eshop.giants-software.com/profile/downloads using the account that owns your FS25 
   dedicated server license.
2. Download the official installer (FarmingSimulator2025.exe) and any DLC/expansion executables.
3. Upload the base installer into /home/container/fs-data/installer/ via the Pterodactyl file manager or SFTP.
4. Upload each DLC executable into /home/container/fs-data/dlc/.
5. Restart the server. The container will automatically pick them up and run the setup script.

You can import this egg and boot the server before the downloads finish. The VNC desktop will simply show a
"media pending" notice until the files arrive.
===================================================================================================
MEDIA

# Bootstrap runtime script that prepares the Arch container before invoking the upstream entrypoint
cat <<'BOOTSTRAP' > "${SCRIPT_DIR}/bootstrap.sh"
#!/bin/bash
set -euo pipefail

LOG_DIR="/home/container/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/bootstrap.log"

log() {
    local timestamp line
    timestamp=$(date -Is)
    line="[fs25-bootstrap] ${timestamp} - $*"
    echo "${line}"
    echo "${line}" >> "${LOG_FILE}"
}

log_section() {
    log "=================================================="
    log "$*"
    log "=================================================="
}

trap 'log "Fatal error (exit $?) at line $LINENO"; exit 1' ERR

is_sensitive_key() {
    case "$1" in
        SERVER_PASSWORD|SERVER_ADMIN|SERVER_ADMIN_PASSWORD|VNC_PASSWORD|WEB_PASSWORD|WEB_ADMIN_PASSWORD)
            return 0
            ;;
    esac
    return 1
}

mask_value() {
    local key="$1"
    local value="$2"
    if is_sensitive_key "${key}"; then
        echo "<hidden>"
    else
        echo "${value}"
    fi
}

have_installer() {
    if compgen -G "${INSTALLER_GLOB}" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

first_installer_path() {
    compgen -G "${INSTALLER_GLOB}" 2>/dev/null | head -n 1 || true
}

DATA_ROOT="/home/container/fs-data"
SCRIPT_DIR="/home/container/scripts"
MEDIA_README="/home/container/FS25_MEDIA_README.txt"
WEB_PORT="${WEB_PORT:-8443}"
WEB_SCHEME="${WEB_SCHEME:-http}"
ENABLE_STARTUP_SCRIPTS="${ENABLE_STARTUP_SCRIPTS:-no}"
GAME_PORT="${SERVER_PORT:-10823}"
HEALTH_LOG="/home/container/logs/healthcheck.log"
HEALTH_FLAG="/tmp/fs25_health_ready"
INSTALLER_GLOB="${DATA_ROOT}/installer/FarmingSimulator2025*.exe"
PORTAL_LOGO_ENFORCER_SLEEP="${PORTAL_LOGO_ENFORCER_SLEEP:-30}"

mkdir -p "${DATA_ROOT}" "${SCRIPT_DIR}" "$(dirname "${HEALTH_LOG}")"
for path in config game dlc installer backups; do
    mkdir -p "${DATA_ROOT}/${path}"
done

ensure_opt_mount() {
    local target="/opt/fs25"
    if [[ -L "${target}" ]]; then
        local current
        current=$(readlink "${target}")
        if [[ "${current}" == "${DATA_ROOT}" ]]; then
            log "Verified /opt/fs25 already points at ${DATA_ROOT}"
            return
        fi
        log "/opt/fs25 symlink points to ${current}, retargeting"
        rm -f "${target}"
    elif [[ -e "${target}" ]]; then
        if [[ -d "${target}" ]]; then
            log "Migrating existing ${target} contents into persistent tree"
            cp -a "${target}/." "${DATA_ROOT}/"
        fi
        rm -rf "${target}"
    fi
    ln -s "${DATA_ROOT}" "${target}"
    log "Symlinked /opt/fs25 -> ${DATA_ROOT}"
}

patch_port_in_file() {
    local file="$1"
    local port="$2"
    [[ -f "${file}" ]] || return 0
    if grep -q '<webserver port="' "${file}"; then
        sed -i "s/<webserver port=\"[0-9][0-9]*\"/<webserver port=\"${port}\"/" "${file}"
        log "Updated web port to ${port} in ${file}"
    fi
}

patch_web_shortcut() {
    local shortcut="/home/nobody/Desktop/Webpanel.desktop"
    [[ -f "${shortcut}" ]] || return 0
    sed -i "s#http://0.0.0.0:[0-9][0-9]*#http://0.0.0.0:${WEB_PORT}#" "${shortcut}"
    log "Patched desktop shortcut to use port ${WEB_PORT}"
}

summarise_media_state() {
    if have_installer; then
        rm -f "${DATA_ROOT}/.media_pending"
        log "Installer detected at $(first_installer_path)"
    else
        printf "WARNING: FarmingSimulator2025.exe not found. Upload it to %s/installer/.\n" "${DATA_ROOT}" > "${DATA_ROOT}/.media_pending"
        log "Installer missing - waiting for upload to ${DATA_ROOT}/installer"
    fi
}

wait_for_media() {
    if have_installer; then
        return
    fi

    log_section "MEDIA PENDING"
    log "Panel will keep this container running until the installer arrives."
    if [[ -f "${MEDIA_README}" ]]; then
        log "Media checklist:"
        while IFS= read -r line; do
            log "  $line"
        done < "${MEDIA_README}"
    fi

    local attempts=0
    while ! have_installer; do
        attempts=$((attempts + 1))
        log "Still waiting for installer (check #${attempts})"
        sleep 30
    done

    summarise_media_state
    log "Installer detected; continuing with normal startup."
}

mask_upstream_secrets() {
    local init="/usr/local/bin/init.sh"
    [[ -f "${init}" ]] || return
    python3 - "$init" <<"PY"
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
data = path.read_text()
patterns = [
    (r"VNC_PASSWORD defined as '.*?'", "VNC_PASSWORD defined as '<hidden>'"),
    (r"WEB_PASSWORD defined as '.*?'", "WEB_PASSWORD defined as '<hidden>'"),
]
new = data
for pattern, replacement in patterns:
    new = re.sub(pattern, replacement, new)
if new != data:
    path.write_text(new)
PY
}

bridge_env_vars() {
    log_section "ENV VAR BRIDGE"
    while IFS='=' read -r legacy mapped; do
        [[ -z "${legacy}" || -z "${mapped}" ]] && continue
        value="$(printenv "${mapped}" 2>/dev/null || true)"
        if [[ -z "${value}" ]]; then
            log "${mapped} not set; skipping"
            continue
        fi
        export "${legacy}=${value}"
        log "Mapped ${mapped} -> ${legacy} ($(mask_value "${legacy}" "${value}"))"
    done <<'MAP'
SERVER_NAME=FS25_SERVER_NAME
SERVER_PASSWORD=FS25_SERVER_PASSWORD
SERVER_ADMIN=FS25_SERVER_ADMIN
SERVER_PLAYERS=FS25_SERVER_PLAYERS
SERVER_REGION=FS25_SERVER_REGION
SERVER_DIFFICULTY=FS25_SERVER_DIFFICULTY
SERVER_PAUSE=FS25_SERVER_PAUSE
SERVER_SAVE_INTERVAL=FS25_SERVER_SAVE_INTERVAL
SERVER_STATS_INTERVAL=FS25_SERVER_STATS_INTERVAL
SERVER_CROSSPLAY=FS25_SERVER_CROSSPLAY
SERVER_MAP=FS25_SERVER_MAP
MAP
}

start_health_monitor() {
    if [[ -x "${SCRIPT_DIR}/healthcheck.sh" ]]; then
        nohup bash "${SCRIPT_DIR}/healthcheck.sh" > "${HEALTH_LOG}" 2>&1 &
        log "Health monitor started (PID $!) -> ${HEALTH_LOG}"
    else
        log "healthcheck.sh missing or not executable"
    fi
}

apply_web_port_overrides() {
    log_section "PATCH WEB PORT"
    local template="/home/nobody/.build/fs25/default_dedicatedServer.xml"
    patch_port_in_file "${template}" "${WEB_PORT}"

    if [[ -d "/home/nobody/.fs25server" ]]; then
        while IFS= read -r -d '' file; do
            patch_port_in_file "${file}" "${WEB_PORT}"
        done < <(find /home/nobody/.fs25server -type f -name 'dedicatedServer*.xml' -print0)
    fi

    patch_web_shortcut
}

sync_portal_logos() {
    local upload_dir="${DATA_ROOT}/media"
    local template_targets=()
    local runtime_template="/home/container/runtime/home/.fs25server/drive_c/Program Files (x86)/Farming Simulator 2025/dedicated_server/webroot/template"
    local legacy_template="/home/nobody/.fs25server/drive_c/Program Files (x86)/Farming Simulator 2025/dedicated_server/webroot/template"
    local persistent_template="${DATA_ROOT}/game/Farming Simulator 2025/dedicated_server/webroot/template"
    local config_template="${DATA_ROOT}/config/FarmingSimulator2025/dedicated_server/webroot/template"
    local web_data_template="${DATA_ROOT}/game/Farming Simulator 2025/web_data/template"

    mkdir -p "${upload_dir}"

    if [[ -n "${runtime_template}" ]]; then
        template_targets+=("${runtime_template}")
    fi
    if [[ -d "/home/nobody/.fs25server" && "${legacy_template}" != "${runtime_template}" ]]; then
        template_targets+=("${legacy_template}")
    fi
    if [[ -n "${persistent_template}" ]]; then
        template_targets+=("${persistent_template}")
    fi
    if [[ -n "${config_template}" ]]; then
        template_targets+=("${config_template}")
    fi
    if [[ -n "${web_data_template}" ]]; then
        template_targets+=("${web_data_template}")
    fi

    if ((${#template_targets[@]} == 0)); then
        log "No dedicated_server template directories detected; skipping portal logo sync"
        return
    fi

    choose_logo_filename() {
        local env_name="$1"
        local explicit_value="$2"
        shift 2
        local patterns=("$@")
        if [[ -n "${explicit_value}" ]]; then
            echo "${explicit_value}"
            return 0
        fi
        local candidate=""
        for pattern in "${patterns[@]}"; do
            candidate=$(find "${upload_dir}" -maxdepth 1 -type f -iname "${pattern}" -print -quit 2>/dev/null || true)
            if [[ -n "${candidate}" ]]; then
                candidate=$(basename "${candidate}")
                log "${env_name} not set; auto-selected ${candidate} from ${upload_dir}"
                echo "${candidate}"
                return 0
            fi
        done
        return 1
    }

    local login_file
    login_file=$(choose_logo_filename "WEB_PORTAL_LOGIN_LOGO" "${WEB_PORTAL_LOGIN_LOGO:-}" "login.*" "main.*" "logo.*") || login_file=""
    local footer_file
    footer_file=$(choose_logo_filename "WEB_PORTAL_FOOTER_LOGO" "${WEB_PORTAL_FOOTER_LOGO:-}" "footer.*" "bottom.*" "logo-footer.*") || footer_file=""

    if [[ -z "${login_file}" && -z "${footer_file}" ]]; then
        log "Portal logo filenames not provided and no recognizable media found under ${upload_dir}; skipping branding sync"
        return
    fi

    local rel_variants=("jpg" "png")
    deploy_logo_file() {
        local src_path="$1"
        local dest_stub="$2"
        local copied=0
        [[ -f "${src_path}" ]] || return 1
        for target in "${template_targets[@]}"; do
            mkdir -p "${target}"
            for ext in "${rel_variants[@]}"; do
                local rel="${dest_stub}.${ext}"
                local dest="${target}/${rel}"
                if [[ -e "${dest}" ]]; then
                    local src_real dest_real
                    src_real=$(readlink -f "${src_path}" 2>/dev/null || echo "${src_path}")
                    dest_real=$(readlink -f "${dest}" 2>/dev/null || echo "${dest}")
                    if [[ "${src_real}" == "${dest_real}" ]]; then
                        copied=1
                        continue
                    fi
                    if cmp -s "${src_real}" "${dest_real}" 2>/dev/null; then
                        copied=1
                        continue
                    fi
                fi
                if cp -f "${src_path}" "${dest}"; then
                    copied=1
                else
                    log "Failed to copy ${src_path} into ${dest}"
                fi
            done
        done
        if ((copied)); then
            return 0
        fi
        return 1
    }

    configure_portal_xml() {
        local cfg="${DATA_ROOT}/game/Farming Simulator 2025/dedicatedServer.xml"
        [[ -f "${cfg}" ]] || return 0
        ((${#@} == 0)) && return 0
        if /usr/local/bin/fs25-configure-web.sh "${cfg}" "$@"; then
            log "Updated dedicatedServer.xml portal logos -> $*"
        else
            log "Failed to update portal logos in dedicatedServer.xml"
        fi
    }

    local login_rel=""
    local bottom_rel=""
    local args=()
    local LOGO_RESULT=""
    local login_src_path=""
    local bottom_src_path=""

    copy_logo() {
        local src_name="$1"
        local dest_stub="$2"
        local dest_rel_jpg="template/${dest_stub}.jpg"
        LOGO_RESULT=""
        [[ -n "${src_name}" ]] || return

        local src_path="${upload_dir}/${src_name}"
        if [[ ! -f "${src_path}" ]]; then
            log "Portal logo ${src_name} not found under ${upload_dir}"
            return
        fi

        if deploy_logo_file "${src_path}" "${dest_stub}"; then
            LOGO_RESULT="${dest_rel_jpg}"
            log "Synced ${src_name} into portal templates (${dest_stub}.{png,jpg}); using ${LOGO_RESULT}"
        else
            log "Copy of ${src_name} into portal templates failed; will retry in background"
        fi
    }

    if [[ -n "${login_file}" ]]; then
        copy_logo "${login_file}" "loginLogo"
        login_rel="${LOGO_RESULT}"
        login_src_path="${upload_dir}/${login_file}"
    fi

    if [[ -n "${footer_file}" ]]; then
        copy_logo "${footer_file}" "bottomLogo"
        bottom_rel="${LOGO_RESULT}"
        bottom_src_path="${upload_dir}/${footer_file}"
    elif [[ -n "${login_rel}" ]]; then
        bottom_rel="${login_rel}"
        bottom_src_path="${login_src_path}"
    fi

    [[ -n "${login_rel}" ]] && args+=("LOGIN_LOGO=${login_rel}")
    [[ -n "${bottom_rel}" ]] && args+=("BOTTOM_LOGO=${bottom_rel}")

    ((${#args[@]})) && configure_portal_xml "${args[@]}"

    start_logo_enforcer() {
        local src_path="$1"
        local dest_stub="$2"
        local rel_path="$3"
        local config_key="$4"
        [[ -n "${src_path}" ]] || return
        (
            set -euo pipefail
            local announced=0
            while true; do
                if [[ -f "${src_path}" ]]; then
                    if deploy_logo_file "${src_path}" "${dest_stub}"; then
                        if (( announced == 0 )) && [[ -n "${rel_path}" ]]; then
                            configure_portal_xml "${config_key}=${rel_path}" || true
                            announced=1
                        fi
                    fi
                else
                    announced=0
                fi
                sleep "${PORTAL_LOGO_ENFORCER_SLEEP}"
            done
        ) >>"/home/container/logs/portal-logo-sync.log" 2>&1 &
        log "Portal logo enforcer started (PID $!) for ${config_key} interval=${PORTAL_LOGO_ENFORCER_SLEEP}s"
    }

    if [[ -n "${login_src_path}" ]]; then
        local login_rel_value="${login_rel:-template/loginLogo.jpg}"
        start_logo_enforcer "${login_src_path}" "loginLogo" "${login_rel_value}" "LOGIN_LOGO"
    fi
    if [[ -n "${bottom_src_path}" ]]; then
        local bottom_rel_value="${bottom_rel:-template/bottomLogo.jpg}"
        start_logo_enforcer "${bottom_src_path}" "bottomLogo" "${bottom_rel_value}" "BOTTOM_LOGO"
    fi
}

main() {
    log_section "BOOTSTRAP START"
    ensure_opt_mount
    summarise_media_state
    wait_for_media
    apply_web_port_overrides
    sync_portal_logos
    bridge_env_vars
    start_health_monitor
    mask_upstream_secrets
    log_section "HANDOFF"
    log "Launching upstream start script"
    exec /usr/local/bin/start.sh
}

main "$@"
BOOTSTRAP
chmod +x "${SCRIPT_DIR}/bootstrap.sh"

# Lightweight health check helper that keeps Wings informed about service status
cat <<'HEALTH' > "${SCRIPT_DIR}/healthcheck.sh"
#!/bin/bash
set -euo pipefail

WEB_PORT="${WEB_PORT:-8443}"
WEB_SCHEME="${WEB_SCHEME:-http}"
GAME_PORT="${SERVER_PORT:-10823}"
ANNOUNCED=0
LAST_STATE="unknown"
FLAG="/tmp/fs25_health_ready"
LOG_PREFIX="[fs25-healthcheck]"

check_ports() {
    local web_ok=1
    local game_ok=1

    if ! curl -ks --max-time 5 "${WEB_SCHEME}://127.0.0.1:${WEB_PORT}/" >/dev/null; then
        web_ok=0
    fi

    if ! ss -lntu | grep -q ":${GAME_PORT} "; then
        game_ok=0
    fi

    if [[ ${web_ok} -eq 1 && ${game_ok} -eq 1 ]]; then
        echo "ready"
    else
        echo "pending"
    fi
}

while true; do
    state=$(check_ports)
    if [[ "${state}" != "${LAST_STATE}" ]]; then
        echo "${LOG_PREFIX} state=${state}"
        LAST_STATE="${state}"
    fi

    if [[ "${state}" == "ready" ]]; then
        if [[ ${ANNOUNCED} -eq 0 ]]; then
            echo "FS25_HEALTHCHECK=PASS $(date -Is)"
            ANNOUNCED=1
            touch "${FLAG}"
        fi
    else
        ANNOUNCED=0
        rm -f "${FLAG}"
    fi

    sleep 30
done
HEALTH
chmod +x "${SCRIPT_DIR}/healthcheck.sh"

echo "Install bootstrap complete"
