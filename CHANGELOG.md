# Changelog

รูปแบบตาม [Keep a Changelog](https://keepachangelog.com/) ; เวอร์ชันตาม [SemVer](https://semver.org/)
เวลาเป็น Asia/Bangkok

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
