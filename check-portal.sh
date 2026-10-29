#!/usr/bin/env bash
# =============================================================================
#  check-portal.sh — ตรวจความพร้อมของ Data Service Portal (spwportal)
#
#  ถามก่อนเริ่ม : Tomcat home, context, WAR ที่วาง, WAR ต้นฉบับ (ถ้ามี), โฟลเดอร์ config ต้นทาง,
#                 proxy.properties ของ DB Security Proxy (เพื่อเทียบ client id), user ที่รัน Tomcat,
#                 URL ของ portal
#  ตรวจ        : hostname/เวลา, สิทธิ์ไฟล์, เวอร์ชัน, config (aad.*, key DATA-MARKET-ACCESS),
#                 URL ที่ใช้จริง + ทดสอบ, log การดาวน์โหลด / error ของ token
#
#  ใช้   : ./check-portal.sh   |  ./check-portal.sh -y
#  ผล   : <โฟลเดอร์ที่รันสคริปต์>/portal_<host>_<เวลา>/  (report.log, results.csv, summary.txt, evidence/ …)
# =============================================================================
SCRIPT_DIR=$(dirname "$(readlink -f -- "$0")")
. "$SCRIPT_DIR/cbi-check-lib.sh" || { echo "ไม่พบ cbi-check-lib.sh ใน $SCRIPT_DIR"; exit 2; }
REPORT_DIR="${REPORT_DIR:-$PWD}"     # ผลการตรวจเก็บในโฟลเดอร์ที่รันสคริปต์
parse_common_args "$@"

EXPECT_WAR_SHA="${EXPECT_WAR_SHA:-ca21aceaecc7a7c2ae76918670b11659b60f4d1bfd78302ec470fb104b6a3078}"   # SPW-DEV12 ต้นฉบับ
EXPECT_STATUS="${EXPECT_STATUS:-SPW-DEV12}"
EXPECT_PATCH="${EXPECT_PATCH:-5}"
MARKERS=( "WEB-INF/classes/th/ac/ddlg/aad/AADAuthHelper.class|acquireProxyToken|>0" )
ASSETS=( "portal/activitylog.html|assets/activitylog-DKLfhaDa.js" "portal/dataservice.html|assets/dataservice-CR_arSek.js" )
MANUAL_CHECKS="login ใหม่ด้วย SSO → Dashboard
Activity Log แสดงรายการ ไม่ค้าง Loading
ดาวน์โหลด collection Open Access → ZIP
ดาวน์โหลด collection Passthrough (บัญชีที่มี User Mapping + คำขออนุมัติ) → CSV ; แล้วรันสคริปต์นี้ซ้ำเพื่อดู log"

echo "=== ตรวจ Data Service Portal — ระบุ path (Enter = ใช้ค่าที่แสดง) ==="
ask TOMCAT_HOME  "Tomcat home"                                     "/app/cbi/server/tomcat9" dir
ask CTX          "ชื่อ context ของ portal"                           "spwportal" text
ask WAR_DEPLOYED "WAR ที่วางใน webapps"                               "$TOMCAT_HOME/webapps/$CTX.war" file
ask WAR_ORIGINAL "WAR ต้นฉบับของ release (ว่าง = ข้าม)"                "" "file?"
ask CONFIG_SRC   "โฟลเดอร์ config ต้นทางของสคริปต์ deploy (ว่าง = ข้าม)"  "" "dir?"
ask PROXY_PROPS  "proxy.properties ของ DB Security Proxy (เทียบ client id ; ว่าง = ข้าม)" "$HOME/cbi/dataguard/proxy.properties" "file?"
ask SVC_USER     "user ที่รัน Tomcat"                                 "$(stat -c %U "$TOMCAT_HOME/webapps" 2>/dev/null || echo cbiaccess)" text
ask PORTAL_URL   "URL ของ portal (เช่น https://host/$CTX ; ว่าง = ข้าม)" "" "text?"
W="$TOMCAT_HOME/webapps/$CTX"; P="$W/WEB-INF/classes/prop"; CATALINA="$TOMCAT_HOME/logs/catalina.out"

start_report "portal"
print_answers

# -----------------------------------------------------------------------------
section "1. สิทธิ์ไฟล์"
perm_check "$WAR_DEPLOYED" "" no no "WAR ที่วาง"
perm_check "$W" "$SVC_USER" no yes "โฟลเดอร์ $CTX"
perm_check "$P/authentication.properties" "$SVC_USER" yes no "prop/authentication.properties"
perm_check "$P/app.properties"            "$SVC_USER" yes no "prop/app.properties"
[ -n "$CONFIG_SRC" ] && perm_check "$CONFIG_SRC/WEB-INF/classes/prop/authentication.properties" "" yes no "ไฟล์ต้นทาง authentication.properties"
ev_cmd ls_portal.txt ls -la --time-style=+%F_%T "$TOMCAT_HOME/webapps" "$W" "$P"
w=$(ls -d "$TOMCAT_HOME/work/Catalina/localhost/$CTX" 2>/dev/null)
[ -n "$w" ] && info "work/ ของ $CTX : $(stat -c '%y' "$w" | cut -d. -f1) (session เก่าถูกล้างเมื่อโฟลเดอร์นี้ถูกลบ)"

# -----------------------------------------------------------------------------
section "2. WAR / เวอร์ชัน"
info "WAR ที่วาง : $(ls -l --time-style='+%F %T' "$WAR_DEPLOYED" | awk '{print $6" "$7"  "$5" bytes"}') ; sha256 $(sha256sum "$WAR_DEPLOYED" | cut -c1-64)"
if [ -n "$WAR_ORIGINAL" ]; then
  s=$(sha256sum "$WAR_ORIGINAL" | cut -c1-64)
  [ "$s" = "$EXPECT_WAR_SHA" ] && pass "sha256 WAR ต้นฉบับตรง" || fail "sha256 WAR ต้นฉบับไม่ตรง" "$s (คาดหวัง $EXPECT_WAR_SHA)"
fi
{ echo "# $(date '+%F %T') sha256"; sha256sum "$WAR_DEPLOYED" ${WAR_ORIGINAL:+"$WAR_ORIGINAL"} 2>&1; } | ev_save sha256.txt
ev_conf "$P/version.properties" version.properties
for a in "${ASSETS[@]}"; do f=${a%%|*}; grep -o 'assets/[^"]*' "$W/$f" 2>/dev/null | sed "s#^#$f\t#"; done | ev_save assets_in_html.tsv
if [ -d "$W" ]; then
  st=$(prop_get "$P/version.properties" app.version.status); pt=$(prop_get "$P/version.properties" app.version.patch)
  [ "$st" = "$EXPECT_STATUS" ] && [ "$pt" = "$EXPECT_PATCH" ] && pass "version patch=$pt status=$st" || fail "version ไม่ตรง" "patch=$pt status=$st (คาดหวัง $EXPECT_PATCH / $EXPECT_STATUS)" "WAR ไม่ใช่ release นี้"
  for m in "${MARKERS[@]}"; do f=${m%%|*}; r=${m#*|}; pat=${r%|*}; exp=${r##*|}; n=$(count_in_file "$W/$f" "$pat")
    match_expect "$n" "$exp" && pass "$(basename "$f") มี \"$pat\"" || fail "$(basename "$f") : \"$pat\" = $n (คาด $exp)"; done
  for a in "${ASSETS[@]}"; do f=${a%%|*}; want=${a#*|}; got=$(grep -o "assets/$(basename "$want" | cut -d- -f1)-[^\"]*" "$W/$f" 2>/dev/null | head -1)
    [ "$got" = "$want" ] && pass "$f → $got" || fail "$f → ${got:-ไม่พบ} (คาดหวัง $want)" "" "WAR ไม่ใช่ release นี้ ; ผู้ใช้กด Ctrl+F5"; done
else fail "ไม่พบโฟลเดอร์ $W"; fi

# -----------------------------------------------------------------------------
section "3. Config ที่ใช้งานจริง"
A="$P/authentication.properties"; AP="$P/app.properties"
ev_conf "$A" deployed_authentication.properties; ev_conf "$AP" deployed_app.properties
[ -n "$PROXY_PROPS" ] && ev_conf "$PROXY_PROPS" proxy.properties
if [ -n "$CONFIG_SRC" ]; then
  for f in authentication.properties app.properties; do ev_conf "$CONFIG_SRC/WEB-INF/classes/prop/$f" "source_$f"
    diff "$CONFIG_SRC/WEB-INF/classes/prop/$f" "$P/$f" 2>&1; done | ev_save config_diff_source_vs_deployed.txt
fi
for f in "$A" "$AP"; do extract_urls "$f" | sed "s#^#$(basename "$f")\t#"; done | ev_save urls_in_config.tsv
for k in aad.authority aad.clientId aad.scopes aad.proxy.scope aad.redirectUri aad.secretKey aad.clientSecret; do
  v=$(prop_get "$A" "$k"); [ -n "$v" ] || is_secret_key "$k" && info "$k = $(safe_val "$k" "$v")"
done
sc=$(prop_get "$A" aad.proxy.scope)
PCID=""; [ -n "$PROXY_PROPS" ] && PCID=$(prop_get "$PROXY_PROPS" azure.entra.client.id)
if [ -z "$sc" ]; then fail "aad.proxy.scope ว่าง" "" "Passthrough → 401 credential_rejected ; ใส่ api://<client id ของ proxy>/.default ทั้งไฟล์ใช้งานและไฟล์ต้นทาง แล้ว restart"
elif [ -n "$PCID" ] && [ "$sc" != "api://$PCID/.default" ]; then fail "aad.proxy.scope ไม่ตรงกับ client id ของ proxy" "$sc (คาดหวัง api://$PCID/.default)" "ตรวจ azure.entra.client.id ใน $PROXY_PROPS"
elif [[ "$sc" != api://*/.default ]]; then warn "aad.proxy.scope รูปแบบไม่ใช่ api://<id>/.default" "$sc"
else pass "aad.proxy.scope = $sc"; fi
as=$(prop_get "$A" aad.scopes)
echo "$as" | grep -qw offline_access && pass "aad.scopes มี offline_access" || fail "aad.scopes ไม่มี offline_access" "$as" "ไม่มี refresh token → Passthrough ได้ session_expired"
ku=$(prop_get "$AP" app.datamarket.access.key.uuid); ks=$(prop_get "$AP" app.datamarket.access.key.secret)
[ -n "$ku" ] && pass "key DATA-MARKET-ACCESS uuid = $ku" || fail "app.datamarket.access.key.uuid ว่าง" "" "ใส่ key ของ environment นี้ (คู่มือ DEV11 §3.1)"
[ -n "$ks" ] && pass "key DATA-MARKET-ACCESS secret = $(safe_val key.secret "$ks")" || fail "app.datamarket.access.key.secret ว่าง"
DMC=$(prop_get "$AP" app.datamarket.context); info "app.datamarket.context = $DMC"
if [ -n "$CONFIG_SRC" ]; then
  for f in authentication.properties app.properties; do
    s="$CONFIG_SRC/WEB-INF/classes/prop/$f"; [ -r "$s" ] || { warn "ไม่พบไฟล์ต้นทาง $s"; continue; }
    diff -q "$P/$f" "$s" >/dev/null && pass "$f ตรงกับไฟล์ต้นทาง" || warn "$f ต่างจากไฟล์ต้นทาง" "" "deploy ครั้งหน้าไฟล์ต้นทางจะทับ — ตรวจ aad.proxy.scope / key"
  done
  ss_=$(prop_get "$CONFIG_SRC/WEB-INF/classes/prop/authentication.properties" aad.proxy.scope)
  [ "$ss_" = "$sc" ] || fail "ไฟล์ต้นทางมี aad.proxy.scope = ${ss_:-(ว่าง)}" "" "แก้ไฟล์ต้นทางด้วย ไม่งั้นค่าจะหายตอน deploy ครั้งหน้า"
fi
echo "       URL ทั้งหมดใน config ของ portal (ซ่อน credential):"
for f in "$A" "$AP"; do extract_urls "$f" | sed "s#^#         $(basename "$f") : #"; done

# -----------------------------------------------------------------------------
section "4. ทดสอบ URL ที่ใช้จริง"
[ -n "$PORTAL_URL" ] && url_check "$PORTAL_URL/portal/login.html" "หน้า login ของ portal" || skip "URL ของ portal (ไม่ได้ระบุ)"
[ -n "$DMC" ] && url_check "$DMC/" "platform ที่ portal เรียก (app.datamarket.context)"
au=$(prop_get "$A" aad.authority); [ -n "$au" ] && url_check "$au/v2.0/.well-known/openid-configuration" "Entra authority"

# -----------------------------------------------------------------------------
section "5. log ของ portal (catalina.out ตั้งแต่ start ล่าสุด)"
if [ -r "$CATALINA" ]; then
  LSRC=$(log_rot_file "$CATALINA" "Starting service \[Catalina\]") || LSRC=""
  [ -n "$LSRC" ] && [ "$LSRC" != "$CATALINA" ] && info "catalina.out ถูก rotate หลัง Tomcat start — อ่านต่อจาก $LSRC"
  LOGP=$(log_since_last "$CATALINA" "Starting service \[Catalina\]")
  info "Tomcat start ล่าสุด : $(echo "$LOGP" | head -1 | awk '{print $1" "$2}')"
  printf '%s\n' "$LOGP" | grep -E "$CTX|th\.ac\.ddlg|DataService|AAD|AADSTS|entitlement|proxy token|credential_rejected|session_expired" | ev_save catalina_portal_since_last_start.log
  printf '%s\n' "$LOGP" | grep "\[DataServiceDownload\]" | ev_save dataservice_download.log
  e=$(echo "$LOGP" | grep -E "ClassNotFoundException|NoClassDefFoundError" | grep -ci "$CTX\|th\.ac\.ddlg")
  [ "$e" -eq 0 ] && pass "ไม่มี ClassNotFound ของ portal" || fail "ClassNotFound ของ portal $e บรรทัด" "" "WAR ไม่ครบ"
  for pat in "entitlement check answered" "no proxy token" "credential_rejected" "AADSTS" "session_expired"; do
    c=$(echo "$LOGP" | grep -c "$pat")
    [ "$c" -eq 0 ] && pass "ไม่มี \"$pat\"" || warn "\"$pat\" $c ครั้ง" "$(echo "$LOGP" | grep "$pat" | tail -1 | cut -c1-200)" \
      "entitlement=key DATA-MARKET-ACCESS ; credential_rejected=aad.proxy.scope ; AADSTS65001=Entra consent ; AADSTS500011=Application ID URI ; session_expired=offline_access / login ใหม่"
  done
  d=$(echo "$LOGP" | grep "\[DataServiceDownload\]")
  info "การเรียก DataServiceDownload หลัง start : $(echo "$d" | grep -c .) ครั้ง"
  for r in legacy passthrough; do
    ok=$(echo "$d" | grep "download route=$r" | grep -c "result=200"); bad=$(echo "$d" | grep "route=$r" | grep -vc "result=200\|result=ok\|allowed")
    info "  route=$r : download 200 = $ok ครั้ง ; ผลอื่น = $bad ครั้ง"
  done
  echo "$d" | tail -5 | sed -E 's/.*(\[DataServiceDownload\])/         \1/' | cut -c1-220
  [ -z "$d" ] && info "ยังไม่มีการดาวน์โหลดหลัง start — ทดสอบที่หน้า portal แล้วรันซ้ำ"
else fail "อ่าน $CATALINA ไม่ได้"; fi

end_report
