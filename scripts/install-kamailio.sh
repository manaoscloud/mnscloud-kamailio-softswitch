#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[install-kamailio]"
# shellcheck disable=SC1091
source "$(dirname "$0")/lib/install-base.sh" "$@"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

NODE_UUID_FILE="/etc/mnscloud/softswitch/node.uuid"
API_TOKEN_FILE="/etc/mnscloud/softswitch/api.token"
API_BASE_FILE="/etc/mnscloud/softswitch/api.base"
DEFAULT_API_BASE="https://api.publichost.cloud"
NODE_UUID=""
API_BASE=""
API_TOKEN=""

normalize_url() {
  local value="$1"
  value="$(printf "%s" "$value" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s#/*$##')"
  printf "%s" "$value"
}

validate_api_base() {
  [[ "$1" =~ ^https?://[^[:space:]/]+(:[0-9]+)?(/[^[:space:]]*)?$ ]]
}

prompt_api_base() {
  local value=""
  if [[ -t 0 ]]; then
    read -r -p "Enter the MNSCloud API base URL [${DEFAULT_API_BASE}]: " value
  fi
  value="${value:-${DEFAULT_API_BASE}}"
  normalize_url "$value"
}

ensure_api_base_file() {
  local dir value
  dir="$(dirname "${API_BASE_FILE}")"
  [[ -d "$dir" ]] || run "mkdir -p '${dir}'"

  if [[ -f "${API_BASE_FILE}" ]]; then
    value="$(tr -d '[:space:]' < "${API_BASE_FILE}")"
    API_BASE="$(normalize_url "$value")"
    ok "API base carregada de ${API_BASE_FILE}: ${API_BASE}"
  else
    API_BASE="$(prompt_api_base)"
    validate_api_base "${API_BASE}" || { err "URL base da API invalida: ${API_BASE}"; return 1; }
    write_file "${API_BASE_FILE}" "${API_BASE}"
    ok "API base saved to ${API_BASE_FILE}: ${API_BASE}"
  fi

  validate_api_base "${API_BASE}" || { err "URL base da API invalida em ${API_BASE_FILE}: ${API_BASE}"; return 1; }
  run "chown root:root '${API_BASE_FILE}'"
  run "chmod 0640 '${API_BASE_FILE}'"
}

detect_kamailio_os() {
  if [[ ! -r /etc/os-release ]]; then
    err "Could not read /etc/os-release"
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}:${VERSION_ID:-}" in
    debian:12|debian:13) echo "debian"; return 0 ;;
    rocky:8*|rocky:9*) echo "rocky"; return 0 ;;
  esac
  err "Unsupported operating system for Kamailio. Supported: Debian 12/13 and Rocky 8/9."
  exit 2
}

generate_uuid() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    tr '[:upper:]' '[:lower:]' < /proc/sys/kernel/random/uuid
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    err "Could not generate local UUID."
    return 1
  fi
}

generate_secret_32() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32
    return 0
  fi
  tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
}

ensure_api_token_file() {
  local dir
  dir="$(dirname "${API_TOKEN_FILE}")"
  [[ -d "$dir" ]] || run "mkdir -p '${dir}'"

  if [[ -f "${API_TOKEN_FILE}" ]]; then
    API_TOKEN="$(tr -d '[:space:]' < "${API_TOKEN_FILE}")"
    ok "Softswitch API token loaded from ${API_TOKEN_FILE}"
  else
    API_TOKEN="$(generate_secret_32)"
    write_file "${API_TOKEN_FILE}" "${API_TOKEN}"
    ok "Softswitch API token created at ${API_TOKEN_FILE}"
  fi

  run "chown root:root '${API_TOKEN_FILE}'"
  run "chmod 0640 '${API_TOKEN_FILE}'"
}

ensure_node_uuid_file() {
  local dir compact
  dir="$(dirname "${NODE_UUID_FILE}")"
  [[ -d "$dir" ]] || run "mkdir -p '${dir}'"
  if [[ -f "${NODE_UUID_FILE}" ]]; then
    NODE_UUID="$(tr -d '[:space:]' < "${NODE_UUID_FILE}")"
    ok "Node UUID loaded from ${NODE_UUID_FILE}: ${NODE_UUID}"
  else
    NODE_UUID="$(generate_uuid)"
    write_file "${NODE_UUID_FILE}" "${NODE_UUID}"
    ok "Node UUID created at ${NODE_UUID_FILE}: ${NODE_UUID}"
  fi
  compact="${NODE_UUID//-/}"
  [[ "${compact}" =~ ^[0-9A-Fa-f]{32}$ ]] || { err "Node UUID invalido em ${NODE_UUID_FILE}: ${NODE_UUID}"; return 1; }
  compact="$(echo "${compact}" | tr '[:upper:]' '[:lower:]')"
  NODE_UUID="${compact:0:8}-${compact:8:4}-${compact:12:4}-${compact:16:4}-${compact:20:12}"
  write_file "${NODE_UUID_FILE}" "${NODE_UUID}"
  run "chown root:root '${NODE_UUID_FILE}'"
  run "chmod 0640 '${NODE_UUID_FILE}'"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  printf "%s" "$value"
}

json_field() {
  local field="$1" file="$2"
  sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$file" | head -n1
}

private_ipv4() {
  ip -o -4 addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}' || true
}

public_ipv4() {
  curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null ||
    curl -fsS --max-time 5 https://ifconfig.me/ip 2>/dev/null ||
    true
}

bootstrap_node_via_api() {
  local hostname_value private_ip public_ip payload response_file http_code server_uuid
  hostname_value="$(hostname -f 2>/dev/null || hostname 2>/dev/null || true)"
  private_ip="$(private_ipv4)"
  public_ip="$(public_ipv4)"
  payload="{\"hostname\":\"$(json_escape "${hostname_value}")\""
  [[ -n "${private_ip}" ]] && payload+=",\"privateIP\":\"$(json_escape "${private_ip}")\""
  [[ -n "${public_ip}" ]] && payload+=",\"publicIP\":\"$(json_escape "${public_ip}")\""
  payload+="}"
  if [[ "$DRY_RUN" == true ]]; then
    log DRY "POST ${API_BASE}/api/v1/softswitch/kamailio/bootstrap?node_uuid=${NODE_UUID} with local token ${API_TOKEN_FILE}"
    return 0
  fi
  response_file="$(mktemp)"
  http_code="$(curl -sS -o "${response_file}" -w "%{http_code}" -X POST "${API_BASE}/api/v1/softswitch/kamailio/bootstrap?node_uuid=${NODE_UUID}" -H "Content-Type: application/json" -H "Authorization: Bearer ${API_TOKEN}" --data "${payload}" 2>>"${LOG_FILE}")"
  server_uuid="$(json_field "serverUUID" "${response_file}")"
  rm -f "${response_file}"
  if [[ "${http_code}" == "200" ]]; then
    ok "Node UUID vinculado via API bootstrap. serverUUID: ${server_uuid:-unknown}"
    return 0
  fi
  warn "Softswitch API bootstrap returned HTTP ${http_code}. Register the Node UUID manually if necessary."
  return 1
}

install_packages_debian() {
  local codename
  # shellcheck disable=SC1091
  . /etc/os-release
  codename="${VERSION_CODENAME:-}"
  if [[ -z "${codename}" ]]; then
    codename="$(. /etc/os-release && echo "${VERSION:-}" | sed -n 's/.*(\([^)]*\)).*/\1/p' | head -n1)"
  fi
  case "${codename}" in
    bookworm|trixie) ;;
    *)
      err "Unsupported Debian codename for Kamailio 6.1.x repository: ${codename:-unknown}. Supported: bookworm/trixie."
      exit 2
      ;;
  esac
  info "Configuring official Kamailio 6.1.x repository for Debian ${codename}..."
  run "apt-get update -y"
  run "apt-get install -y --no-install-recommends ca-certificates curl gnupg"
  run "install -m 0755 -d /usr/share/keyrings"
  run "rm -f /usr/share/keyrings/kamailio.gpg.tmp"
  run "curl -fsSL https://deb.kamailio.org/kamailiodebkey.gpg | gpg --dearmor -o /usr/share/keyrings/kamailio.gpg.tmp"
  run "mv /usr/share/keyrings/kamailio.gpg.tmp /usr/share/keyrings/kamailio.gpg"
  run "chmod 0644 /usr/share/keyrings/kamailio.gpg"
  write_file "/etc/apt/sources.list.d/kamailio.list" "deb [signed-by=/usr/share/keyrings/kamailio.gpg] http://deb.kamailio.org/kamailio61 ${codename} main"
  write_file "/etc/apt/preferences.d/kamailio" "Package: kamailio*
Pin: origin deb.kamailio.org
Pin-Priority: 1001

Package: kamcli
Pin: origin deb.kamailio.org
Pin-Priority: 1001"
  run "apt-get update -y"
  run "apt-get install -y --no-install-recommends kamailio kamailio-extra-modules kamailio-utils-modules kamailio-tls-modules kamailio-json-modules sngrep tcpdump ngrep dnsutils traceroute mtr-tiny netcat-openbsd jq ca-certificates curl"
  run "kamailio -v | head -n 1"
}

install_packages_rocky() {
  local major
  # shellcheck disable=SC1091
  . /etc/os-release
  major="${VERSION_ID%%.*}"
  case "${major}" in
    8|9) ;;
    *)
      err "Unsupported Rocky Linux version for Kamailio 6.1.x repository: ${VERSION_ID:-unknown}. Supported: Rocky 8/9."
      exit 2
      ;;
  esac
  info "Configuring official Kamailio 6.1.x repository for Rocky ${major}..."
  run "dnf install -y epel-release dnf-plugins-core ca-certificates curl"
  run "rpm --import https://rpm.kamailio.org/rpm-pub.key"
  write_file "/etc/yum.repos.d/kamailio.repo" "[kamailio-6.1]
name=Kamailio 6.1.x official repository
baseurl=https://rpm.kamailio.org/rocky/${major}/6.1/6.1/\$basearch/
enabled=1
gpgcheck=1
gpgkey=https://rpm.kamailio.org/rpm-pub.key"
  run "dnf clean all"
  run "dnf makecache --repo kamailio-6.1"
  run "dnf install -y kamailio kamailio-utils kamailio-json kamailio-curl sngrep tcpdump ngrep bind-utils traceroute mtr nc jq curl ca-certificates"
  run "kamailio -v | head -n 1"
}

backup_once() {
  local file="$1"
  if [[ -f "$file" && ! -f "${file}.bkp" ]]; then
    run "cp -a '${file}' '${file}.bkp'"
  fi
}

write_kamailio_config() {
  local cfg="/etc/kamailio/kamailio.cfg"
  backup_once "$cfg"
  write_file "$cfg" "#!KAMAILIO
#!define WITH_AUTH
#!define WITH_USRLOCDB

listen=udp:0.0.0.0:5060
listen=tcp:0.0.0.0:5060
auto_aliases=no
children=4
log_stderror=no

loadmodule \"tm.so\"
loadmodule \"sl.so\"
loadmodule \"rr.so\"
loadmodule \"maxfwd.so\"
loadmodule \"textops.so\"
loadmodule \"siputils.so\"
loadmodule \"xlog.so\"
loadmodule \"pv.so\"
loadmodule \"jsonrpcs.so\"
loadmodule \"kex.so\"
loadmodule \"corex.so\"
loadmodule \"ctl.so\"
loadmodule \"htable.so\"
loadmodule \"http_async_client.so\"
loadmodule \"jansson.so\"

modparam(\"http_async_client\", \"workers\", 4)
modparam(\"htable\", \"htable\", \"auth_cache=>size=12;autoexpire=60\")

request_route {
  if (!mf_process_maxfwd_header(\"10\")) { sl_send_reply(\"483\", \"Too Many Hops\"); exit; }
  if (is_method(\"OPTIONS\")) { sl_send_reply(\"200\", \"OK\"); exit; }

  if (is_method(\"REGISTER\")) {
    \$var(auth_url) = \"${API_BASE}/api/v1/softswitch/kamailio/auth?node_uuid=${NODE_UUID}\";
    \$var(auth_body) = \"{\\\"username\\\":\\\"\" + \$fU + \"\\\",\\\"domain\\\":\\\"\" + \$fd + \"\\\"}\";
    xlog(\"L_INFO\", \"Kamailio auth lookup for \$fU@\$fd via MNSCloud\\n\");
    if (!t_newtran()) { sl_reply_error(); exit; }
    \$http_req(all) = \$null;
    \$http_req(method) = \"POST\";
    \$http_req(hdr) = \"Content-Type: application/json\";
    \$http_req(hdr) = \"Authorization: Bearer ${API_TOKEN}\";
    \$http_req(body) = \$var(auth_body);
    http_async_query(\"\$var(auth_url)\", \"AUTH_REPLY\");
    exit;
  }

  if (!t_relay()) { sl_reply_error(); }
  exit;
}

route[AUTH_REPLY] {
  if (\$http_ok && \$http_rs == 200) {
    if (\$http_rb =~ \"\\\"authorized\\\":true\") {
      t_reply(\"200\", \"OK\");
      exit;
    }
  }
  t_reply(\"403\", \"Forbidden\");
  exit;
}
"
  run "kamailio -c -f '${cfg}'"
}

enable_service() {
  run "systemctl enable kamailio"
  run "systemctl restart kamailio"
}

main() {
  require_root
  echo "kamailio        Softswitch - Kamailio 6.1.x (official repository)"
  echo "Mode: $([[ "$DRY_RUN" == true ]] && echo DRY-RUN || echo APPLY)"
  echo "Log:  ${LOG_FILE}"
  echo "=================================================="
  local app_security_script="${MNSCLOUD_MONOREPO_ROOT:-${PROJECT_ROOT}}/scripts/application-security.sh"
  [[ -f "${app_security_script}" ]] && run "bash '${app_security_script}'"
  ensure_local_hostname_hosts
  ensure_api_base_file
  ensure_node_uuid_file
  ensure_api_token_file
  case "$(detect_kamailio_os)" in
    debian) install_packages_debian ;;
    rocky) install_packages_rocky ;;
  esac
  bootstrap_node_via_api || true
  write_kamailio_config
  enable_service
  ok "Kamailio installed. Node UUID: ${NODE_UUID}"
}

main "$@"
