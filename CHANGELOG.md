# Changelog

รูปแบบตาม [Keep a Changelog](https://keepachangelog.com/) ; เวอร์ชันตาม [SemVer](https://semver.org/)
เวลาเป็น Asia/Bangkok

## [3.1.4] — 2026-10-29

ปรับจากผลรันจริงบน cbi-dev (รอบ 11:46–12:00)

### Fixed
- catalina.out ถูก rotate ตอนเที่ยงคืน → เดิม FAIL "ไม่มี Server startup in" / "ไม่พบ schema check" ทั้งที่ Tomcat ปกติ ;
  ตอนนี้ตามไปอ่านไฟล์ที่ rotate (`.1`, `-YYYYMMDD`, `.gz`, `catalina.YYYY-MM-DD.log`) ; หาไม่เจอเลย = WARN / SKIP แทน FAIL
- ไฟล์ backup ใน webapps : แยก `.war` / โฟลเดอร์ (Tomcat deploy เป็นแอปจริง) ออกจาก `.zip` / `.bk` (แค่กินพื้นที่) ; แอปที่รู้จักตั้งใน `KNOWN_APPS`
- enforcer : เกณฑ์ดิสก์ตรงกับ cubika (WARN ≥ 80%, FAIL ≥ 95%) และแสดงพื้นที่เหลือ
- enforcer : ทดสอบ URL ใน `app.properties` พร้อมชื่อ key ; ต่อไม่ได้ = WARN (บาง key ไม่ได้ใช้บนเครื่องนี้ — ผลจริงดูที่ `[cred-store]`)
- proxy : อ่าน user ของ process ไม่ได้ → แจ้งชัด (เดิมแสดง user ว่าง)

## [3.1.3] — 2026-10-29

พบจากการรันจริงบน cbi-dev ครั้งแรก

### Fixed
- `check-db.sh` : ต่อ DB ไม่ได้ (เช่น `mysql: [ERROR] ...`) → เดิมเอาข้อความ error ไปแสดงเป็นรายชื่อ database ;
  ตอนนี้แสดง "ต่อ DB ไม่ได้" แล้วรายงาน FAIL ทันที ไม่ถามข้อที่เหลือ (ตรวจจาก exit code / ผลของ `SELECT 1`)
- "ไม่พบโฟลเดอร์เก็บผล" ทั้งที่โฟลเดอร์มีอยู่ — หา path ด้วย `readlink -f` แทน `cd` (ไม่ขึ้นกับ `cd` / `CDPATH` ของ shell ผู้ใช้)
  และแจ้งชัดเมื่อโฟลเดอร์เขียนไม่ได้

### Security
- คำถามที่เว้นว่างได้ (เช่นไฟล์ credential) ไม่รับ path ที่ไม่มีอยู่อีกแล้ว (เดิมตอบ y ใช้ต่อได้) — ถามซ้ำจนได้ path ที่มีจริงหรือว่าง
- ค่าที่ใส่แล้วไม่ใช่ path (เช่นพิมพ์รหัสผ่านผิดช่อง) ไม่ถูกแสดงกลับบนจอ และไม่ถูกบันทึกลง `answers.txt`
- ข้อความ error จาก mysql ผ่านการปิดค่าลับก่อนแสดง / บันทึก

### Changed
- บอกวิธีใช้ช่องถามตั้งแต่ข้อแรก : Enter = ใช้ค่าที่แสดง ; พิมพ์ใหม่ให้กด Ctrl+U ลบก่อน
- `check-db.sh` บอกชัดว่าข้อแรกใส่ path ของไฟล์ credential เท่านั้น

## [3.1.2] — 2026-10-29

### Fixed
- `check-db.sh` : ไม่มี `~/.cubika-db.cnf` → ค่าเริ่มต้นเป็นว่าง (Enter = กรอก host / user / password เอง) แทนการวนถามไฟล์ที่ไม่มี
- คำถามที่เว้นว่างได้ เมื่อ path ไม่พบ แสดงวิธีข้าม (Ctrl+U แล้ว Enter)

## [3.1.1] — 2026-10-29

ตรวจความปลอดภัย : ยืนยันว่าระหว่างรันไม่มีการแก้ไขไฟล์ / process / ข้อมูลใน DB

### Security
- `check-db.sh` เปิดทุก session แบบ **READ ONLY** (`transaction_read_only=1`) และจำกัดเวลา SELECT ละ 60 วินาที (`QUERY_TIMEOUT`)
  ; ตรวจยืนยันกับ server ว่า read_only=1 แล้วรายงานในผล
- `check-db.sh` รับชื่อ database / ตารางเฉพาะ `A-Z a-z 0-9 _ $ -` — กันคำสั่ง SQL แฝงมากับคำตอบ ; `DATA_LIMIT` ต้องเป็นตัวเลข
- ห้ามเก็บผลการตรวจในโฟลเดอร์ของระบบ (`webapps/`, `work/`, `temp/`, `conf/`, `WEB-INF/`, `dataguard/`, `pending-jobs/`, `policycached/`, `cred/`, `/etc`)
  — ป้องกัน Tomcat deploy โฟลเดอร์ผลเป็นแอป / agent อ่านไฟล์แปลกปลอม
- ข้อความบนจอ / `report.log` / `results.csv` ผ่านการปิดค่าลับด้วย (เดิมปิดเฉพาะไฟล์ใน `evidence/`) เช่น `-Dpassword=` ใน command line
- `check-cubika.sh` ตรวจการต่อ DB จาก connection ที่ Tomcat เปิดอยู่แล้ว (`ss`) แทนการเปิด TCP ใหม่
  — MySQL นับ connection ที่ไม่ login เป็น error และอาจ block host (`max_connect_errors`)

### Fixed
- หา process เฉพาะที่เป็น `java` จริง (เดิม `pgrep -f` อาจจับ shell / `tail -f` / `grep` ที่มีข้อความเดียวกัน)
- ข้อมูลตาราง (`SYS_CONFIG`) : แถวที่ key เป็นค่าลับ ปิดคอลัมน์ค่าถูกต้อง (เดิมถ้าค่ามีคำว่า pass อยู่ด้วยจะไม่ถูกปิด)
- password ที่มี `"` `\` `#` ใช้กับไฟล์ credential ชั่วคราวได้
- จำกัดจำนวนบรรทัด log ที่โหลดเข้าหน่วยความจำ (`LOG_MAX_LINES`, 300,000)

## [3.1.0] — 2026-10-29

### Changed
- ค่าลับ (key / secret / password / token) **ปิดบางส่วน** แทนการซ่อนทั้งหมด เพื่อให้เทียบค่าจริงได้
  - ≥ 16 ตัว : `abcd***7890(26)` · 8–15 ตัว : `S3***PW(8)` · < 8 ตัว : `***(6)`
  - บนจอ ค่ายาว ≥ 16 ตัวแสดง `sha256:` 8 ตัวแรกเพิ่ม
  - ใช้กับ config ใน `evidence/`, log, URL, `results.csv` และข้อมูลตารางใน `db_snapshot/`
- `check-portal.sh` แสดงค่า `app.datamarket.access.key.uuid` เต็ม และ secret แบบปิดบางส่วน
- `is_secret_key` ใช้รายการคำเดียวกับการปิดค่าในไฟล์ (`pass|pwd|secret|token|credential|private|apikey`)

### Added
- `MASK_MODE=full` — กลับไปซ่อนทั้งหมด (สำหรับส่งผลให้คนนอกทีม)
- ไม่มี `perl` → ซ่อนทั้งหมดอัตโนมัติ

### Fixed
- ค่าที่ปิดแล้วไม่ถูกปิดซ้ำ (เช่น URL ใน `urls_in_config.tsv`)

## [3.0.0] — 2026-10-29

### Changed
- **ผลการตรวจเก็บในโฟลเดอร์ที่สั่งรันสคริปต์** (เดิม `<โฟลเดอร์สคริปต์>/reports/`)
  รัน 1 ครั้ง = 1 โฟลเดอร์ `<สคริปต์>_<host>_<YYYYMMDD_HHMMSS>/`
- `report.log` ไม่มีรหัสสี
- `check-db.sh` : snapshot ย้ายไปอยู่ใน `<โฟลเดอร์ผล>/db_snapshot/<database>/` ; baseline ระบุเป็นโฟลเดอร์ผลรอบก่อนได้เลย และสคริปต์เสนอรอบล่าสุดให้เอง

### Added
- ทุกผลการตรวจเก็บเป็นไฟล์ : `results.csv` (ทีละข้อ เปิดด้วย Excel ได้), `summary.txt`, `answers.txt`, `host.txt`
- `evidence/` : สำเนา config ที่ใช้จริง (มี path / owner / สิทธิ์ / sha256 กำกับ), log ตั้งแต่ start ล่าสุด, process / cmdline,
  `permissions.tsv`, `urls_tested.tsv`, `tcp_tested.tsv`, `ports_listen.txt`, sha256, marker, รายการไฟล์, diff ไฟล์ต้นทาง ↔ ใช้จริง
- `cbi-check-history.csv` : ประวัติทุกครั้งที่รัน (เวลา, สคริปต์, เครื่อง, ผล, จำนวน PASS / WARN / FAIL, โฟลเดอร์)
- `check-db.sh`
  - เลือก database ที่จะตรวจเมื่อ server มีหลาย DB (ชื่อ / เลข / `all`) และตรวจทีละ DB
  - ดึงข้อมูลจากตาราง `SYS_CONFIG` (หาชื่อตารางแบบไม่สนตัวพิมพ์) + เทียบกับรอบก่อน
  - ระบุตารางที่ต้องการดูข้อมูลเพิ่ม (คั่นด้วย `,`) และจำนวนแถวสูงสุด

## [2.0.0] — 2026-10-28

### Changed
- แยกจากสคริปต์เดียว (`cubika-readiness-check.sh`) เป็น 5 สคริปต์ + `cbi-check-lib.sh`
  : `check-cubika.sh`, `check-portal.sh`, `check-db.sh`, `check-enforcer.sh`, `check-proxy.sh`

### Added
- ถาม path ก่อนเริ่มทุกสคริปต์ (WAR / โฟลเดอร์ agent / config) ; `-y` = ไม่ถาม
- ตรวจ hostname / FQDN / IP / OS / timezone / ผู้รัน และระบุวันเวลาที่ตรวจ + ระยะเวลา
- ตรวจสิทธิ์ไฟล์ (owner, ไฟล์ที่มี secret ห้าม o+r, โฟลเดอร์ที่บริการต้องเขียน)
- ตรวจ URL ที่ใช้จริงใน config (ซ่อน credential) + ทดสอบ HTTP / TCP
- enforcer : process ตัวเดียว, Gateway กำพร้า (PPID=1), systemd, advertisedHost
- proxy : config ที่ process ใช้จริง, `aad.proxy.scope` ↔ client id, port ชน, user-mapping, entra-jwt

## [1.0.0] — 2026-10-28

### Added
- `cubika-readiness-check.sh` สคริปต์เดียว (baseline / check / sample-conf) สำหรับ RC07 + SPW-DEV12 บน cbi-dev
