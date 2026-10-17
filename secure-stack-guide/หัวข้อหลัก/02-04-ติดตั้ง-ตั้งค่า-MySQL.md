## 4. ติดตั้ง & ตั้งค่า MySQL [Critical]

```bash
sudo apt install -y mysql-server
sudo systemctl enable --now mysql
sudo mysql_secure_installation      # ลบ anonymous user, test db, ปิด remote root
```
> 💡 **อธิบาย — `mysql_secure_installation` ทำอะไร:** เป็น wizard ที่ลบของ default ที่เสี่ยง (บัญชี anonymous, database `test`, การ login root จากระยะไกล) · ตอบ Yes ให้หมดได้ ยกเว้น "Validate Password Component" ที่จะบังคับความซับซ้อนรหัส (เลือกตามนโยบายทีม)

bind localhost — `/etc/mysql/mysql.conf.d/mysqld.cnf`:
```ini
[mysqld]
bind-address = 127.0.0.1       # รับ connection เฉพาะในเครื่อง — ภายนอกต่อไม่ได้
local_infile = 0               # ปิด LOAD DATA LOCAL (กันอ่านไฟล์ฝั่ง client ผ่าน SQL)
skip_symbolic_links = 1        # กันใช้ symlink ชี้ข้าม directory
```
```bash
sudo systemctl restart mysql
```

สร้าง database + user จำกัดสิทธิ์:
```bash
sudo mysql        # เข้า MySQL shell ในนาม root (ผ่าน socket, ไม่ต้องใช้รหัส)
```
```sql
CREATE DATABASE appdb CHARACTER SET utf8mb4;
CREATE USER 'app'@'127.0.0.1' IDENTIFIED BY '<รหัสยาวสุ่ม>';
GRANT SELECT,INSERT,UPDATE,DELETE ON appdb.* TO 'app'@'127.0.0.1';   -- ให้เฉพาะที่แอปใช้
-- ห้าม GRANT ALL / *.* / 'app'@'%'  (จะกลายเป็น user เทพที่ต่อจากไหนก็ได้)
FLUSH PRIVILEGES;
```
> 💡 **อธิบาย — least privilege ของ DB:** แอปควรใช้ user ที่ทำได้แค่ CRUD บน `appdb` เท่านั้น · ถ้าแอปโดน SQL injection ผู้โจมตีก็ทำได้แค่ในขอบเขตนี้ ไม่สามารถ DROP ตาราง, อ่าน db อื่น, หรือสร้าง user ใหม่
> ⚠️ **gotcha ที่เจอบ่อย — caching_sha2_password:** MySQL 8 ใช้ auth แบบ `caching_sha2_password` เป็น default ซึ่ง **JDBC connector เก่า (Connector/J < 8.0) ต่อไม่ติด** ขึ้น error auth — แก้โดย**ใช้ Connector/J 8.0+ ในแอป** (วิธีที่ถูก) หรือถ้าจำเป็นจริงค่อยเปลี่ยน auth ของ user: `ALTER USER 'app'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '<รหัส>';`
> 💡 ไม่ทำ encryption ที่ MySQL — ข้อมูลบนดิสก์ถูก LUKS ครอบไว้แล้ว · รหัส MySQL ถูก hash อัตโนมัติ

---
