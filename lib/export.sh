#!/usr/bin/env bash
# Client configuration export helpers.

[[ -n "${_XRF_EXPORT_LOADED:-}" ]] && return 0
readonly _XRF_EXPORT_LOADED=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/core.sh
. "${HERE}/lib/core.sh"
# shellcheck source=lib/plugins.sh
. "${HERE}/lib/plugins.sh"
# shellcheck source=modules/io.sh
. "${HERE}/modules/io.sh"
# shellcheck source=modules/state.sh
. "${HERE}/modules/state.sh"
# shellcheck source=modules/net/network.sh
. "${HERE}/modules/net/network.sh"
# shellcheck source=services/xray/common.sh
. "${HERE}/services/xray/common.sh"

export::load_context() {
  local state
  state="$(state::load)"

  local -a fields=()
  mapfile -t fields < <(
    echo "${state}" | jq -r '
      [
        .name // .topology // "reality-only",
        .xray.reality_sni // "www.apple.com",
        .xray.short_id // "",
        .xray.reality_public_key // "",
        .xray.vision_port // "8443",
        .xray.reality_port // "443",
        .xray.uuid_vision // "",
        .xray.uuid_reality // "",
        .xray.domain // "",
        .xray.uuid // "",
        .xray.port // "443",
        .xray.fingerprint // "chrome",
        .xray.vless_encryption // "none"
      ] | .[] // ""
    '
  )

  EX_TOPO="${fields[0]:-reality-only}"
  EX_SNI="${fields[1]:-www.apple.com}"
  EX_SID="${fields[2]:-}"
  EX_PBK="${fields[3]:-}"
  EX_VPORT="${fields[4]:-8443}"
  EX_RPORT="${fields[5]:-443}"
  EX_UV="${fields[6]:-}"
  EX_UR="${fields[7]:-}"
  EX_DOM="${fields[8]:-}"
  EX_UUID="${fields[9]:-}"
  EX_PORT="${fields[10]:-443}"
  EX_FP="${fields[11]:-chrome}"
  EX_VLESS_ENCRYPTION="${fields[12]:-none}"
  EX_IP="${XRAY_SERVER_IP:-}"

  if [[ -z "${EX_SID}" && -f "$(xray::active)/05_inbounds.json" ]]; then
    EX_SID="$(jq -r '.inbounds[]?.streamSettings?.realitySettings?.shortIds?[1] // .inbounds[]?.streamSettings?.realitySettings?.shortIds?[0] // empty' "$(xray::active)/05_inbounds.json" 2> /dev/null | head -1)"
  fi

  [[ -n "${EX_IP}" ]] || EX_IP="$(net::detect_public_ip || true)"
  [[ -n "${EX_IP}" ]] || EX_IP="YOUR_SERVER_IP"
}

export::_link_records() {
  local first_sni="${EX_SNI%%,*}"

  case "${EX_TOPO}" in
    vision-reality)
      if [[ -n "${EX_DOM}" && -n "${EX_UV}" ]]; then
        local vlink="vless://${EX_UV}@${EX_DOM}:${EX_VPORT}?security=tls&flow=xtls-rprx-vision&sni=${EX_DOM}&fp=${EX_FP}#Vision-${EX_DOM}"
        printf 'VISION\t%s\t%s\t%s\t%s\t%s\t%s\t\t\t\t%s\n' "${vlink}" "${EX_DOM}" "${EX_VPORT}" "${EX_UV}" "${EX_DOM}" "${EX_FP}" "tls"
      fi
      if [[ -n "${EX_UR}" && -n "${EX_PBK}" && -n "${EX_SID}" ]]; then
        local rlink="vless://${EX_UR}@${EX_IP}:${EX_RPORT}?encryption=${EX_VLESS_ENCRYPTION}&flow=xtls-rprx-vision&security=reality&sni=${first_sni}&fp=${EX_FP}&pbk=${EX_PBK}&sid=${EX_SID}&spx=%2F#REALITY-${EX_IP}"
        printf 'REALITY\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${rlink}" "${EX_IP}" "${EX_RPORT}" "${EX_UR}" "${first_sni}" "${EX_FP}" "${EX_PBK}" "${EX_SID}" "${EX_VLESS_ENCRYPTION}" "reality"
      fi
      ;;
    *)
      if [[ -n "${EX_UUID}" && -n "${EX_PBK}" && -n "${EX_SID}" ]]; then
        local link="vless://${EX_UUID}@${EX_IP}:${EX_PORT}?encryption=${EX_VLESS_ENCRYPTION}&flow=xtls-rprx-vision&security=reality&sni=${first_sni}&fp=${EX_FP}&pbk=${EX_PBK}&sid=${EX_SID}&spx=%2F#REALITY-${EX_IP}"
        printf 'REALITY\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${link}" "${EX_IP}" "${EX_PORT}" "${EX_UUID}" "${first_sni}" "${EX_FP}" "${EX_PBK}" "${EX_SID}" "${EX_VLESS_ENCRYPTION}" "reality"
      fi
      ;;
  esac
}

export::uri() {
  local records
  records="$(export::_link_records)"
  if [[ -z "${records}" ]]; then
    core::log error "no client links available in state" "{}"
    return 1
  fi

  local label link
  while IFS=$'\t' read -r label link _rest; do
    [[ -n "${label}" && -n "${link}" ]] || continue
    if [[ "${label}" == "VISION" ]]; then
      printf 'VISION : %s\n' "${link}"
    else
      printf '%s: %s\n' "${label}" "${link}"
    fi
    plugins::emit links_render "link=${link}" "topology=${EX_TOPO}"
  done <<< "${records}"
}

export::subscription() {
  local raw_links
  raw_links="$(export::uri_raw)" || return 1
  printf '%s' "${raw_links}" | base64 | tr -d '\n'
  printf '\n'
}

export::uri_raw() {
  local records
  records="$(export::_link_records)"
  if [[ -z "${records}" ]]; then
    core::log error "no client links available in state" "{}"
    return 1
  fi

  local link
  while IFS=$'\t' read -r _label link _rest; do
    [[ -n "${link}" ]] || continue
    printf '%s\n' "${link}"
  done <<< "${records}"
}

export::clash() {
  local records
  records="$(export::_link_records)"
  if [[ -z "${records}" ]]; then
    core::log error "no client links available in state" "{}"
    return 1
  fi

  local -a proxy_names=()
  local label link server port uuid sni fp pbk sid enc security

  printf 'mixed-port: 7890\n'
  printf 'allow-lan: false\n'
  printf 'mode: rule\n'
  printf 'log-level: info\n'
  printf 'proxies:\n'

  while IFS=$'\t' read -r label link server port uuid sni fp pbk sid enc security; do
    [[ -n "${label}" && -n "${server}" ]] || continue
    local proxy_name="${label}-${server}"
    proxy_names+=("${proxy_name}")
    printf '  - name: %s\n' "${proxy_name}"
    printf '    type: vless\n'
    printf '    server: %s\n' "${server}"
    printf '    port: %s\n' "${port}"
    printf '    uuid: %s\n' "${uuid}"
    printf '    network: tcp\n'
    printf '    tls: true\n'
    printf '    udp: true\n'
    printf '    servername: %s\n' "${sni}"
    printf '    client-fingerprint: %s\n' "${fp}"
    printf '    flow: xtls-rprx-vision\n'
    if [[ "${security}" == "reality" ]]; then
      printf '    reality-opts:\n'
      printf '      public-key: %s\n' "${pbk}"
      printf '      short-id: %s\n' "${sid}"
    fi
  done <<< "${records}"

  printf 'proxy-groups:\n'
  printf '  - name: PROXY\n'
  printf '    type: select\n'
  printf '    proxies:\n'
  local name
  for name in "${proxy_names[@]}"; do
    printf '      - %s\n' "${name}"
  done
  printf 'rules:\n'
  printf '  - MATCH,PROXY\n'
}

export::v2rayn() {
  local records
  records="$(export::_link_records)"
  if [[ -z "${records}" ]]; then
    core::log error "no client links available in state" "{}"
    return 1
  fi

  local outbounds='[]'
  local label link server port uuid sni fp pbk sid enc security
  while IFS=$'\t' read -r label link server port uuid sni fp pbk sid enc security; do
    [[ -n "${label}" && -n "${server}" ]] || continue
    local outbound
    if [[ "${security}" == "reality" ]]; then
      outbound="$(
        jq -n \
          --arg tag "${label}" \
          --arg address "${server}" \
          --argjson port "${port}" \
          --arg uuid "${uuid}" \
          --arg enc "${enc}" \
          --arg sni "${sni}" \
          --arg fp "${fp}" \
          --arg pbk "${pbk}" \
          --arg sid "${sid}" \
          '{
            protocol: "vless",
            tag: $tag,
            settings: {
              vnext: [{
                address: $address,
                port: $port,
                users: [{
                  id: $uuid,
                  flow: "xtls-rprx-vision",
                  encryption: $enc
                }]
              }]
            },
            streamSettings: {
              network: "tcp",
              security: "reality",
              realitySettings: {
                serverName: $sni,
                fingerprint: $fp,
                publicKey: $pbk,
                shortId: $sid,
                spiderX: "/"
              }
            }
          }'
      )"
    else
      outbound="$(
        jq -n \
          --arg tag "${label}" \
          --arg address "${server}" \
          --argjson port "${port}" \
          --arg uuid "${uuid}" \
          --arg sni "${sni}" \
          --arg fp "${fp}" \
          '{
            protocol: "vless",
            tag: $tag,
            settings: {
              vnext: [{
                address: $address,
                port: $port,
                users: [{
                  id: $uuid,
                  flow: "xtls-rprx-vision",
                  encryption: "none"
                }]
              }]
            },
            streamSettings: {
              network: "tcp",
              security: "tls",
              tlsSettings: {
                serverName: $sni,
                fingerprint: $fp,
                alpn: ["h2", "http/1.1"]
              }
            }
          }'
      )"
    fi
    outbounds="$(jq -n --argjson base "${outbounds}" --argjson item "${outbound}" '$base + [$item]')"
  done <<< "${records}"

  jq -n \
    --argjson outbounds "${outbounds}" '
    {
      log: {loglevel: "warning"},
      inbounds: [
        {
          tag: "socks",
          port: 10808,
          listen: "127.0.0.1",
          protocol: "socks",
          settings: {auth: "noauth", udp: true}
        }
      ],
      outbounds: ($outbounds + [{protocol: "freedom", tag: "direct"}]),
      routing: {
        domainStrategy: "AsIs",
        rules: [
          {
            type: "field",
            outboundTag: (($outbounds[0].tag // "direct")),
            network: "tcp,udp"
          }
        ]
      }
    }'
}

export::qr() {
  if ! command -v qrencode > /dev/null 2>&1; then
    core::log error "qrencode not found" '{"hint":"install qrencode or use xrf export uri"}'
    return 1
  fi

  local records
  records="$(export::_link_records)"
  if [[ -z "${records}" ]]; then
    core::log error "no client links available in state" "{}"
    return 1
  fi

  local label link
  while IFS=$'\t' read -r label link _rest; do
    [[ -n "${label}" && -n "${link}" ]] || continue
    printf '%s\n' "${label}"
    qrencode -t ANSIUTF8 "${link}"
    printf '\n'
  done <<< "${records}"
}

export::all() {
  local out_dir="${1}"
  io::ensure_dir "${out_dir}" 0755

  local uri_content clash_content v2rayn_content sub_content
  uri_content="$(export::uri)" || return 1
  clash_content="$(export::clash)" || return 1
  v2rayn_content="$(export::v2rayn)" || return 1
  sub_content="$(export::subscription)" || return 1

  printf '%s\n' "${uri_content}" | io::atomic_write "${out_dir}/uri.txt" 0644
  printf '%s\n' "${v2rayn_content}" | io::atomic_write "${out_dir}/v2rayn.json" 0644
  printf '%s\n' "${clash_content}" | io::atomic_write "${out_dir}/clash.yaml" 0644
  printf '%s\n' "${sub_content}" | io::atomic_write "${out_dir}/subscription.txt" 0644

  printf 'Export files written to: %s\n' "${out_dir}"
}
