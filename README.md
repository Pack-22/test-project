# cbi-check — ชุดสคริปต์ตรวจความพร้อมของระบบ CUBIKA หลัง deploy

สคริปต์ bash 5 ตัวสำหรับตรวจว่าระบบพร้อมใช้งานหลังอัปเดต release
(ปัจจุบันตั้งค่าคาดหวังไว้ที่ **CUBIKA 9.0.1 RC07 + Data Service Portal SPW-DEV12**)
ใช้กับเครื่องใดก็ได้ — สคริปต์ถาม path ก่อนเริ่มทุกครั้ง

| สคริปต์ | ตรวจอะไร |
|---|---|
| `check-db.sh` | database (MySQL) : จำนวนตาราง, ขนาด, schema ของ release, สิทธิ์ user, ข้อมูลใน `SYS_CONFIG` / ตารางที่ระบุ, เทียบรอบก่อน |
| `check-cubika.sh` | CUBIKA platform (WAR บน Tomcat) : process, สิทธิ์ไฟล์, sha256 / marker ของ build, config ที่ใช้จริง, catalina.out, URL |
| `check-portal.sh` | Data Service Portal (spwportal) : เวอร์ชัน, `aad.*`, `aad.proxy.scope`, key DATA-MARKET-ACCESS, log การดาวน์โหลด |
| `check-enforcer.sh` | Policy enforcer (Data Guard agent) + Gateway : process ตัวเดียว, jar, `enforcer.properties`, datastore, pending-jobs, Gateway กำพร้า, advertisedHost |
| `check-proxy.sh` | DB Security Proxy ที่รันแยก : config ที่ใช้จริง, Entra client id ↔ scope ของ portal, port, DB ปลายทาง, user-mapping, entra-jwt |

หลักการ
- **อ่านอย่างเดียว** — ไม่ stop / start / kill / แก้ไฟล์ของระบบ ; DB ใช้แค่ `SELECT` / `SHOW` ใน session แบบ READ ONLY ([ความปลอดภัย](#ความปลอดภัย))
- **ทุกผลการตรวจเก็บเป็นไฟล์** ในโฟลเดอร์ที่สั่งรันสคริปต์ ([โครงสร้าง](docs/STRUCTURE.md))
- **ค่าลับถูกปิดบางส่วน** ให้เทียบค่าจริงได้ แต่ไม่เห็นค่าเต็ม (ดู [การปิดค่าลับ](#การปิดค่าลับ))
- ระบุวันเวลา / hostname / ผู้รัน ทุกครั้ง

---

## ความต้องการ

| สิ่งที่ต้องมี | ใช้กับ |
|---|---|
| bash 4+, coreutils, grep, sed, awk | ทุกสคริปต์ |
| `ss` (iproute2), `ps`, `pgrep` | process / port |
| `curl` | ทดสอบ URL (ไม่มี = ข้าม) |
| `unzip` | ตรวจ marker ใน jar ของ enforcer / key ใหม่ใน WAR |
| `perl` | ปิดค่าลับแบบบางส่วน (ไม่มี = ซ่อนทั้งหมด) |
| `mysql` client | `check-db.sh` |

ทดสอบบน Ubuntu ; ควรรันด้วย user เดียวกับที่รันบริการ (เช่น `cbiaccess`) เพื่ออ่าน `/proc/<pid>` และ log ได้

## ติดตั้ง

```bash
git clone https://github.com/Pack-22/cbi-check.git /home/cbiaccess/cbi-check
mkdir -p /home/cbiaccess/check          # โฟลเดอร์เก็บผล (แยกจาก repo)
```

## ใช้งาน

```bash
cd /home/cbiaccess/check                # ผลการตรวจจะอยู่ในโฟลเดอร์นี้
/home/cbiaccess/cbi-check/check-db.sh
/home/cbiaccess/cbi-check/check-cubika.sh
/home/cbiaccess/cbi-check/check-portal.sh
/home/cbiaccess/cbi-check/check-enforcer.sh
/home/cbiaccess/cbi-check/check-proxy.sh
```

แต่ละสคริปต์ถาม path ก่อนเริ่ม — กด Enter = ใช้ค่าที่แสดง (enforcer / proxy เดาค่าเริ่มต้นจาก process ที่รันอยู่)

| ตัวเลือก | ความหมาย |
|---|---|
| `-y` | ไม่ถาม ใช้ค่า default หรือค่าจาก environment (เช่น `TOMCAT_HOME=/x ./check-cubika.sh -y`) |
| `-h` | แสดงคำอธิบายของสคริปต์ |

ลำดับที่แนะนำและขั้นตอนเต็ม : [docs/WORKFLOW.md](docs/WORKFLOW.md)

### สิ่งที่แต่ละสคริปต์ถาม

| สคริปต์ | คำถาม (ตัวแปร environment) |
|---|---|
| check-db | `DB_CNF` ไฟล์ `[client]` (ว่าง = กรอก `DB_HOST` / `DB_PORT` / `DB_USER` + password แบบไม่แสดง) · `DB_PICK` database ที่จะตรวจ (ชื่อ / เลข คั่นด้วย `,` / `all`) · `DATA_TABLES` ตารางที่ต้องการดูข้อมูล (ค่าเริ่มต้น `SYS_CONFIG`) · `DATA_LIMIT` จำนวนแถว (200) · `BASELINE` ผลรอบก่อน (เสนอรอบล่าสุดให้เอง) |
| check-cubika | `TOMCAT_HOME` · `CTX` (cubika_9x0) · `WAR_DEPLOYED` · `WAR_ORIGINAL` · `CONFIG_SRC` · `SVC_USER` · `BASE_URL` |
| check-portal | `TOMCAT_HOME` · `CTX` (spwportal) · `WAR_DEPLOYED` · `WAR_ORIGINAL` · `CONFIG_SRC` · `PROXY_PROPS` · `SVC_USER` · `PORTAL_URL` |
| check-enforcer | `AGENT_DIR` · `JAR_NAME` · `CBI_HOME` (~/cbi) · `ENF_LOG` · `SVC_USER` · `PUBLIC_HOST` |
| check-proxy | `PROXY_DIR` · `PROXY_JAR` · `PROXY_CONF` · `PROXY_LOG` · `SVC_USER` · `PORTAL_AUTH` |

## ผลการตรวจ

รัน 1 ครั้ง = 1 โฟลเดอร์ `<สคริปต์>_<hostname>_<YYYYMMDD_HHMMSS>/` ในโฟลเดอร์ที่สั่งรัน

| ไฟล์ | เนื้อหา |
|---|---|
| `summary.txt` | สรุป PASS / WARN / FAIL + รายการที่ FAIL / WARN + สิ่งที่ต้องดูหน้าจอ — **เปิดอันนี้ก่อน** |
| `results.csv` | ผลทีละข้อ : เวลา, ส่วน, สถานะ, ข้อความ, ได้, ดูต่อ (เปิดด้วย Excel ได้) |
| `report.log` | ทุกบรรทัดที่แสดงบนจอ |
| `answers.txt` | ค่า / path ที่ผู้รันระบุ |
| `host.txt` | hostname, IP, OS, timezone, uptime, ดิสก์, หน่วยความจำ |
| `evidence/` | หลักฐานดิบ : config ที่ใช้จริง, log ช่วงที่ตรวจ, process, สิทธิ์ไฟล์, URL, port |
| `db_snapshot/` | (check-db) ตาราง / คอลัมน์ / index / ข้อมูลตาราง — ใช้เป็น baseline รอบถัดไป |

และเพิ่ม 1 แถวใน `cbi-check-history.csv` (ประวัติทุกครั้งที่รัน)
โฟลเดอร์ผลตั้งสิทธิ์ 700 / ไฟล์ 600 อ่านได้เฉพาะผู้รัน — รายละเอียดทุกไฟล์ : [docs/STRUCTURE.md](docs/STRUCTURE.md)

ความหมายสถานะ

| สถานะ | ความหมาย |
|---|---|
| `PASS` | ตรงตามที่คาดหวัง |
| `WARN` | ใช้งานได้ แต่ควรตรวจ / แจ้งทีม |
| `FAIL` | ไม่พร้อม — ทำตามบรรทัด `ดูต่อ:` แล้วรันสคริปต์นั้นซ้ำ |
| `INFO` | ข้อมูลประกอบ |
| `SKIP` | ข้าม (ไม่ได้ระบุ path / ไม่มีเครื่องมือ) |

exit code : `0` = ไม่มี FAIL · `1` = มี FAIL · `2` = ใช้งานผิด / เตรียมไม่ได้

## การปิดค่าลับ

ค่าที่ชื่อ key / คอลัมน์ / ข้อความมีคำว่า `pass`, `pwd`, `secret`, `token`, `credential`, `private`, `apikey`
รวมถึง `user:password@` ใน URL, JWT และ `Bearer …` ถูกปิดก่อนแสดงและก่อนเขียนลงไฟล์ทุกไฟล์

| ความยาวค่า | แสดงเป็น | ตัวอย่าง |
|---|---|---|
| ≥ 16 ตัว | 4 ตัวแรก + `***` + 4 ตัวท้าย (ความยาว) | `abcd***7890(26)` |
| 8 – 15 ตัว | 2 ตัวแรก + `***` + 2 ตัวท้าย (ความยาว) | `S3***PW(8)` |
| < 8 ตัว | ความยาวอย่างเดียว | `***(6)` |

บนจอ ค่าที่ยาว ≥ 16 ตัวมี `sha256:xxxxxxxx` ต่อท้าย ใช้ยืนยันว่าตรงกันทุกตัวอักษร :
`printf '%s' 'ค่าที่มี' | sha256sum | cut -c1-8`

ส่งผลให้คนนอกทีม → ซ่อนทั้งหมด : `MASK_MODE=full ./check-portal.sh`

## ความปลอดภัย

สิ่งที่สคริปต์ **ทำ** กับระบบ — อ่านอย่างเดียวทั้งหมด

| ประเภท | คำสั่ง |
|---|---|
| ไฟล์ | อ่าน config / log / jar (`cat`, `grep`, `sed -n`, `unzip -p`, `sha256sum`, `stat`, `ls`) |
| process | `ps`, `pgrep`, อ่าน `/proc/<pid>/cmdline,cwd,fd/1`, `systemctl status`, `ss -ltn` |
| เครือข่าย | HTTP GET (`curl -m 15`) ไปยัง URL ใน config, เปิด TCP ทดสอบไปปลายทางที่ไม่ใช่ MySQL, `getent` |
| DB | `SELECT` / `SHOW` เท่านั้น ใน session `transaction_read_only=1` + `max_execution_time` |

สิ่งที่สคริปต์ **เขียน** — เฉพาะในโฟลเดอร์ผลการตรวจ (`mkdir`, ไฟล์ผล, `chmod go-rwx` ของโฟลเดอร์ผลเอง)
และไฟล์ credential ชั่วคราวของ check-db (สิทธิ์ 600, ลบเมื่อจบ)

สิ่งที่ **ไม่มี** ในสคริปต์ : `rm` (นอกจากไฟล์ชั่วคราวของตัวเอง), `mv`, `cp`, `kill`, `systemctl start/stop/restart`, `sed -i`,
`chown`, การ redirect เขียนไฟล์นอกโฟลเดอร์ผล, `INSERT/UPDATE/DELETE/ALTER/DROP/CREATE`

ผลทดสอบ 3.1.1 (ระบบจำลอง Tomcat + enforcer + proxy + mysql) : รันครบ 5 สคริปต์ทั้งด้วย root และ user ธรรมดา
→ checksum / mtime / สิทธิ์ของทุกไฟล์ในระบบเหมือนเดิม, process ยังรันครบ, ไม่มีไฟล์ค้างใน `/tmp`,
ทุกการเรียก mysql เป็น read-only, ชื่อตาราง `bad;DROP TABLE x` ถูกปฏิเสธ, ไม่มีค่าลับเต็มในไฟล์ผล

ข้อแนะนำ
- รันด้วย user ที่รันบริการ (เช่น `cbiaccess`) — **ไม่ต้องใช้ root**
- `check-db.sh` ใช้ DB user ที่มีแค่สิทธิ์ `SELECT` ได้ (ส่วนตรวจสิทธิ์จะ WARN ว่า user ที่ใช้ตรวจไม่มี ALTER — ปกติ)
- การนับแถว / ดึงข้อมูลตารางใหญ่ใช้ทรัพยากร DB — รันนอกเวลาใช้งานหนัก ; แต่ละ query หยุดเองเมื่อเกิน `QUERY_TIMEOUT`

## ปรับค่าเมื่อเปลี่ยน release

ค่าคาดหวังอยู่ต้นไฟล์ของแต่ละสคริปต์ แก้ในไฟล์ หรือส่งผ่าน environment

| สคริปต์ | ตัวแปร | ค่าปัจจุบัน |
|---|---|---|
| check-cubika | `EXPECT_WAR_SHA` | sha256 ของ WAR ต้นฉบับ RC07 |
| | `EXPECT_CHANGELOG_TEXT` | `RC07 - 2026-10-28` |
| | `EXPECT_CONNECTOR` / `EXPECT_CONNECTOR_SHA` | `cbi-connector-2.10.2-0503.jar` |
| | `MARKERS` (array ในไฟล์) | ข้อความที่ต้องมีในไฟล์ของ build |
| check-portal | `EXPECT_WAR_SHA` · `EXPECT_STATUS` · `EXPECT_PATCH` | SPW-DEV12 · `SPW-DEV12` · `5` |
| check-enforcer | `EXPECT_JAR_SHA` · `EXPECT_SETTINGS` | jar 0150 · `11` |
| check-db | `KEY_TABLES` · `TOP_TABLES` | ตารางที่นับแถวจริง · 20 |
| ทุกตัว | `REPORT_DIR` | โฟลเดอร์เก็บผล (ค่าเริ่มต้น = โฟลเดอร์ที่รัน) |
| ทุกตัว | `MASK_MODE` | `partial` / `full` |
| ทุกตัว | `LOG_MAX_LINES` | 300000 (บรรทัด log สูงสุดที่โหลด) |
| check-db | `QUERY_TIMEOUT` | 60 วินาทีต่อ query |

เปลี่ยนค่าแล้วบันทึกใน [CHANGELOG.md](CHANGELOG.md) ทุกครั้ง

## ข้อควรระวัง

- repo นี้มีค่าเฉพาะ environment (path, IP, Entra client id) อยู่ในค่า default — **เก็บเป็น private**
- **ห้าม commit โฟลเดอร์ผลการตรวจ** (มี `.gitignore` กันไว้) — รันจากโฟลเดอร์อื่นที่ไม่ใช่ repo
- ส่งผลให้ QA : แนบ `summary.txt` + `results.csv` ก็พอ ; `evidence/` เปิดดูเมื่อ FAIL / WARN
