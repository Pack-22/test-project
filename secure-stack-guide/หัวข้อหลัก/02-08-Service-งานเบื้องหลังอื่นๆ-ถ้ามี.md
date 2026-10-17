## 8. Service / งานเบื้องหลังอื่นๆ (ถ้ามี)

ใช้รูปแบบเดียวกันซ้ำได้ทุก service — หลักการ 4 ข้อ:

1. **1 service = 1 user เฉพาะ (nologin) ไม่แชร์กัน** — service ไหนโดนเจาะก็ไม่ลามถึงตัวอื่น
2. **รันผ่าน systemd ที่ harden** ไม่รันด้วย root และไม่ปล่อยค้างใน screen/tmux
3. **network service → bind `127.0.0.1`** และ UFW ปิดพอร์ตไว้ (ให้คุยผ่าน Nginx/localhost เท่านั้น)
4. **งานตามเวลา → ใช้ systemd timer** (ดีกว่า cron: log รวมใน journald, คุม user/สิทธิ์ได้)

**สร้าง user + วางไฟล์**
```bash
sudo useradd --system --create-home --home-dir /opt/worker \
     --shell /usr/sbin/nologin worker
sudo chown -R worker:worker /opt/worker
```

**systemd unit (template ที่ harden)** — `/etc/systemd/system/worker.service`
```ini
[Unit]
Description=Background worker
# รอ network พร้อมก่อนสตาร์ท
After=network.target

[Service]
# รันด้วย user เฉพาะ (nologin) ไม่ใช่ root
User=worker
Group=worker
WorkingDirectory=/opt/worker
ExecStart=/opt/worker/run.sh
# ตายผิดปกติ → สตาร์ทใหม่
Restart=on-failure

# --- hardening ---
# ห้าม process ยกระดับสิทธิ์ตัวเอง
NoNewPrivileges=true
# ทั้งระบบเป็น read-only สำหรับ process นี้
ProtectSystem=strict
# มองไม่เห็น /home
ProtectHome=true
# /tmp แยกของตัวเอง (process อื่นไม่เห็น)
PrivateTmp=true
# เขียนได้เฉพาะโฟลเดอร์นี้ (ข้อยกเว้นของ ProtectSystem)
ReadWritePaths=/opt/worker/data
# ตัด capability พิเศษทั้งหมด (เปิด port<1024, แก้เวลาระบบ ฯลฯ) — ใส่เท่าที่ต้องถ้าจำเป็น
CapabilityBoundingSet=

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload && sudo systemctl enable --now worker
```
> 💡 **อธิบาย — directive hardening:** `ProtectSystem=strict` + `ReadWritePaths` = process เขียนได้แค่โฟลเดอร์ที่อนุญาต ต่อให้โดนเจาะก็แก้ไฟล์ระบบไม่ได้ · `PrivateTmp` = กันไฟล์ชั่วคราวรั่วถึงกัน · `CapabilityBoundingSet=` ว่าง = ตัดสิทธิ์พิเศษ (เช่น เปิด port < 1024, แก้เวลาระบบ) ทั้งหมด

**งานตามเวลา (แทน cron)** — `.service` (Type=oneshot) + `.timer`
```ini
# /etc/systemd/system/cleanup.service — งานที่ timer เรียก
[Service]
# รันครั้งเดียวแล้วจบ
Type=oneshot
# รันด้วย service user เดียวกัน
User=worker
ExecStart=/opt/worker/cleanup.sh
```
```ini
# /etc/systemd/system/cleanup.timer — ตารางเวลา
[Timer]
# ทุกวันเวลา 02:00
OnCalendar=*-*-* 02:00:00
# ถ้าเครื่องปิดช่วงนั้น ให้รันย้อนตอนเปิด
Persistent=true

[Install]
WantedBy=timers.target
```
```bash
sudo systemctl enable --now cleanup.timer
systemctl list-timers          # ดูตารางงานทั้งหมด + รอบถัดไป
```

**Restart / ดู log** — ให้สิทธิ์ผ่าน group `app-deploy` เฉพาะคำสั่ง (เพิ่มในบรรทัด sudoers เดิม)
```
%app-deploy ALL=(root) NOPASSWD: /bin/systemctl restart worker, /bin/systemctl status worker
```
```bash
sudo systemctl restart worker
```

**Logs ของ service — ไปอยู่ใน journald อัตโนมัติ**

service ที่รันผ่าน systemd **ไม่ต้องตั้ง log เอง** — ทุกอย่างที่ ExecStart พิมพ์ออก stdout/stderr ถูก journald เก็บให้ · retention = `journald.conf` (รายวัน 90 วัน ที่ตั้งในภาคผนวก B) ครอบให้แล้ว
```bash
journalctl -u worker -f                              # ดู log สด
journalctl -u worker --since today                   # เฉพาะวันนี้
journalctl -u worker --since "2026-10-17" --until "2026-10-18"   # ย้อนรายวัน
journalctl -u worker -p err                          # เฉพาะ level error
```
> 💡 **ทำไมไม่เห็นไฟล์ log:** service พวกนี้ไม่ได้เขียนไฟล์ใน `/var/log/` แบบ Nginx/Tomcat — มัน log เข้า **journald** (binary) ซึ่งดูด้วย `journalctl -u <ชื่อ>` · ครบทั้ง retention + ค้นตามวัน/level ได้เลย
> 💡 **ถ้า service เขียน log เป็นไฟล์เอง** (เช่น `/opt/worker/logs/app.log`) → เพิ่ม logrotate เหมือน 5.8 ให้หมุนรายวัน เก็บ 90:
> ```
> /opt/worker/logs/*.log {
>     daily
>     rotate 90
>     compress
>     missingok
>     notifempty
>     copytruncate
>     su worker worker
> }
> ```

> 💡 ถ้า service ต้องต่อ MySQL → สร้าง DB user แยกอีกตัว ให้สิทธิ์เฉพาะ db/ตารางที่ใช้ (เหมือนหัวข้อ 4) ไม่ใช้ user เดียวกับแอปหลัก

---
