#!/usr/bin/env bash
# =============================================================================
#  check-proxy.sh — ตรวจ DB Security Proxy ที่รันแยก (เช่น proxy ของ DWS สำหรับ Passthrough ของ portal)
#
#  ถามก่อนเริ่ม : โฟลเดอร์ที่วาง jar ของ proxy, ชื่อ jar, ไฟล์ proxy.properties, ไฟล์ log,
#                 user ที่รัน, authentication.properties ของ portal (เทียบ aad.proxy.scope)
#  ตรวจ        : hostname/เวลา, process + Java + config ที่ใช้จริง, สิทธิ์ไฟล์ (config / keystore),
#                 ค่าใน config + URL ที่ใช้จริง + ทดสอบ, port listen, ต่อ DB ปลายทาง, log (user-mapping /
#                 policy-watch / entra-jwt)
#
#  ใช้   : ./check-proxy.sh   |  ./check-proxy.sh -y
#  ผล   : <โฟลเดอร์ที่รันสคริปต์>/proxy_<host>_<เวลา>/  (report.log, results.csv, summary.txt, evidence/ …)
# =============================================================================
SCRIPT_DIR=$(dirname "$(readlink -f -- "$0")")
. "$SCRIPT_DIR/cbi-check-lib.sh" || { echo "ไม่พบ cbi-check-lib.sh ใน $SCRIPT_DIR"; exit 2; }
REPORT_DIR="${REPORT_DIR:-$PWD}"     # ผลการตรวจเก็บในโฟลเดอร์ที่รันสคริปต์
parse_common_args "$@"

KEYS=( db.host db.port proxy.postgresql.port proxy.mysql.port proxy.sqlserver.port admin.port
       azure.entra.tenant.id azure.entra.client.id usermapping.enabled usermapping.api.url cubika.ai.url cubika.report.url )
MANUAL_CHECKS="ดาวน์โหลด Passthrough ที่ portal แล้วรันสคริปต์นี้ซ้ำ — ต้องเห็น [entra-jwt] Accepted"

echo "=== ตรวจ DB Security Proxy (แยก) — ระบุ path (Enter = ใช้ค่าที่แสดง) ==="
# หา process ที่ไม่ใช่ Gateway ของ enforcer (config ไม่อยู่ใต้ /dataguard/proxy/<id>/)
PPID_=""; PCFG=""
while read -r pid; do
  a=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null); c=$(echo "$a" | grep -oE -- '-Dproxy\.config=[^ ]+' | cut -d= -f2-)
  echo "$c" | grep -q "/dataguard/proxy/[^/]*/proxy.properties" && continue
  PPID_="$pid"; PCFG="$c"; break
done < <(java_pids "db-security-proxy")
DEF_DIR=$(readlink "/proc/$PPID_/cwd" 2>/dev/null || echo "$HOME/sw_install/agent-dataguard")
DEF_JAR=$(tr '\0' '\n' < "/proc/$PPID_/cmdline" 2>/dev/null | grep -m1 'db-security-proxy.*\.jar' | xargs -r basename)
DEF_LOG=$(readlink "/proc/$PPID_/fd/1" 2>/dev/null); case "$DEF_LOG" in /*) ;; *) DEF_LOG="$DEF_DIR/db-security-proxy.log";; esac
ask PROXY_DIR   "โฟลเดอร์ที่วาง jar ของ proxy"                     "$DEF_DIR" dir
ask PROXY_JAR   "ชื่อ jar ของ proxy"                              "${DEF_JAR:-db-security-proxy-1.1.0-build-0104.jar}" text
ask PROXY_CONF  "ไฟล์ proxy.properties ที่ proxy ใช้"               "${PCFG:-$HOME/cbi/dataguard/proxy.properties}" file
ask PROXY_LOG   "ไฟล์ log ของ proxy"                              "$DEF_LOG" "file?"
ask SVC_USER    "user ที่รัน proxy"                                "$(stat -c %U "$PROXY_CONF" 2>/dev/null || id -un)" text
ask PORTAL_AUTH "authentication.properties ของ portal (เทียบ scope ; ว่าง = ข้าม)" "/app/cbi/server/tomcat9/webapps/spwportal/WEB-INF/classes/prop/authentication.properties" "file?"

start_report "proxy"
print_answers

# -----------------------------------------------------------------------------
section "1. Process / Java"
if [ -n "$PPID_" ]; then
  pass "proxy รันอยู่ PID $PPID_ (user $(proc_user "$PPID_"), start $(proc_start "$PPID_"), PPID $(ps -o ppid= -p "$PPID_" | tr -d ' '))"
  info "cwd : $(readlink "/proc/$PPID_/cwd") ; คำสั่ง : $(tr '\0' ' ' < "/proc/$PPID_/cmdline" | cut -c1-220)"
  info "Java : $(proc_java_version "$PPID_")"
  pu=$(proc_user "$PPID_")
  if [ -z "$pu" ]; then warn "อ่าน user ของ PID $PPID_ ไม่ได้" "" "process อาจหยุดระหว่างตรวจ — ps -fp $PPID_"
  elif [ "$pu" != "$SVC_USER" ]; then warn "proxy รันด้วย user $pu ไม่ใช่ $SVC_USER"; fi
  rc=${PCFG:-"(ไม่ได้ระบุ -Dproxy.config — ใช้ค่า default ของโปรแกรม)"}
  [ -z "$PCFG" ] || [ "$PCFG" = "$PROXY_CONF" ] && pass "config ที่ process ใช้ : $rc" || warn "process ใช้ config $PCFG ไม่ใช่ $PROXY_CONF"
  n=$(java_pids "db-security-proxy" | while read -r p; do tr '\0' ' ' < "/proc/$p/cmdline" | grep -q "/dataguard/proxy/[^/]*/proxy.properties" || echo "$p"; done | grep -c .)
  [ "$n" -le 1 ] || fail "proxy แบบแยกรัน $n ตัว" "" "port จะชนกัน — หยุดตัวเก่า"
else fail "proxy ไม่รัน" "" "cd $PROXY_DIR แล้ว start ด้วย -Dproxy.config=$PROXY_CONF (เคยล้มเพราะ start จากโฟลเดอร์ที่ไม่มี jar)"; fi
ev_cmd process_java.txt ps -o pid,ppid,user,lstart,etime,rss,args -C java
[ -n "$PPID_" ] && { echo "# PID $PPID_ cwd=$(readlink /proc/$PPID_/cwd) stdout=$(readlink /proc/$PPID_/fd/1)"; tr '\0' '\n' < "/proc/$PPID_/cmdline"; } 2>&1 | ev_save process_proxy.txt
if have systemctl; then
  s=$(systemctl list-units --type=service --all 2>/dev/null | grep -iE "proxy|dbguard" | grep -v docker | awk '{print $1" "$3" "$4}')
  [ -n "$s" ] && info "systemd : $s" || warn "ไม่ได้รันเป็น systemd service" "" "ถ้า process ถูก kill จะไม่ start เอง — แนะนำ service + Restart=on-failure"
fi

# -----------------------------------------------------------------------------
section "2. ไฟล์ / สิทธิ์"
[ -f "$PROXY_DIR/$PROXY_JAR" ] && pass "พบ jar $PROXY_JAR ($(ls -l --time-style='+%F %T' "$PROXY_DIR/$PROXY_JAR" | awk '{print $6" "$7}') ; sha256 $(sha256sum "$PROXY_DIR/$PROXY_JAR" | cut -c1-16)…)" \
  || fail "ไม่พบ $PROXY_DIR/$PROXY_JAR"
perm_check "$PROXY_CONF" "$SVC_USER" yes no "proxy.properties"
{ echo "# $(date '+%F %T') sha256"; sha256sum "$PROXY_DIR"/*.jar 2>&1; } | ev_save sha256.txt
ev_cmd ls_proxy_dir.txt ls -la --time-style=+%F_%T "$PROXY_DIR" "$(dirname "$PROXY_CONF")"
for k in $(grep -oE '^[a-zA-Z0-9_.]*keystore[a-zA-Z0-9_.]*(path|file)?' "$PROXY_CONF" | sort -u); do
  v=$(prop_get "$PROXY_CONF" "$k"); [ -n "$v" ] && [ -e "$v" ] && perm_check "$v" "$SVC_USER" yes no "$k ($v)"
done
ks=$(grep -oE '/[^ ]*\.jks' "$PROXY_LOG" 2>/dev/null | tail -1); [ -n "$ks" ] && perm_check "$ks" "$SVC_USER" yes no "keystore จาก log ($ks)"
[ -n "$PROXY_LOG" ] && perm_check "$PROXY_LOG" "$SVC_USER" no yes "log"
pc=$(dirname "$PROXY_CONF")/policies-cached; [ -d "$pc" ] && info "policies-cached : $(ls "$pc" | wc -l) ไฟล์ (แก้ล่าสุด $(stat -c %y "$pc" | cut -d. -f1))"
info "proxy.properties แก้ล่าสุด : $(stat -c %y "$PROXY_CONF" | cut -d. -f1) (ถ้าเปลี่ยนโดยไม่ได้นัด ให้ถามทีม)"

# -----------------------------------------------------------------------------
section "3. ค่าใน proxy.properties + URL ที่ใช้จริง"
ev_conf "$PROXY_CONF" proxy.properties
[ -n "$PORTAL_AUTH" ] && ev_conf "$PORTAL_AUTH" portal_authentication.properties
extract_urls "$PROXY_CONF" | ev_save urls_in_config.txt
for k in "${KEYS[@]}"; do v=$(prop_get "$PROXY_CONF" "$k"); [ -n "$v" ] && info "$(printf '%-24s' "$k") = $(safe_val "$k" "$v")"; done
CID=$(prop_get "$PROXY_CONF" azure.entra.client.id); TID=$(prop_get "$PROXY_CONF" azure.entra.tenant.id)
[ -n "$CID" ] && [ -n "$TID" ] && pass "มี azure.entra.tenant.id และ client.id" || fail "azure.entra.tenant.id / client.id ไม่ครบ" "" "Passthrough ตรวจ token ไม่ได้"
if [ -n "$PORTAL_AUTH" ] && [ -r "$PORTAL_AUTH" ]; then
  sc=$(prop_get "$PORTAL_AUTH" aad.proxy.scope)
  [ "$sc" = "api://$CID/.default" ] && pass "aad.proxy.scope ของ portal ตรงกับ client id ของ proxy" "$sc" || fail "aad.proxy.scope ของ portal = ${sc:-(ว่าง)} (คาดหวัง api://$CID/.default)" "" "แก้ authentication.properties ของ portal (ทั้งไฟล์ใช้งานและไฟล์ต้นทาง)"
fi
echo "       URL ทั้งหมดใน proxy.properties (ซ่อน credential):"
extract_urls "$PROXY_CONF" | sed 's/^/         /'
um=$(prop_get "$PROXY_CONF" usermapping.api.url); cu=$(prop_get "$PROXY_CONF" cubika.ai.url)
[ -n "$cu" ] && url_check "$cu/" "cubika.ai.url"
[ -n "$um" ] && url_check "$um" "usermapping.api.url"
[ -n "$TID" ] && url_check "https://login.microsoftonline.com/$TID/v2.0/.well-known/openid-configuration" "Entra (JWKS ของ tenant)"

# -----------------------------------------------------------------------------
section "4. port / ปลายทาง"
for k in proxy.postgresql.port proxy.mysql.port proxy.sqlserver.port admin.port; do
  p=$(prop_get "$PROXY_CONF" "$k"); [ -z "$p" ] || [ "$p" = "0" ] && continue
  who=$(ss -ltnp 2>/dev/null | awk -v p=":$p\$" '$4 ~ p' | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)
  if port_listening "$p"; then
    if [ -n "$who" ] && [ -n "$PPID_" ] && [ "$who" != "$PPID_" ]; then fail "$k $p ถูก process อื่น (PID $who) ใช้" "" "port ชน"
    else pass "$k $p listen อยู่"; fi
  else [ "$k" = "admin.port" ] && warn "$k $p ไม่ได้ listen" || fail "$k $p ไม่ได้ listen" "" "proxy ไม่รัน / start ไม่สำเร็จ — ดู log"; fi
done
ev_cmd ports_listen.txt ss -ltnp
dh=$(prop_get "$PROXY_CONF" db.host); dp=$(prop_get "$PROXY_CONF" db.port)
[ -n "$dh" ] && tcp_check "$dh" "${dp:-5432}" "DB ปลายทางของ proxy"

# -----------------------------------------------------------------------------
section "5. log ของ proxy — รอบ start ล่าสุด"
if [ -r "$PROXY_LOG" ]; then
  info "log : $(ls -lh --time-style='+%F %T' "$PROXY_LOG" | awk '{print $5", แก้ล่าสุด "$6" "$7}')"
  LOGP=$(log_since_last "$PROXY_LOG" "Loading config from" 2)
  printf '%s\n' "$LOGP" | tail -n 20000 | ev_save proxy_since_last_start.log
  printf '%s\n' "$LOGP" | grep -E "SEVERE|ERROR|Exception|Rejected" | ev_save proxy_errors_since_last_start.log
  printf '%s\n' "$LOGP" | grep -E "\[user-mapping\]|\[entra-jwt\]|\[policy-watch\]" | ev_save proxy_auth_mapping.log
  lc=$(echo "$LOGP" | grep -m1 "Loading config from" | sed 's/.*Loading config from: //')
  [ "$lc" = "$PROXY_CONF" ] && pass "log : โหลด config $lc" || warn "log : โหลด config ${lc:-(ไม่พบ)} ไม่ใช่ $PROXY_CONF"
  echo "$LOGP" | grep -E "Config loaded|DB Security Proxy [0-9]|Listening on port|proxy listener (ready )?on port|TLS enabled" | sed -E 's/^INFO: *//; s/^/         /' | head -8
  echo "$LOGP" | grep -q "Unable to access jarfile" && fail "log มี Unable to access jarfile" "" "start จากโฟลเดอร์ผิด"
  pw=$(echo "$LOGP" | grep "\[policy-watch\] Started" | tail -1 | sed 's/.*Started: //'); [ -n "$pw" ] && pass "policy-watch : $pw"
  um=$(echo "$LOGP" | grep "\[user-mapping\]" | grep -E "Sync complete|Sync failed" | tail -1)
  case "$um" in *"Sync complete"*) pass "user-mapping sync ล่าสุดสำเร็จ" "$(echo "$um" | sed 's/^INFO: //')";;
                *"Sync failed"*) warn "user-mapping sync ล่าสุดล้ม" "$um" "Read timed out ระหว่าง restart Tomcat = ปกติ ; ถ้าค้าง ตรวจ usermapping.api.url";;
                *) warn "ไม่พบผล user-mapping";; esac
  ac=$(echo "$LOGP" | grep -c "\[entra-jwt\] Accepted"); rj=$(echo "$LOGP" | grep -c "\[entra-jwt\] Rejected")
  info "entra-jwt หลัง start : Accepted $ac ครั้ง ; Rejected $rj ครั้ง"
  [ "$rj" -gt 0 ] && warn "มี token ถูกปฏิเสธ" "$(echo "$LOGP" | grep "\[entra-jwt\] Rejected" | tail -1 | cut -c1-200)" "signature mismatch = portal ส่ง token ของ Graph (aad.proxy.scope ว่าง) ; audience = client id ไม่ตรง"
  er=$(echo "$LOGP" | grep -E "SEVERE|ERROR|Exception" | grep -v "Read timed out")
  [ -z "$er" ] && pass "ไม่มี SEVERE / ERROR" || { warn "SEVERE/ERROR $(echo "$er" | grep -c .) บรรทัด"; echo "$er" | cut -c1-200 | sort | uniq -c | sort -rn | head -5 | sed 's/^/         /'; }
  age=$(( $(date +%s) - $(stat -c %Y "$PROXY_LOG") ))
  [ "$age" -lt 900 ] && pass "log มีการเขียนเมื่อ $age วินาทีก่อน" || warn "log ไม่ถูกเขียนมา $age วินาที" "" "proxy อาจค้าง / ดับ (user-mapping sync ทุก 5 นาทีควรเขียน log)"
else skip "log (อ่าน $PROXY_LOG ไม่ได้)"; fi

end_report
