## 6. ติดตั้ง & ตั้งค่า Nginx + TLS [Critical]

> 💡 **อธิบาย — โครงสร้าง Nginx:** คอนฟิกมี 3 ชั้นซ้อนกัน — **`http {}`** (ค่ากลางทั้ง server), **`server {}`** (1 เว็บไซต์/โดเมน), **`location {}`** (เส้นทาง URL ในไซต์) · directive แต่ละตัว**ต้องวางให้ถูกชั้น** ไม่งั้น `nginx -t` ไม่ผ่าน

### 6.1 ติดตั้ง + ตั้ง server_name ก่อน

```bash
sudo apt install -y nginx
sudo systemctl enable --now nginx
```
แก้ไซต์ default `/etc/nginx/sites-available/default` ใส่ `server_name` ให้ตรง domain (certbot ต้องใช้หาตำแหน่ง):
```nginx
server {
    listen 80;
    server_name yourdomain.com;        # ← แก้เป็น domain จริง
    location / {
        proxy_pass http://127.0.0.1:8080;        # ส่งต่อไป Tomcat
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```
```bash
sudo nginx -t && sudo systemctl reload nginx
```
> ⚠️ **ก่อนขอ cert ต้องครบ:** (1) DNS A record ของ `yourdomain.com` ชี้มาที่ IP เครื่องแล้ว (2) UFW เปิด 80/443 แล้ว (หัวข้อ 3.4) (3) `server_name` ตรง — ไม่งั้น certbot ขอ cert ไม่ผ่าน

### 6.2 ขอใบรับรอง TLS (Let's Encrypt)

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d yourdomain.com     # certbot แก้ server block เติม listen 443 + cert + redirect ให้อัตโนมัติ
```
> 💡 certbot จะเติม `listen 443 ssl`, path ของ cert, และ redirect 80→443 ลงใน server block ให้เอง พร้อมตั้ง cron ต่ออายุอัตโนมัติ (cert อายุ 90 วัน)

### 6.3 เพิ่มค่าความปลอดภัย

ใส่ **ใน `http {}`** ของ `/etc/nginx/nginx.conf` (มีผลทุกไซต์):
```nginx
server_tokens off;                     # ซ่อนเวอร์ชัน Nginx ใน header/หน้า error
client_max_body_size 10m;              # จำกัดขนาด request (กัน upload ถล่ม)
client_body_timeout 10s;
client_header_timeout 10s;

# security headers (มีผลหลังเปิด HTTPS จาก 6.2)
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;  # บังคับ HTTPS
add_header X-Content-Type-Options "nosniff" always;                                  # กัน MIME sniffing
add_header X-Frame-Options "SAMEORIGIN" always;                                      # กัน clickjacking
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```
ส่วน `ssl_protocols` / `ssl_ciphers` certbot ตั้งให้แล้วใน `options-ssl-nginx.conf` — ไม่ต้องตั้งซ้ำ
```bash
sudo nginx -t && sudo systemctl reload nginx
```
> 💡 **อธิบาย — ทำไมมี Nginx หน้า Tomcat:** Nginx รับ HTTPS จากภายนอกแล้ว proxy เป็น HTTP ไป Tomcat ที่ localhost — Tomcat ไม่ต้องโดนเน็ตตรงๆ, จัดการ cert/TLS ที่เดียว, และกรอง request ชั้นหน้าได้ (rate limit, body size)

### 6.4 Log & retention (Nginx) [High]

Nginx เป็น **แหล่งหลักที่บันทึกว่าใครเข้าเว็บ** เพราะอยู่หน้าสุดและเห็น **IP จริงของผู้ใช้** · มี 2 ไฟล์:

| ไฟล์ | บันทึกอะไร |
|---|---|
| `/var/log/nginx/access.log` | ทุก request: IP จริง, เวลา, `"METHOD /path"`, status, bytes, referer, user-agent |
| `/var/log/nginx/error.log` | error ของ Nginx เอง (config ผิด, upstream ล่ม, TLS ปัญหา) |

**format log (เก็บครบ ให้สอดคล้องกับ Tomcat 5.9):** default `combined` เก็บเกือบครบอยู่แล้ว แต่ไม่มี response time — นิยาม format เองใน `http {}` ของ `/etc/nginx/nginx.conf`:
```nginx
log_format rich '$remote_addr - $remote_user [$time_local] '
                '"$request" $status $body_bytes_sent $request_time '
                '"$http_referer" "$http_user_agent"';
access_log /var/log/nginx/access.log rich;
```
```
203.0.113.5 - - [17/Oct/2026:19:40:12 +0700] "POST /app/orders/create HTTP/1.1" 200 512 0.048 "https://site/app/orders" "Mozilla/5.0 ..."
```
**แต่ละ field:** `$remote_addr` IP จริง · `$remote_user` user จาก HTTP auth (session login = `-`) · `"$request"` **method + หน้า/endpoint** · `$status` · `$body_bytes_sent` · `$request_time` **เวลาตอบ (วินาที)** · `"$http_referer"` **มาจากหน้าไหน** · `"$http_user_agent"` browser · `sudo nginx -t && sudo systemctl reload nginx` ให้มีผล

**retention:** Ubuntu ติดตั้ง logrotate ให้ Nginx อยู่แล้วที่ `/etc/logrotate.d/nginx` (default `rotate 14` = เก็บ 14 วัน) — ปรับให้ตรง policy:
```bash
sudo sed -i 's/rotate 14/rotate 90/' /etc/logrotate.d/nginx   # เก็บ 90 วันให้ตรงกับ log อื่น
sudo logrotate -d /etc/logrotate.d/nginx                      # dry-run ตรวจ
```
```bash
# ดูสดว่าใครกำลังเข้ามา:
sudo tail -f /var/log/nginx/access.log
# สรุป top IP ที่เข้ามามากสุด:
sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head
```
> 💡 **สรุปเลเยอร์ของ log "ใครเข้ามา":**
> - **SSH/เข้าเครื่อง** (sysadmin) → `last`, `/var/log/auth.log`, auditd (หัวข้อ 3.6)
> - **เข้าเว็บจากภายนอก** (ผู้ใช้ทั่วไป) → **Nginx access.log** (IP จริง + URL) — แหล่งหลัก
> - **ระดับแอป** (session, response time) → Tomcat access log (หัวข้อ 5.9)
> - **username ที่ login ในแอป** → ต้องให้แอปเขียน log เอง
> ⚠️ ตั้ง retention ของ access.log ให้ **ยาวพอกับ audit** (เช่น 90 วัน+) เพราะเวลาสืบสวนเหตุ มักต้องย้อนดู request log ประกอบ

---
