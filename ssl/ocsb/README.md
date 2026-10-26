# คู่มือติดตั้ง SSL Certificate `*.ocsb.go.th` บน nginx

ปรับปรุงล่าสุด: 26 ต.ค. 2026
Certificate อายุใช้งาน: 25 ก.ย. 2026 – 11 เม.ย. 2027

---

## 1. ภาพรวม

### ไฟล์ที่ได้จาก DigiCert

| ไฟล์ | คืออะไร | ใช้หรือไม่ |
|---|---|---|
| `star_ocsb_go_th.crt` | Certificate ของโดเมน `*.ocsb.go.th` | ใช้ |
| `DigiCertCA.crt` | Intermediate CA (GeoTrust TLS RSA CA G1) | ใช้ |
| `TrustedRoot.crt` | Root CA (DigiCert Global Root G2) | ไม่ต้องใช้ |
| `INSTALL_INSTRUCTIONS.*.txt` | คู่มือภาษาต่างๆ | ไม่ต้องใช้ |

### ไฟล์ที่ต้องได้จากคนสร้าง CSR (ไม่ได้มาจาก DigiCert)

| ไฟล์ | คืออะไร |
|---|---|
| `_.ocsb.go.th.key` | Private key ที่สร้างคู่กับ CSR (สร้างเมื่อ 31 ส.ค. 2026) |
| `_.ocsb.go.th.csr` | CSR ที่ส่งให้ DigiCert (ไม่ต้องใช้ตอนติดตั้ง) |

> **สำคัญ:** Private key สร้างย้อนกลับจาก certificate ไม่ได้ ถ้าไม่มี key ที่คู่กัน ต้อง reissue cert ใหม่เท่านั้น

### ปลายทางบนเซิร์ฟเวอร์ (ทุกเครื่องใช้ path เดียวกัน)

```nginx
ssl_certificate     /etc/ssl/ocsb_certs/fullchain.crt;
ssl_certificate_key /etc/ssl/ocsb_private/private.key;
```

### เครื่องและโดเมนที่ใช้ cert นี้

| เครื่อง | ไฟล์ config nginx | โดเมน |
|---|---|---|
| datamindaimgmt | `/etc/nginx/sites-available/portal.ocsb.go.th` | portal.ocsb.go.th |
| datamindaimgmt | `/etc/nginx/sites-available/aidatadriven-cubika.ocsb.go.th` | aidatadriven-cubika.ocsb.go.th |
| datamindaimgmt | `/etc/nginx/sites-available/aidatadriven-dashboard.ocsb.go.th` | aidatadriven-dashboard.ocsb.go.th |
| datamindaigenwiz | `/etc/nginx/sites-available/aidatadriven-genwiz.ocsb.go.th` | aidatadriven-genwiz.ocsb.go.th |
| datamindaidashboard | `/etc/nginx/sites-available/chatbot.ocsb.go.th` | chatbot.ocsb.go.th |

> เครื่อง datamindaidashboard มี `chatbot.tisi.go.th` และ `portal.tisi.go.th` ด้วย ซึ่งใช้ cert คนละชุด ไม่เกี่ยวข้อง

---

## 2. ขั้นตอนที่ 0 — ตรวจ config ของเครื่อง

ทำบนทุกเครื่องก่อนเริ่ม เพื่อยืนยันว่า nginx ชี้ไปที่ path ไหน

```bash
sudo grep -rn "ssl_certificate" /etc/nginx/sites-available/
```

ผลที่ควรได้ (ตัวอย่าง):

```
/etc/nginx/sites-available/portal.ocsb.go.th:11:    ssl_certificate /etc/ssl/ocsb_certs/fullchain.crt;
/etc/nginx/sites-available/portal.ocsb.go.th:12:    ssl_certificate_key /etc/ssl/ocsb_private/private.key;
```

ถ้า path ต่างจากนี้ ให้เปลี่ยนคำสั่งในขั้นตอนถัดไปให้ตรง

---

## 3. ขั้นตอนที่ 1 — เตรียมไฟล์และสร้าง fullchain

อัปโหลดไฟล์ทั้งหมดไปไว้ที่ `~/sw_install/ssl-ocsb/` บนเครื่องปลายทาง (ผ่าน WinSCP หรือ scp)

```bash
cd ~/sw_install/ssl-ocsb
ls -l
```

ต้องเห็นอย่างน้อย `star_ocsb_go_th.crt`, `DigiCertCA.crt`, `_.ocsb.go.th.key`

### 1.1 ลบ CRLF ของ Windows

ไฟล์ที่ก๊อปมาจาก Windows มักมีตัวขึ้นบรรทัดแบบ CRLF ซึ่งอาจทำให้ nginx/openssl อ่านผิด

```bash
sed -i 's/\r$//' star_ocsb_go_th.crt DigiCertCA.crt _.ocsb.go.th.key
```

### 1.2 รวมเป็น fullchain.crt

ลำดับต้องเป็น **cert ของโดเมนก่อน** แล้วตามด้วย **intermediate** (ไม่ต้องใส่ TrustedRoot)

```bash
awk 1 star_ocsb_go_th.crt DigiCertCA.crt > fullchain.crt
```

> ใช้ `awk 1` แทน `cat` เพื่อให้มีขึ้นบรรทัดใหม่คั่นระหว่างไฟล์เสมอ

### 1.3 ตรวจ fullchain

```bash
grep -c "BEGIN CERTIFICATE" fullchain.crt
```

ต้องได้ `2`

```bash
openssl crl2pkcs7 -nocrl -certfile fullchain.crt | openssl pkcs7 -print_certs -noout
```

ผลที่ถูกต้อง:

```
subject=C = TH, ST = Bangkok, L = Ratchathewi, O = Office of the Cane and Sugar Board, CN = *.ocsb.go.th
issuer=C = US, O = DigiCert Inc, OU = www.digicert.com, CN = GeoTrust TLS RSA CA G1

subject=C = US, O = DigiCert Inc, OU = www.digicert.com, CN = GeoTrust TLS RSA CA G1
issuer=C = US, O = DigiCert Inc, OU = www.digicert.com, CN = DigiCert Global Root G2
```

---

## 4. ขั้นตอนที่ 2 — ตรวจว่า cert กับ key เป็นคู่กัน

**ห้ามข้ามขั้นนี้** ถ้าไม่คู่กันแล้วติดตั้งไป nginx จะขึ้นไม่ได้ และทุกเว็บบนเครื่องจะล่ม

```bash
openssl x509 -noout -pubkey -in fullchain.crt | md5sum
openssl pkey -pubout -in _.ocsb.go.th.key | md5sum
```

ทั้งสองบรรทัดต้องได้ค่าเดียวกัน สำหรับ cert รอบนี้คือ:

```
e8ac61803b5b91a65fa68c6b49228dfd  -
e8ac61803b5b91a65fa68c6b49228dfd  -
```

- ถ้าตรงกัน → ไปขั้นตอนที่ 3
- ถ้าไม่ตรง → หยุด ดูหัวข้อ **ปัญหาที่พบและวิธีแก้**
- ถ้าคำสั่ง `pkey` ถามรหัสผ่าน → key ถูกเข้ารหัส ให้ถอดรหัสก่อน:

```bash
openssl pkey -in _.ocsb.go.th.key -out _.ocsb.go.th.nopass.key
```

---

## 5. ขั้นตอนที่ 3 — สำรองของเดิมและติดตั้ง

### 3.1 สร้างโฟลเดอร์ (กรณีเครื่องใหม่ที่ยังไม่มี)

```bash
sudo mkdir -p /etc/ssl/ocsb_certs /etc/ssl/ocsb_private
sudo chmod 700 /etc/ssl/ocsb_private
```

### 3.2 สำรองไฟล์เดิม

```bash
sudo cp /etc/ssl/ocsb_private/private.key /etc/ssl/ocsb_private/private.key.bk-20261026
sudo cp /etc/ssl/ocsb_certs/fullchain.crt /etc/ssl/ocsb_certs/fullchain.crt.bk-20261026
```

### 3.3 วางไฟล์ใหม่

```bash
sudo cp _.ocsb.go.th.key /etc/ssl/ocsb_private/private.key
sudo chmod 600 /etc/ssl/ocsb_private/private.key
sudo cp fullchain.crt /etc/ssl/ocsb_certs/fullchain.crt
```

### 3.4 ทดสอบ config และ reload nginx

```bash
sudo nginx -t && sudo systemctl reload nginx
```

ผลที่ถูกต้อง:

```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

> ใช้ `reload` ไม่ใช่ `restart` — ถ้า config ผิด nginx ตัวเดิมจะยังทำงานต่อ เว็บไม่ล่ม

### 3.5 ปิดสิทธิ์ไฟล์ key ที่ home

```bash
chmod 600 ~/sw_install/ssl-ocsb/_.ocsb.go.th.key
```

---

## 6. ขั้นตอนที่ 4 — ตรวจสอบผล

แทน `DOMAIN` ด้วยโดเมนของเครื่องนั้น เช่น `portal.ocsb.go.th`

### 4.1 วันหมดอายุ

```bash
DOMAIN=portal.ocsb.go.th
echo | openssl s_client -connect $DOMAIN:443 -servername $DOMAIN 2>/dev/null | openssl x509 -noout -dates
```

ต้องได้:

```
notBefore=Sep 25 00:00:00 2026 GMT
notAfter=Apr 11 23:59:59 2027 GMT
```

### 4.2 Chain ครบถ้วน

```bash
echo | openssl s_client -connect $DOMAIN:443 -servername $DOMAIN 2>/dev/null | grep "Verify return code"
```

ต้องได้ `Verify return code: 0 (ok)`

### 4.3 ตรวจหลายโดเมนพร้อมกัน

```bash
for d in portal.ocsb.go.th aidatadriven-cubika.ocsb.go.th aidatadriven-dashboard.ocsb.go.th \
         aidatadriven-genwiz.ocsb.go.th chatbot.ocsb.go.th; do
  echo "== $d"
  echo | openssl s_client -connect $d:443 -servername $d 2>/dev/null | openssl x509 -noout -enddate
done
```

### 4.4 ตรวจในเบราว์เซอร์

เปิดเว็บแบบ Incognito → คลิกรูปแม่กุญแจ → ดูรายละเอียด certificate ว่าหมดอายุ 11 เม.ย. 2027

---

## 7. การย้อนกลับ (Rollback)

ถ้าติดตั้งแล้วมีปัญหา คืนค่าไฟล์เดิมได้ทันที

```bash
sudo cp /etc/ssl/ocsb_private/private.key.bk-20261026 /etc/ssl/ocsb_private/private.key
sudo cp /etc/ssl/ocsb_certs/fullchain.crt.bk-20261026 /etc/ssl/ocsb_certs/fullchain.crt
sudo nginx -t && sudo systemctl reload nginx
```

---

## 8. ปัญหาที่พบและวิธีแก้

### 8.1 md5 ของ cert กับ key ไม่ตรงกัน

สาเหตุ: cert ถูกออกจาก CSR ที่สร้างด้วย key ตัวอื่น (รอบนี้เกิดจาก CSR ถูกสร้างนอกเซิร์ฟเวอร์ และไม่ได้ส่ง key มาพร้อม cert)

**ห้าม reload/restart nginx** แล้วเลือกทางใดทางหนึ่ง:

**ทาง A — หา key ตัวจริง**

ค้นหาไฟล์ที่มี private key บนเครื่อง:

```bash
sudo grep -rl "PRIVATE KEY" /etc /home /root /opt 2>/dev/null
```

หรือขอจากคนที่สร้าง CSR (ให้ส่งเป็น zip ใส่รหัสผ่าน และแจ้งรหัสแยกช่องทาง)

ไฟล์ key จริงเปิดด้วย Notepad จะขึ้นต้นด้วย `-----BEGIN PRIVATE KEY-----` หรือ `-----BEGIN RSA PRIVATE KEY-----` (ไฟล์ `.crt` จาก DigiCert ไม่ใช่ key)

**ทาง B — Reissue ด้วย CSR จาก key ที่มีบนเครื่อง**

```bash
cd ~/sw_install/ssl-ocsb
sudo openssl req -new -key /etc/ssl/ocsb_private/private.key -out ocsb.csr \
  -subj "/C=TH/ST=Bangkok/L=Ratchathewi/O=Office of the Cane and Sugar Board/CN=*.ocsb.go.th"
```

ตรวจ CSR:

```bash
openssl req -noout -subject -in ocsb.csr
openssl req -noout -pubkey -in ocsb.csr | md5sum
sudo openssl pkey -pubout -in /etc/ssl/ocsb_private/private.key | md5sum
```

md5 สองบรรทัดหลังต้องตรงกัน จากนั้น:

```bash
cat ocsb.csr
```

คัดลอกทั้งหมด (รวมบรรทัด BEGIN/END) ไปวางใน DigiCert CertCentral → Certificates → Orders → เลือก order → **Reissue Now**

### 8.2 เขียนทับ fullchain.crt ไปแล้ว แต่ key ไม่ตรง

nginx ที่รันอยู่ยังใช้ cert เก่าในหน่วยความจำ เว็บยังใช้ได้ แต่ถ้า restart จะขึ้นไม่ได้ ให้ดึง cert เก่าจากเว็บที่รันอยู่กลับมา:

```bash
cd ~/sw_install/ssl-ocsb
echo | openssl s_client -connect portal.ocsb.go.th:443 -servername portal.ocsb.go.th -showcerts 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > old_fullchain.crt
```

ตรวจว่าคู่กับ key เดิม:

```bash
openssl x509 -noout -pubkey -in old_fullchain.crt | md5sum
sudo openssl pkey -pubout -in /etc/ssl/ocsb_private/private.key | md5sum
```

ถ้าตรง วางกลับ:

```bash
sudo cp /etc/ssl/ocsb_certs/fullchain.crt ~/sw_install/ssl-ocsb/new_fullchain_nokey.crt
sudo cp old_fullchain.crt /etc/ssl/ocsb_certs/fullchain.crt
sudo nginx -t
```

### 8.3 ไฟล์ .crt เป็น DER ไม่ใช่ PEM

ถ้าเปิดไฟล์แล้วไม่ขึ้นต้นด้วย `-----BEGIN CERTIFICATE-----`:

```bash
openssl x509 -inform der -in star_ocsb_go_th.crt -out star_ocsb_go_th.pem.crt
```

### 8.4 หาไฟล์ที่สร้างด้วย tee ไม่เจอ

คำสั่ง `... | sudo tee /etc/ssl/ocsb_certs/fullchain.crt` เขียนไฟล์ไปที่ปลายทางโดยตรง ไม่ได้อยู่ในโฟลเดอร์ปัจจุบัน ตรวจด้วย:

```bash
ls -l /etc/ssl/ocsb_certs/
```

---

## 9. ทำความสะอาดและต่ออายุครั้งหน้า

### ลบไฟล์ชั่วคราว (หลังใช้งานปกติแล้ว)

```bash
cd ~/sw_install/ssl-ocsb
rm -f ocsb.csr new_fullchain_nokey.crt old_fullchain.crt
```

ไฟล์สำรอง `*.bk-20261026` ใน `/etc/ssl` เก็บไว้ประมาณ 1 สัปดาห์ แล้วค่อยลบ:

```bash
sudo rm /etc/ssl/ocsb_private/private.key.bk-20261026 /etc/ssl/ocsb_certs/fullchain.crt.bk-20261026
```

### ต่ออายุครั้งหน้า

- Cert หมดอายุ **11 เม.ย. 2027** ควรเริ่มต่ออายุ **ต้นมีนาคม 2027**
- Cert รุ่นใหม่มีอายุสั้นลง (ประมาณ 200 วัน) ต้องต่ออายุบ่อยขึ้น
- แนะนำให้สร้าง CSR บนเซิร์ฟเวอร์เอง แล้วส่งให้ผู้ดูแลบัญชี DigiCert เพื่อให้ key อยู่กับเราตั้งแต่ต้น:

```bash
cd ~/sw_install/ssl-ocsb
openssl req -new -newkey rsa:2048 -nodes \
  -keyout _.ocsb.go.th.key -out _.ocsb.go.th.csr \
  -subj "/C=TH/ST=Bangkok/L=Ratchathewi/O=Office of the Cane and Sugar Board/CN=*.ocsb.go.th"
chmod 600 _.ocsb.go.th.key
```

เก็บไฟล์ `.key` ไว้ให้ดี แล้วส่งเฉพาะไฟล์ `.csr` ให้ DigiCert เมื่อได้ cert กลับมา ทำตามขั้นตอนที่ 1–4 ของคู่มือนี้ได้เลย

---

## 10. สรุปคำสั่งแบบย่อ (Quick Reference)

```bash
cd ~/sw_install/ssl-ocsb

# 1. เตรียมไฟล์
sed -i 's/\r$//' star_ocsb_go_th.crt DigiCertCA.crt _.ocsb.go.th.key
awk 1 star_ocsb_go_th.crt DigiCertCA.crt > fullchain.crt

# 2. ตรวจคู่ cert/key (ต้องตรงกัน)
openssl x509 -noout -pubkey -in fullchain.crt | md5sum
openssl pkey -pubout -in _.ocsb.go.th.key | md5sum

# 3. สำรองและติดตั้ง
sudo cp /etc/ssl/ocsb_private/private.key /etc/ssl/ocsb_private/private.key.bk-$(date +%Y%m%d)
sudo cp /etc/ssl/ocsb_certs/fullchain.crt /etc/ssl/ocsb_certs/fullchain.crt.bk-$(date +%Y%m%d)
sudo cp _.ocsb.go.th.key /etc/ssl/ocsb_private/private.key
sudo chmod 600 /etc/ssl/ocsb_private/private.key
sudo cp fullchain.crt /etc/ssl/ocsb_certs/fullchain.crt
sudo nginx -t && sudo systemctl reload nginx

# 4. ตรวจผล
DOMAIN=portal.ocsb.go.th
echo | openssl s_client -connect $DOMAIN:443 -servername $DOMAIN 2>/dev/null | openssl x509 -noout -dates
echo | openssl s_client -connect $DOMAIN:443 -servername $DOMAIN 2>/dev/null | grep "Verify return code"
chmod 600 _.ocsb.go.th.key
```
