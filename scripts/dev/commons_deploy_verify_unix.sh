#!/usr/bin/env bash
# commons_deploy_verify_unix.sh
# Library: shared logic for deploy and verify scripts.
# Source this file, do NOT execute directly.
#
# Provides:
#   - Colors and helpers (info, success, warn, error)
#   - TOML parsing with awk (no external dependencies)
#   - SHA256 hashing (local and remote)
#   - SSH helpers
#   - PATH.toml readers

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: este archivo se sourcea, no se ejecuta directamente." >&2
    exit 1
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}  →${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}  ⚠${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}  ✗${RESET} $*"; }
fatal()   { echo -e "${RED}${BOLD}  ✗ ERROR:${RESET} $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# TOML parsing (pure bash + awk, no external dependencies)
# ─────────────────────────────────────────────────────────────────────────────

# Get a single value from a TOML section: toml_get <file> <section> <key>
toml_get() {
    local file="$1" section="$2" key="$3" val
    val="$(awk -v sec="$section" -v k="$key" '
        BEGIN { in_section=0 }
        $0 ~ "^\\[" sec "\\]$" { in_section=1; next }
        /^\[/ { if (in_section) exit; in_section=0 }
        in_section && ($0 ~ "^" k "[ \t]*=" || $0 ~ "^\"" k "\"" "[ \t]*=") {
            sub(/^[^=]*=[ \t]*/, "");
            gsub(/^"|"$/, "");
            print;
            exit;
        }
    ' "$file" 2>/dev/null || true)"
    echo "$val"
}

# List all key=value pairs in a TOML section
toml_list_section() {
    local file="$1" section="$2"
    awk -v sec="$section" '
        BEGIN { in_section=0 }
        $0 ~ "^\\[" sec "\\]$" { in_section=1; next }
        /^\[/ { if (in_section) exit; in_section=0 }
        in_section && /=/ {
            split($0, parts, "=");
            key = parts[1]; gsub(/^[ \t]+|[ \t]+$/, "", key);
            gsub(/^"|"$/, "", key);
            val = parts[2]; gsub(/^[ \t]+|[ \t]+$/, "", val);
            gsub(/^"|"$/, "", val);
            if (key != "" && val != "" && key !~ /^#/ && val !~ /^#/)
                print key "=" val
        }
    ' "$file" 2>/dev/null
}

# List subsections of a parent section: toml_list_subsections <file> <parent>
# e.g. toml_list_subsections PATH.toml "hosts" → bastion-usb-wifi, macbook-pro-late2012
toml_list_subsections() {
    local file="$1" parent="$2"
    awk -v parent="$parent" '
        $0 ~ "^\\[" parent "\\.([a-zA-Z0-9_-]+)\\]" {
            line = $0;
            gsub(/^\[.*\./, "", line);
            gsub(/\]/, "", line);
            print line;
        }
    ' "$file" 2>/dev/null
}

# List array values from a TOML key: toml_list_array <file> <section> <key>
toml_list_array() {
    local file="$1" section="$2" key="$3"
    awk -v sec="$section" -v k="$key" '
        BEGIN { in_section=0; in_array=0 }
        $0 ~ "^\\[" sec "\\]$" { in_section=1; next }
        /^\[/ && in_section { if (in_array==0) exit; else in_section=0 }
        in_section && ($0 ~ "^" k "[ \t]*=[ \t]*\\[" || $0 ~ "^\"" k "\"" "[ \t]*=[ \t]*\\[") { in_array=1; next }
        in_array && /\]/ { in_array=0; exit }
        in_array {
            gsub(/^[ \t]+"?/, "");
            gsub(/"?[,]?$/, "");
            gsub(/^"|"$/,"");
            if ($0 != "") print
        }
    ' "$file" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# PATH.toml readers
# ─────────────────────────────────────────────────────────────────────────────

PATH_TOML="${PATH_TOML:-$REPO_ROOT/PATH.toml}"

# Get remote name for a script path
get_script_remote_name() {
    local script="$1"
    toml_get "$PATH_TOML" "scripts" "$script"
}

# List all script → remote_name pairs
list_script_mappings() {
    toml_list_section "$PATH_TOML" "scripts"
}

# Get host config values
get_host_value() {
    local host="$1" key="$2"
    toml_get "$PATH_TOML" "hosts.$host" "$key"
}

# List all known hosts
list_hosts() {
    toml_list_subsections "$PATH_TOML" "hosts"
}

# ─────────────────────────────────────────────────────────────────────────────
# SHA256 hashing
# ─────────────────────────────────────────────────────────────────────────────

hash_local() {
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

hash_remote() {
    local ssh_target="$1" remote_path="$2"
    ssh "$ssh_target" "sha256sum '$remote_path' 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# SSH helpers
# ─────────────────────────────────────────────────────────────────────────────

# Build SSH target from host config
ssh_target() {
    local host="$1"
    local address user
    address="$(get_host_value "$host" "address")"
    user="$(get_host_value "$host" "user")"
    if [[ -n "$user" ]]; then
        echo "${user}@${address}"
    else
        echo "$address"
    fi
}

# Get remote path for a script on a specific host
remote_path_for_script() {
    local host="$1" script="$2"
    local base_path remote_name
    base_path="$(get_host_value "$host" "base_path")"
    remote_name="$(get_script_remote_name "$script")"
    echo "${base_path}/${remote_name}"
}

# SSH execute on target
ssh_exec() {
    local target="$1" cmd="$2"
    ssh "$target" "$cmd" 2>/dev/null
}

# SCP a file to target
scp_file() {
    local local_file="$1" target="$2" remote_path="$3"
    scp "$local_file" "${target}:${remote_path}" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Deploy + verify helpers
# ─────────────────────────────────────────────────────────────────────────────

# Deploy a single script to a host
deploy_one() {
    local host="$1" script="$2"
    local target remote_path
    target="$(ssh_target "$host")"
    remote_path="$(remote_path_for_script "$host" "$script")"

    if [[ ! -f "$script" ]]; then
        error "  Script local no encontrado: $script"
        return 1
    fi

    scp_file "$script" "$target" "$remote_path" && \
    ssh_exec "$target" "chmod +x '$remote_path' 2>/dev/null" && \
    success "  deploy: $script → ${host}:${remote_path}"
}

# Verify a single script on a host (compare hashes)
verify_one() {
    local host="$1" script="$2" silent="${3:-0}"
    local target remote_path local_hash remote_hash
    target="$(ssh_target "$host")"
    remote_path="$(remote_path_for_script "$host" "$script")"

    if [[ ! -f "$script" ]]; then
        [[ "$silent" -eq 0 ]] && error "  Script local no encontrado: $script"
        return 1
    fi

    local_hash="$(hash_local "$script")"
    remote_hash="$(hash_remote "$target" "$remote_path")"

    if [[ -z "$remote_hash" ]]; then
        error "  ${script}: ✗ no encontrado en ${host} (${remote_path})"
        return 1
    elif [[ "$local_hash" == "$remote_hash" ]]; then
        [[ "$silent" -eq 0 ]] && success "  ${script}: ✓ ${local_hash:0:16}"
        return 0
    else
        error "  ${script}: ✗ difiere (local=${local_hash:0:16}, remoto=${remote_hash:0:16})"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Find + xargs pattern helpers
# ─────────────────────────────────────────────────────────────────────────────

# List all scripts found under scripts/
find_all_scripts() {
    find "$REPO_ROOT/scripts" -name '*.sh' -type f | sort
}

# List all scripts that have a mapping in PATH.toml
find_mapped_scripts() {
    local tmpfile
    tmpfile="$(mktemp /tmp/mapped_scripts.XXXXXX)"
    find_all_scripts > "$tmpfile"
    while IFS= read -r script; do
        local rel="${script#"$REPO_ROOT"/}"
        local remote_name
        remote_name="$(get_script_remote_name "$rel" || true)"
        if [[ -n "$remote_name" ]]; then
            echo "$rel"
        fi
    done < "$tmpfile"
    rm -f "$tmpfile"
}

# Verify checksums locally against SHA256SUMS
verify_local_checksums() {
    local file="${1:-$REPO_ROOT/SHA256SUMS}"
    if [[ ! -f "$file" ]]; then
        error "SHA256SUMS no encontrado en $file"
        error "Ejecuta: make checksums"
        return 1
    fi

    pushd "$REPO_ROOT" > /dev/null
    if sha256sum -c "$file" --quiet 2>/dev/null; then
        success "Todos los scripts coinciden con SHA256SUMS."
        popd > /dev/null
        return 0
    else
        error "Discrepancia detectada contra SHA256SUMS."
        popd > /dev/null
        return 1
    fi
}
