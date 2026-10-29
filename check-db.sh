#!/usr/bin/env bash
# =============================================================================
#  check-db.sh — ตรวจ database ของ CUBIKA (MySQL) : ตาราง / ขนาด / schema ของ release / สิทธิ์ user
#                 + ดึงข้อมูลจากตารางที่ระบุ (ค่าเริ่มต้น SYS_CONFIG)
#
#  ถามก่อนเริ่ม : ไฟล์ credential ของ mysql (หรือ host/port/user แล้วถาม password แบบไม่แสดง),
#                 database ที่จะตรวจ (เลือกได้หลายตัว เมื่อ server มีหลาย database),
#                 ตารางที่ต้องการดูข้อมูล + จำนวนแถวสูงสุด, โฟลเดอร์ snapshot ก่อนหน้า (baseline)
#  ตรวจ        : hostname/เวลา, การเชื่อมต่อ, ค่า server, สิทธิ์ของ user, จำนวนตาราง / ขนาดรวม /
#                 ตารางใหญ่สุด, engine / collation, คอลัมน์+index ของ RC01, ordinal,
#                 ข้อมูลในตารางที่ระบุ (ซ่อนค่าลับ), เทียบ baseline (รวมข้อมูลของตารางที่ระบุ)
#  บันทึก       : <โฟลเดอร์ที่รันสคริปต์>/db_<host>_<เวลา>/ (report.log, results.csv, summary.txt)
#                 และ …/db_snapshot/<database>/ (ใช้เป็น baseline รอบถัดไป : ระบุโฟลเดอร์ db_<host>_<เวลา> ของรอบก่อน)
#
#  ใช้   : ./check-db.sh   |  ./check-db.sh -y
#  อ่านอย่างเดียว — มีแต่ SELECT / SHOW
#  ค่าลับ : คอลัมน์ / แถวที่มีคำว่า password, secret, pwd, token, apikey, private, credential
#           ถูกปิดบางส่วน เช่น fd64***a147(36) ; สั้นกว่า 8 ตัว = ***(n) ; MASK_MODE=full = ซ่อนทั้งหมด
# =============================================================================
SCRIPT_DIR=$(dirname "$(readlink -f -- "$0")")
. "$SCRIPT_DIR/cbi-check-lib.sh" || { echo "ไม่พบ cbi-check-lib.sh ใน $SCRIPT_DIR"; exit 2; }
REPORT_DIR="${REPORT_DIR:-$PWD}"     # ผลการตรวจเก็บในโฟลเดอร์ที่รันสคริปต์
parse_common_args "$@"
have mysql || { echo "ไม่มีคำสั่ง mysql (apt-get install mysql-client)"; exit 2; }

TOP_TABLES="${TOP_TABLES:-20}"
KEY_TABLES=( ${KEY_TABLES:-DGD_POLICY DGD_USER DGD_USR_ROLE DAS_DAQ_TECHNICAL DAS_DAQ_ISSUE DAS_DAQ_QUARANTINE} )
SECRET_RE='pass|pwd|secret|token|apikey|api_key|private|credential'
SCREEN_WIDTH="${SCREEN_WIDTH:-60}"      # ความยาวสูงสุดของแต่ละช่องตอนแสดงบนจอ (ไฟล์ snapshot เก็บเต็ม)

# ---------- credential ----------
echo "=== ตรวจ Database ของ CUBIKA — ระบุค่า (Enter = ใช้ค่าที่แสดง) ==="
echo "ข้อแรกใส่ path ของไฟล์ credential เท่านั้น — ไม่มีไฟล์ให้กด Enter แล้วสคริปต์จะถาม host / port / user / password แยกทีละข้อ"
DEF_CNF=""; [ -f "$HOME/.cubika-db.cnf" ] && DEF_CNF="$HOME/.cubika-db.cnf"
ask DB_CNF "ไฟล์ credential mysql [client] (ว่าง = กรอก host/user/password เอง)" "$DEF_CNF" "file?"
TMPCNF=""
if [ -z "$DB_CNF" ]; then
  ask DB_HOST "DB host" "127.0.0.1" text; ask DB_PORT "DB port" "3306" text; ask DB_USER "DB user" "" text
  read -r -s -p "DB password (ไม่แสดง) : " DB_PASS </dev/tty; echo
  TMPCNF=$(mktemp); chmod 600 "$TMPCNF"; trap 'rm -f "$TMPCNF"' EXIT
  esc=${DB_PASS//\\/\\\\}; esc=${esc//\"/\\\"}
  printf '[client]\nhost=%s\nport=%s\nuser=%s\npassword="%s"\n' "$DB_HOST" "$DB_PORT" "$DB_USER" "$esc" > "$TMPCNF"; unset esc
  unset DB_PASS; DB_CNF="$TMPCNF"
fi
CUR_DB=""
# ทุก session เปิดแบบ READ ONLY (server ปฏิเสธ INSERT/UPDATE/DELETE/DDL) + จำกัดเวลา SELECT ละไม่เกิน QUERY_TIMEOUT วินาที
QUERY_TIMEOUT="${QUERY_TIMEOUT:-60}"
RO_INIT=""; RO_MODE="ไม่ได้ตั้ง"
_my() { mysql --defaults-extra-file="$DB_CNF" ${RO_INIT:+--init-command="$RO_INIT"} ${CUR_DB:+-D "$CUR_DB"} "$@" 2>&1; }
for cand in "SET SESSION transaction_read_only=1, SESSION max_execution_time=$((QUERY_TIMEOUT*1000))" \
            "SET SESSION tx_read_only=1, SESSION max_execution_time=$((QUERY_TIMEOUT*1000))" \
            "SET SESSION transaction_read_only=1" "SET SESSION tx_read_only=1"; do
  if mysql --defaults-extra-file="$DB_CNF" --init-command="$cand" -N -B -e "SELECT 1;" >/dev/null 2>&1; then RO_INIT="$cand"; RO_MODE="$cand"; break; fi
done
q()  { _my -N -B -e "$1"; }   # ไม่มีหัวคอลัมน์
qh() { _my -B -e "$1"; }      # มีหัวคอลัมน์
IDENT_RE='^[A-Za-z0-9_$-]{1,64}$'   # ชื่อ database / ตารางที่ยอมรับ (กันคำสั่ง SQL แฝงมากับคำตอบ)

# ---------- เลือก database ----------
CONN_ERR=""; DB_ALL=()
r=$(q "SELECT 1;")
if [ "$r" != "1" ]; then CONN_ERR=$(_m "$r" | head -3)
  echo "ต่อ DB ไม่ได้ :"; echo "$CONN_ERR" | sed 's/^/   /'; DATA_TABLES=""; DATA_LIMIT=200; BASELINE=""
else
  mapfile -t DB_ALL < <(q "SHOW DATABASES;" | grep -vxE 'information_schema|performance_schema|mysql|sys')
  DEF_DB=$(q "SELECT IFNULL(DATABASE(),'');")
  if [ "${#DB_ALL[@]}" -gt 0 ] && [ "$ASSUME_YES" != "1" ]; then
    echo "database บน server นี้ (ที่ user มองเห็น) :"
    i=0; for d in "${DB_ALL[@]}"; do i=$((i+1)); printf '   %2d) %s\n' "$i" "$d"; done
  fi
  [ -z "$DEF_DB" ] && [ "${#DB_ALL[@]}" -eq 1 ] && DEF_DB="${DB_ALL[0]}"
  ask DB_PICK "database ที่จะตรวจ (ชื่อหรือเลข คั่นด้วย , ; all = ทุกตัว)" "$DEF_DB" text
fi
[ -z "$CONN_ERR" ] && ask DATA_TABLES "ตารางที่ต้องการดูข้อมูล (คั่นด้วย , ; ว่าง = ไม่ดู)" "SYS_CONFIG" "text?"
[ -z "$CONN_ERR" ] && ask DATA_LIMIT  "จำนวนแถวสูงสุดต่อตาราง"                       "200" text
LAST_DB=$(ls -1d "$PWD"/db_*_*/db_snapshot 2>/dev/null | sort | tail -1 | xargs -r dirname)
[ -z "$CONN_ERR" ] && ask BASELINE    "โฟลเดอร์ผลการตรวจ DB รอบก่อนเพื่อเทียบ (ว่าง = ไม่เทียบ)" "$LAST_DB" "dir?"

# แปลงคำตอบเป็นรายชื่อ database
DBS=()
if [ -n "${DB_PICK:-}" ]; then
  if [ "$DB_PICK" = "all" ]; then DBS=("${DB_ALL[@]}")
  else
    IFS=',' read -ra picks <<<"$DB_PICK"
    for p in "${picks[@]}"; do p=$(echo "$p" | tr -d ' '); [ -z "$p" ] && continue
      if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le "${#DB_ALL[@]}" ]; then p="${DB_ALL[$((p-1))]}"; fi
      [[ "$p" =~ $IDENT_RE ]] && DBS+=("$p") || echo "  ข้ามชื่อ database ที่ไม่ถูกต้อง: $p"
    done
  fi
fi
IFS=',' read -ra DTABLES <<<"${DATA_TABLES:-}"
[[ "$DATA_LIMIT" =~ ^[0-9]+$ ]] && [ "$DATA_LIMIT" -ge 1 ] || DATA_LIMIT=200

start_report "db"
print_answers
SNAP_ROOT="$OUT_DIR/db_snapshot"; mkdir -p "$SNAP_ROOT"
[ -n "$BASELINE" ] && [ -d "$BASELINE/db_snapshot" ] && BASELINE="$BASELINE/db_snapshot"

# ---------- ช่วยแสดงข้อมูลตาราง (ซ่อนค่าลับ) ----------
# mask_tsv : อ่าน TSV ที่มีหัวคอลัมน์ → ซ่อนคอลัมน์ที่ชื่อเป็นค่าลับ และแถวที่มีคำว่าเป็นค่าลับ
mask_tsv() {
  awk -F'\t' -v OFS='\t' -v re="$SECRET_RE" -v full="$([ "$MASK_MODE" = full ] && echo 1 || echo 0)" '
    function m(v,  n){ n=length(v); if (v=="" || v=="NULL") return v
      if (full || n<8) return "***(" n ")"
      if (n<16) return substr(v,1,2) "***" substr(v,n-1,2) "(" n ")"
      return substr(v,1,4) "***" substr(v,n-3,4) "(" n ")" }
    NR==1 { for(i=1;i<=NF;i++) { h=tolower($i); sec[i]=(h ~ re)
              kc[i]=(h ~ /(^|_)(id|key|name|code|param|parameter|prop|property|type|group|module|category)s?$/) }
            print; next }
    { hit=0; for(i=1;i<=NF;i++) if (kc[i] && tolower($i) ~ re) hit=1
      for(i=1;i<=NF;i++){
        if (sec[i]) $i=m($i)                                  # คอลัมน์ที่ชื่อเป็นค่าลับ
        else if (!kc[i] && (hit || tolower($i) ~ re)) $i=m($i)  # แถวที่ key เป็นค่าลับ → ปิดคอลัมน์ค่า
      }
      print }'
}
show_tsv() {   # แสดง TSV บนจอแบบตัดความยาว
  awk -F'\t' -v w="$SCREEN_WIDTH" -v OFS=' | ' '{ for(i=1;i<=NF;i++){ if(length($i)>w) $i=substr($i,1,w-1) "…" } ; $1=$1; print "         " $0 }'
}

# =============================================================================
section "1. การเชื่อมต่อ / ค่า server"
[ -z "$TMPCNF" ] && perm_check "$DB_CNF" "$(id -un)" yes no "ไฟล์ credential $DB_CNF"
if [ -n "$CONN_ERR" ]; then fail "ต่อ DB ไม่ได้" "$CONN_ERR" "ตรวจ host / user / password / firewall"; end_report; fi
r=$(q "SELECT CURRENT_USER(), @@hostname, @@port, VERSION();"); read -r DBU DBH DBP DBV <<<"$(echo "$r" | tr '\t' ' ')"
pass "ต่อ DB ได้ : user=$DBU server=$DBH:$DBP MySQL $DBV"
ROV=$(q "SELECT @@session.transaction_read_only;" 2>/dev/null); echo "$ROV" | grep -q '^1$' || ROV=$(q "SELECT @@session.tx_read_only;" 2>/dev/null)
[ -n "$RO_INIT" ] && echo "$ROV" | grep -q '^1$' && pass "session ตรวจเป็นแบบ READ ONLY — server ยืนยัน read_only=1 (แก้ข้อมูลไม่ได้)" "$RO_MODE" \
  || warn "เปิด session แบบ READ ONLY ไม่ได้" "" "สคริปต์ใช้แค่ SELECT/SHOW อยู่แล้ว ; แนะนำใช้ DB user ที่มีแค่สิทธิ์ SELECT"
info "database ที่ user มองเห็น (${#DB_ALL[@]}) : ${DB_ALL[*]}"
[ "${#DBS[@]}" -eq 0 ] && { fail "ไม่ได้เลือก database ที่จะตรวจ"; end_report; }
info "database ที่จะตรวจ : ${DBS[*]}"
printf "%s\n" "${DB_ALL[@]}" | ev_save databases_visible.txt
q "SELECT 'lower_case_table_names',@@lower_case_table_names UNION ALL SELECT 'character_set_server',@@character_set_server
   UNION ALL SELECT 'collation_server',@@collation_server UNION ALL SELECT 'time_zone',@@time_zone
   UNION ALL SELECT 'system_time_zone',@@system_time_zone UNION ALL SELECT 'max_allowed_packet',@@max_allowed_packet
   UNION ALL SELECT 'innodb_default_row_format',@@innodb_default_row_format UNION ALL SELECT 'sql_mode',@@sql_mode;" \
 | tee "$SNAP_ROOT/server_vars.tsv" | awk -F'\t' '{printf "[INFO] %-28s = %s\n",$1,$2}'
info "เวลา DB = $(q "SELECT NOW();")  ; เวลาเครื่องที่รันสคริปต์ = $(date '+%F %T')"
GRANTS=$(q "SHOW GRANTS;"); echo "$GRANTS" | sed 's/IDENTIFIED BY.*//' > "$SNAP_ROOT/grants.txt"
echo "       สิทธิ์ของ $DBU :"; sed 's/^/         /' "$SNAP_ROOT/grants.txt"

# =============================================================================
for CUR_DB in "${DBS[@]}"; do
SNAP="$SNAP_ROOT/$CUR_DB"; mkdir -p "$SNAP"
BL=""; if [ -n "$BASELINE" ]; then
  if [ -r "$BASELINE/$CUR_DB/tables.tsv" ]; then BL="$BASELINE/$CUR_DB"
  elif [ -r "$BASELINE/tables.tsv" ] && [ "${#DBS[@]}" -eq 1 ]; then BL="$BASELINE"; fi
fi

section "DATABASE : $CUR_DB"
ok=$(q "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$CUR_DB';")
if [ "$ok" != "1" ]; then fail "ไม่พบ database $CUR_DB (หรือ user ไม่มีสิทธิ์)" "$ok"; continue; fi
dbcs=$(q "SELECT CONCAT(default_character_set_name,' / ',default_collation_name) FROM information_schema.schemata WHERE schema_name=DATABASE();")
info "charset / collation = $dbcs"
echo "$dbcs" | grep -q utf8mb4 || warn "$CUR_DB ไม่ได้ใช้ utf8mb4" "$dbcs" "ภาษาไทย / emoji อาจเพี้ยน"

# -----------------------------------------------------------------------------
section "[$CUR_DB] 2. สิทธิ์ของ DB user (Hibernate ต้องสร้าง/แก้ตารางได้)"
if echo "$GRANTS" | grep -qiE "ALL PRIVILEGES ON (\`?$CUR_DB\`?|\*)\.\*"; then pass "user มี ALL PRIVILEGES บน $CUR_DB"
else for p in SELECT INSERT UPDATE DELETE CREATE ALTER INDEX; do
  echo "$GRANTS" | grep -qiE "GRANT .*\b$p\b.* ON (\`?$CUR_DB\`?|\*)\.\*" && pass "สิทธิ์ $p" \
    || warn "ไม่เห็นสิทธิ์ $p บน $CUR_DB (ของ user ที่ใช้ตรวจ)" "" "ถ้าเป็น user เดียวกับที่แอปใช้ : GRANT $p ON $CUR_DB.* — ไม่มี ALTER/INDEX คอลัมน์ใหม่ของ release จะไม่ถูกสร้าง"
done; fi

# -----------------------------------------------------------------------------
section "[$CUR_DB] 3. จำนวนตาราง / ขนาด"
q "SET SESSION information_schema_stats_expiry=0;
   SELECT table_name, IFNULL(engine,'-'), IFNULL(table_collation,'-'), table_rows,
          ROUND(data_length/1024/1024,2), ROUND(index_length/1024/1024,2), ROUND((data_length+index_length)/1024/1024,2), ROUND(data_free/1024/1024,2)
   FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE' ORDER BY table_name;" > "$SNAP/tables.tsv"
q "SELECT table_name, COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() GROUP BY table_name ORDER BY table_name;" > "$SNAP/column_counts.tsv"
q "SELECT table_name, column_name, column_type, is_nullable FROM information_schema.columns WHERE table_schema=DATABASE() ORDER BY table_name, column_name;" > "$SNAP/columns.tsv"
q "SELECT table_name, index_name, GROUP_CONCAT(column_name ORDER BY seq_in_index), non_unique FROM information_schema.statistics WHERE table_schema=DATABASE() GROUP BY table_name,index_name,non_unique ORDER BY 1,2;" > "$SNAP/indexes.tsv"
q "SELECT 'VIEW',table_name FROM information_schema.views WHERE table_schema=DATABASE()
   UNION ALL SELECT routine_type,routine_name FROM information_schema.routines WHERE routine_schema=DATABASE()
   UNION ALL SELECT 'TRIGGER',trigger_name FROM information_schema.triggers WHERE trigger_schema=DATABASE() ORDER BY 1,2;" > "$SNAP/objects.tsv"
TN=$(grep -c . "$SNAP/tables.tsv")
read -r DMB IMB TMB FMB <<<"$(awk -F'\t' '{d+=$5;i+=$6;t+=$7;f+=$8} END{printf "%.1f %.1f %.1f %.1f",d,i,t,f}' "$SNAP/tables.tsv")"
pass "จำนวนตาราง = $TN ; view/routine/trigger = $(grep -c . "$SNAP/objects.tsv")"
info "ขนาด : data ${DMB} MB + index ${IMB} MB = รวม ${TMB} MB (พื้นที่ว่างในไฟล์ ${FMB} MB)"
info "จำนวนแถวรวมโดยประมาณ = $(awk -F'\t' '{s+=$4} END{print s+0}' "$SNAP/tables.tsv")"
echo "       ตารางใหญ่สุด $TOP_TABLES อันดับ :"
printf '         %-42s %12s %10s %10s %10s\n' TABLE ROWS~ DATA_MB INDEX_MB TOTAL_MB
sort -t$'\t' -k7 -g -r "$SNAP/tables.tsv" | head -"$TOP_TABLES" | awk -F'\t' '{printf "         %-42s %12s %10s %10s %10s\n",$1,$4,$5,$6,$7}'
ne=$(awk -F'\t' '$2!="InnoDB"{print $1"("$2")"}' "$SNAP/tables.tsv" | tr '\n' ' ')
[ -z "$ne" ] && pass "ทุกตารางเป็น InnoDB" || warn "ตารางที่ไม่ใช่ InnoDB" "$ne"
nc=$(cut -f3 "$SNAP/tables.tsv" | sort | uniq -c | sort -rn); info "collation ของตาราง : $(echo "$nc" | tr -s ' ' | tr '\n' ';')"
[ "$(echo "$nc" | grep -c .)" -le 1 ] && pass "ทุกตารางใช้ collation เดียวกัน" || warn "ตารางใช้ collation หลายแบบ" "" "join / เรียงข้อมูลภาษาไทยอาจเพี้ยน — ถาม dev"
info "ตารางที่ไม่มีข้อมูล (rows~0) = $(awk -F'\t' '$4==0' "$SNAP/tables.tsv" | grep -c .) ตาราง"
echo "       จำนวนแถวจริงของตารางสำคัญ :"
: > "$SNAP/key_table_counts.tsv"
for t in "${KEY_TABLES[@]}"; do
  n=$(q "SELECT COUNT(*) FROM \`$t\`;"); echo "$n" | grep -qi error && n="(ไม่มีตาราง)"
  printf '         %-30s %s\n' "$t" "$n"; printf '%s\t%s\n' "$t" "$n" >> "$SNAP/key_table_counts.tsv"
done

# -----------------------------------------------------------------------------
section "[$CUR_DB] 4. schema ของ release (RC01 ขึ้นไป)"
if [ "$(q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='DAS_DAQ_TECHNICAL';")" != "1" ]; then
  skip "ไม่มีตาราง DAS_DAQ_TECHNICAL — database นี้อาจไม่ใช่ของ CUBIKA"
else
  c4=$(q "SELECT GROUP_CONCAT(CONCAT(column_name,' ',column_type,' ',is_nullable) ORDER BY column_name SEPARATOR ' | ') FROM information_schema.columns
          WHERE table_schema=DATABASE() AND table_name='DAS_DAQ_TECHNICAL' AND column_name IN ('DQT_RULE_TOTAL_TYPE','DQT_RULE_TOTAL_QUERY','DQT_THRESHOLD_OPERATOR','DQT_TARGET_OPERATOR');")
  n4=$(echo "$c4" | tr '|' '\n' | grep -c DQT_)
  [ "$n4" = "4" ] && pass "คอลัมน์ RC01 ครบ 4" "$c4" || fail "คอลัมน์ RC01 มี $n4/4" "$c4" "Tomcat ยังไม่เคย start ด้วย WAR RC01+ / hbm2ddl.auto ไม่ใช่ update / user ไม่มี ALTER — SQL สำรองในคู่มือ RC01 §3.4"
  i3=$(q "SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='DAS_DAQ_TECHNICAL' AND index_name IN ('IDX_DQT_RULE_TOTAL_TYPE','IDX_DQT_THRESHOLD_OPERATOR','IDX_DQT_TARGET_OPERATOR');")
  [ "$i3" = "3" ] && pass "index RC01 ครบ 3 (ไม่มี IDX_DQT_RULE_TOTAL_QUERY = ปกติ)" || warn "index RC01 มี $i3/3" "" "SQL สำรองในคู่มือ RC01 §3.4"
  st=$(q "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='DAS_DAQ_TECHNICAL' AND column_name IN ('ALL','GT','GTE','LT','LTE','EQ');")
  [ "$st" = "0" ] && pass "ไม่มีคอลัมน์ค้างของ PR 5837" || warn "มีคอลัมน์ค้างของ PR 5837 ($st)" "" "nullable ไม่กระทบ — แจ้ง QA / dev"
  om=$(q "SELECT GREATEST(IFNULL((SELECT MAX(DQI_SEVERITY) FROM DAS_DAQ_ISSUE),0), IFNULL((SELECT MAX(DQQ_STATUS) FROM DAS_DAQ_QUARANTINE),0));")
  if echo "$om" | grep -qi error; then warn "อ่าน ordinal ไม่ได้" "$om"
  elif [ "${om:-0}" -ge 3 ] 2>/dev/null; then warn "ordinal สูงสุด = $om (มีข้อมูลจาก 9.1)" "" "ห้าม rollback WAR ไปก่อน RC01 บน DB นี้"
  else pass "ordinal ของ DQ Issue / Quarantine สูงสุด = $om (rollback ได้)"; fi
fi

# -----------------------------------------------------------------------------
section "[$CUR_DB] 5. ข้อมูลในตารางที่ระบุ"
if [ "${#DTABLES[@]}" -eq 0 ]; then skip "ไม่ได้ระบุตาราง"
else
  mkdir -p "$SNAP/data"
  for t in "${DTABLES[@]}"; do
    t=$(echo "$t" | tr -d ' '); [ -z "$t" ] && continue
    [[ "$t" =~ $IDENT_RE ]] || { warn "ข้ามชื่อตารางที่ไม่ถูกต้อง: $t" "" "ใช้ได้เฉพาะ A-Z a-z 0-9 _ \$ -"; continue; }
    real=$(q "SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE() AND LOWER(table_name)=LOWER('$t') LIMIT 1;")
    if [ -z "$real" ] || echo "$real" | grep -qi error; then warn "ไม่มีตาราง $t ใน $CUR_DB"; continue; fi
    cnt=$(q "SELECT COUNT(*) FROM \`$real\`;")
    cols=$(q "SELECT GROUP_CONCAT(column_name ORDER BY ordinal_position SEPARATOR ', ') FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='$real';")
    upd=$(q "SELECT IFNULL(update_time,'-') FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='$real';")
    echo; info "ตาราง $real : $cnt แถว ; แก้ล่าสุด (ตาม MySQL) $upd"
    info "คอลัมน์ : $cols"
    out="$SNAP/data/$real.tsv"
    qh "SELECT * FROM \`$real\` ORDER BY 1 LIMIT $DATA_LIMIT;" | mask_tsv > "$out"
    if head -1 "$out" | grep -qi "^ERROR"; then fail "อ่านข้อมูล $real ไม่ได้" "$(head -1 "$out")"; continue; fi
    nsec=$(tail -n +2 "$out" | grep -c '\*\*\*(')
    show_tsv < "$out"
    [ "$cnt" -gt "$DATA_LIMIT" ] 2>/dev/null && info "แสดง $DATA_LIMIT จาก $cnt แถว (เพิ่ม/ลดได้ที่คำถาม 'จำนวนแถวสูงสุด')"
    [ "$nsec" -gt 0 ] && info "ซ่อนค่าลับใน $nsec แถว (ไฟล์ snapshot ก็ถูกซ่อน)"
    pass "บันทึกข้อมูล $real → $out"
    # เทียบกับ baseline
    if [ -n "$BL" ] && [ -r "$BL/data/$real.tsv" ]; then
      d=$(diff "$BL/data/$real.tsv" "$out" | grep '^[<>]')
      if [ -z "$d" ]; then pass "ข้อมูล $real เหมือนก่อนหน้า (ภายใน $DATA_LIMIT แถวแรก)"
      else warn "ข้อมูล $real เปลี่ยนจากก่อนหน้า $(echo "$d" | grep -c .) บรรทัด (< ก่อน / > ตอนนี้)" "" "ตรวจว่าเป็นการเปลี่ยนที่ตั้งใจ (config ของระบบ)"
           echo "$d" | head -30 | sed 's/\t/ | /g; s/^/         /'; fi
    fi
  done
fi

# -----------------------------------------------------------------------------
section "[$CUR_DB] 6. เทียบกับ snapshot ก่อนหน้า"
if [ -n "$BL" ]; then
  info "baseline : $BL"
  BT=$(grep -c . "$BL/tables.tsv")
  mis=$(comm -23 <(cut -f1 "$BL/tables.tsv" | sort) <(cut -f1 "$SNAP/tables.tsv" | sort) | tr '\n' ' ')
  add=$(comm -13 <(cut -f1 "$BL/tables.tsv" | sort) <(cut -f1 "$SNAP/tables.tsv" | sort) | tr '\n' ' ')
  info "จำนวนตาราง : ก่อน $BT → ตอนนี้ $TN"
  [ -z "$mis" ] && pass "ไม่มีตารางหาย" || fail "ตารางหาย" "$mis" "หยุดใช้งาน — ตรวจว่าแอปต่อ DB ถูกตัว / มีคนลบ"
  [ -z "$add" ] && pass "ไม่มีตารางเพิ่ม" || warn "ตารางเพิ่ม" "$add" "entity ใหม่ที่ Hibernate สร้าง — ถาม dev"
  dc=$(diff "$BL/columns.tsv" "$SNAP/columns.tsv" 2>/dev/null | grep '^[<>]')
  [ -z "$dc" ] && pass "คอลัมน์ทุกตารางเหมือนเดิม" || { info "คอลัมน์ที่เปลี่ยน (< ก่อน / > ตอนนี้) $(echo "$dc" | grep -c .) บรรทัด:"; echo "$dc" | head -20 | sed 's/^/         /'; }
  di=$(diff "$BL/indexes.tsv" "$SNAP/indexes.tsv" 2>/dev/null | grep '^[<>]')
  [ -z "$di" ] && pass "index ทุกตารางเหมือนเดิม" || { warn "index เปลี่ยน $(echo "$di" | grep -c .) บรรทัด"; echo "$di" | head -10 | sed 's/^/         /'; }
  if [ -r "$BL/key_table_counts.tsv" ]; then
    while IFS=$'\t' read -r t nb; do
      nn=$(awk -F'\t' -v t="$t" '$1==t{print $2}' "$SNAP/key_table_counts.tsv")
      if [[ "$nb" =~ ^[0-9]+$ && "$nn" =~ ^[0-9]+$ ]] && [ "$nn" -lt "$nb" ]; then warn "$t แถวลดลง $nb → $nn" "" "การ deploy ไม่ลบข้อมูล — มีคนลบ / ต่อ DB ผิด"
      else info "$t : $nb → $nn"; fi
    done < "$BL/key_table_counts.tsv"
  fi
  printf '         %-42s %10s %10s\n' TABLE ก่อน_MB ตอนนี้_MB
  join -t $'\t' <(cut -f1,7 "$BL/tables.tsv" | sort) <(cut -f1,7 "$SNAP/tables.tsv" | sort) \
   | sort -t$'\t' -k3 -g -r | head -10 | awk -F'\t' '{printf "         %-42s %10s %10s\n",$1,$2,$3}'
elif [ -n "$BASELINE" ]; then warn "ไม่พบ baseline ของ $CUR_DB ใน $BASELINE" "" "เลือกโฟลเดอร์ db_<host>_<เวลา> ของรอบก่อนที่ตรวจ $CUR_DB"
else info "ไม่ได้ระบุ baseline"; fi
done
# =============================================================================
section "snapshot"
info "$SNAP_ROOT  (โฟลเดอร์ย่อยต่อ database : tables / columns / indexes / objects / key_table_counts / data/<ตาราง>.tsv)"
info "รอบถัดไปใช้เป็น baseline ได้ : ระบุ $OUT_DIR ที่คำถาม baseline (สคริปต์เสนอรอบล่าสุดให้เอง)"

end_report
