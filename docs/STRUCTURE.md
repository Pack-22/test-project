# โครงสร้าง

## Repository

```
cbi-check/
├── README.md                วิธีใช้ / ตัวเลือก / การปิดค่าลับ / ค่าคาดหวังของ release
├── CHANGELOG.md             ประวัติการเปลี่ยนแปลง
├── VERSION                  เวอร์ชันของชุดสคริปต์
├── .gitignore               กันโฟลเดอร์ผลการตรวจ / credential ไม่ให้ถูก commit
├── docs/
│   ├── WORKFLOW.md          ขั้นตอนก่อน / หลัง deploy
│   └── STRUCTURE.md         ไฟล์นี้
├── cbi-check-lib.sh         ฟังก์ชันกลาง (ถาม path, รายงาน, results.csv, evidence, ปิดค่าลับ, สิทธิ์ไฟล์, URL)
├── check-db.sh
├── check-cubika.sh
├── check-portal.sh
├── check-enforcer.sh
├── check-proxy.sh
└── check-passthrough.sh     ไล่ทั้ง flow ของ Passthrough (รันบนเครื่อง agent / platform / portal)
```

`check-*.sh` ต้องอยู่โฟลเดอร์เดียวกับ `cbi-check-lib.sh` (หาจากตำแหน่งของสคริปต์เอง — เรียกจากโฟลเดอร์ไหนก็ได้)

## ผลการตรวจ (ในโฟลเดอร์ที่สั่งรัน)

```
/home/cbiaccess/check/                         ← โฟลเดอร์ที่สั่งรัน (หรือ REPORT_DIR)
├── cbi-check-history.csv                      1 แถวต่อการรัน : เวลา, สคริปต์, เครื่อง, OK/WARN/FAIL, จำนวน, โฟลเดอร์
│
├── <สคริปต์>_<host>_<YYYYMMDD_HHMMSS>/          ← ทุกสคริปต์มี 5 ไฟล์นี้
│   ├── summary.txt                            สรุป + รายการ FAIL / WARN + สิ่งที่ต้องดูหน้าจอ
│   ├── results.csv                            ผลทีละข้อ (time, check, section, status, message, got, next)
│   ├── report.log                             ทุกบรรทัดที่แสดงบนจอ
│   ├── answers.txt                            path / ค่าที่ผู้รันตอบ
│   ├── host.txt                               hostname, IP, OS, timezone, uptime, df, free
│   └── evidence/
│
├── db_<host>_<เวลา>/
│   ├── evidence/  databases_visible.txt  permissions.tsv
│   └── db_snapshot/                           ← baseline ของรอบถัดไป
│       ├── server_vars.tsv                    charset, collation, time_zone, sql_mode …
│       ├── grants.txt                         สิทธิ์ของ DB user
│       └── <database>/                        1 โฟลเดอร์ต่อ DB ที่เลือก
│           ├── tables.tsv                     ตาราง, engine, collation, rows, data/index/total MB
│           ├── columns.tsv  column_counts.tsv  indexes.tsv  objects.tsv
│           ├── key_table_counts.tsv           จำนวนแถวจริงของตารางสำคัญ
│           └── data/<ตาราง>.tsv               ข้อมูลตารางที่ระบุ (ค่าเริ่มต้น SYS_CONFIG)
│
├── cubika_<host>_<เวลา>/evidence/
│   ├── config/deployed_*.properties           hibernate, system, app, authentication, ui ที่ใช้จริง
│   ├── config/source_*.properties             ไฟล์ต้นทาง (เมื่อระบุ CONFIG_SRC)
│   ├── config_diff_source_vs_deployed.txt
│   ├── catalina_since_last_start.log  catalina_errors_since_last_start.log
│   ├── changelog.txt  markers.tsv  sha256.txt  ls_web-inf_lib.txt
│   ├── urls_in_config.tsv  urls_tested.tsv  tcp_tested.tsv
│   └── process_java.txt  process_tomcat_cmdline.txt  systemd_tomcat.txt  ports_listen.txt
│       permissions.tsv  ls_webapps.txt  ls_tomcat.txt  disk.txt
│
├── portal_<host>_<เวลา>/evidence/
│   ├── config/deployed_authentication.properties  deployed_app.properties  version.properties  proxy.properties
│   ├── config/source_*.properties  config_diff_source_vs_deployed.txt
│   ├── catalina_portal_since_last_start.log   บรรทัดของ portal / AAD / entitlement
│   ├── dataservice_download.log               [DataServiceDownload] route=legacy|passthrough
│   └── assets_in_html.tsv  sha256.txt  urls_in_config.tsv  urls_tested.tsv  permissions.tsv  ls_portal.txt
│
├── enforcer_<host>_<เวลา>/evidence/
│   ├── config/enforcer.properties  app.properties  gateway_<id>_proxy.properties
│   ├── enforcer_since_last_start.log  enforcer_errors_since_last_start.log  enforcer_tail300.log
│   ├── process_enforcer_<pid>.txt  gateways.tsv  pending_jobs_ls.txt  ls_cbi_home.txt
│   ├── dns_public_host.txt                    (เมื่อระบุ PUBLIC_HOST)
│   └── sha256.txt  markers.tsv  ls_agent_dir.txt  urls_in_config.txt  urls_tested.tsv
│       process_java.txt  ports_listen.txt  permissions.tsv  disk.txt
│
├── passthrough_<host>_<เวลา>/evidence/
│   ├── config/proxy.properties  portal_authentication.properties  portal_app.properties
│   ├── proxy_since_last_start.log  proxy_entra_jwt.log  process_proxy.txt  ports_listen.txt
│   ├── platform_download.log  portal_aad.log
│   └── tcp_tested.tsv  urls_tested.tsv  permissions.tsv
│
└── proxy_<host>_<เวลา>/evidence/
    ├── config/proxy.properties  portal_authentication.properties
    ├── proxy_since_last_start.log  proxy_errors_since_last_start.log
    ├── proxy_auth_mapping.log                 [user-mapping] / [entra-jwt] / [policy-watch]
    └── process_proxy.txt  tcp_tested.tsv  urls_tested.tsv  sha256.txt  urls_in_config.txt
        ports_listen.txt  process_java.txt  permissions.tsv  ls_proxy_dir.txt
```

ไฟล์บางตัวเกิดเฉพาะเมื่อมีข้อมูล (เช่น `source_*` เมื่อระบุโฟลเดอร์ต้นทาง, `gateway_*` เมื่อมี Gateway รันอยู่)

## รูปแบบไฟล์

| ไฟล์ | รูปแบบ |
|---|---|
| `results.csv`, `cbi-check-history.csv` | CSV UTF-8 มี BOM (Excel แสดงภาษาไทยถูก) |
| `*.tsv` | แยกด้วย tab |
| `evidence/config/*` | หัวไฟล์ 3 บรรทัด : `# source`, `# stat` (owner / สิทธิ์ / ขนาด / แก้ล่าสุด), `# sha256` ของไฟล์จริง (ก่อนปิดค่า) |
| `evidence/*.log` | ตัดเฉพาะตั้งแต่ start ล่าสุด สูงสุด 20,000 บรรทัด |

ทุกไฟล์ผ่านการปิดค่าลับก่อนเขียน ; โฟลเดอร์ผลสิทธิ์ 700 / ไฟล์ 600
