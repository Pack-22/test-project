## 7. Deploy แอป (WAR บน Tomcat)

แอปเป็น **WAR รันในตัว Tomcat** → **Tomcat (user `tomcat`) คือ service user ที่รันแอป** ไม่ต้องมี systemd service แยกและไม่ต้อง login เป็น `tomcat`
ปิด manager/tomcat-users แล้ว จึง deploy แบบ **file-drop (autoDeploy)**: วางไฟล์ war ลง webapps แล้ว Tomcat กางเอง

### 7.1 ให้สิทธิ์ group `app-deploy` วาง war ได้ (ทำครั้งเดียว ด้วย ACL)

```bash
sudo chown tomcat:tomcat /opt/tomcat/webapps
sudo chmod 750 /opt/tomcat/webapps
# ACL: ให้ service tomcat อ่าน war ได้เสมอ + group app-deploy เขียน/ทับ war ได้
sudo setfacl -R  -m g:tomcat:rX -m g:app-deploy:rwX /opt/tomcat/webapps
sudo setfacl -R -d -m g:tomcat:rX -m g:app-deploy:rwX /opt/tomcat/webapps   # war ใหม่สืบทอดสิทธิ์
```
> 💡 **อธิบาย — ทำไมใช้ ACL ไม่ใช่ group tomcat:** process Tomcat (user `tomcat`) ต้องอ่าน war ได้, คน deploy ต้องเขียนได้ · default ACL ทำให้ war ที่ `app-deploy` วางใหม่ **ให้ `tomcat` อ่านได้อัตโนมัติ และ `app-deploy` เขียนทับได้** — คน deploy อยู่แค่ group `app-deploy` พอ **ไม่ต้องเป็นสมาชิก group `tomcat`** (แยก role ออกจาก service account สะอาดกว่า)

### 7.2 Deploy WAR

ทำในนาม deploy user (ไม่ใช้ root):
```bash
# ชื่อไฟล์ = context path:  app.war → https://domain/app   |   ROOT.war → https://domain/
cp app.war /opt/tomcat/webapps/
```
Tomcat autoDeploy จะกาง war เองในไม่กี่วินาที **ไม่ต้อง restart** — ดู log ยืนยัน:
```bash
tail -f /opt/tomcat/logs/catalina.out      # เห็น "Deployment of web application archive ... has finished"
```
> 💡 **autoDeploy** คือค่า default ของ Tomcat 9 ที่เฝ้าดูโฟลเดอร์ webapps เจอ war ใหม่/เปลี่ยนก็กางให้เอง · **อัปเดตเวอร์ชัน:** วางทับไฟล์ war ชื่อเดิม Tomcat จะ undeploy ตัวเก่าแล้ว deploy ตัวใหม่ให้

### 7.3 Restart Tomcat (เฉพาะเมื่อจำเป็น)

เช่น แก้ server.xml / JVM opts ต้อง restart:
```bash
sudo systemctl restart tomcat      # ใช้ user ใน group app-deploy ผ่าน sudo เฉพาะคำสั่ง
```
sudoers (`/etc/sudoers.d/app-deploy`) ตั้งไว้แล้วในหัวข้อ 3:
```
%app-deploy ALL=(root) NOPASSWD: /bin/systemctl restart tomcat, /bin/systemctl status tomcat
```
> 💡 **สรุปใครทำอะไร:** `tomcat` = เจ้าของ process (nologin) · group `app-deploy` = วาง war (ACL) + restart (sudo) · group `app-logview` = อ่าน log · group `sudo` = admin เต็ม
> 💡 **Backup:** ถ้าส่ง backup ออกนอกเครื่อง (S3 / เครื่องสำรอง) **เข้ารหัสไฟล์ backup แยก** (เช่น `gpg`) เพราะ LUKS ครอบแค่ดิสก์ในเครื่อง ไม่ครอบไฟล์ที่ออกไปข้างนอก

---
