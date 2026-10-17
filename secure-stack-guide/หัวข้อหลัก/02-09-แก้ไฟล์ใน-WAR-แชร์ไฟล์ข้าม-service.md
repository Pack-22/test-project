## 9. แก้ไฟล์ใน WAR & แชร์ไฟล์ข้าม service

### 9.1 แก้ไฟล์ใน WAR ที่กางแล้ว

WAR ที่กางอยู่ `/opt/tomcat/webapps/app/` เป็นของ `tomcat:tomcat`

- **แนะนำ: อย่าแก้ในไดเรกทอรีที่กางโดยตรง** — Tomcat อาจ re-explode ทับ หรือ redeploy แล้วการแก้หาย → แก้ที่ **source → build war ใหม่ → วางทับ** (war คือ source of truth)
- ถ้าจำเป็นต้องแก้ด่วน (เช่น แก้ config.properties) ให้ทำ **ในนาม user `tomcat`** เพื่อให้เจ้าของไฟล์ไม่เพี้ยน:
```bash
sudo -u tomcat vi /opt/tomcat/webapps/app/WEB-INF/classes/config.properties
# ถ้าเผลอแก้ด้วย deploy user แล้ว ให้คืนเจ้าของ:
sudo chown tomcat:tomcat <ไฟล์>
```
> ⚠️ ห้าม `chmod 777` เพื่อให้แก้ง่าย — มันเปิดให้ทุก user แก้ไฟล์แอปได้ · ใช้ `sudo -u tomcat` คือทางที่สะอาดและปลอดภัยสุด

### 9.2 แชร์ไฟล์ข้าม service (เช่น Tomcat ↔ Hive/Hadoop บน local FS)

แต่ละ service รันคนละ user — ให้เข้าถึงกันได้โดย**ไม่เปิด 777** ด้วย **shared group + setgid + (ถ้าซับซ้อน) ACL**
```bash
# 1) group กลางสำหรับแชร์ข้อมูล
sudo groupadd datax

# 2) เพิ่ม service user ทั้งสองฝั่งเข้า group
sudo usermod -aG datax tomcat
sudo usermod -aG datax hive

# 3) โฟลเดอร์แชร์: group + setgid (ไฟล์ใหม่ได้ group datax อัตโนมัติ)
sudo chown tomcat:datax /data/exchange
sudo chmod 2770 /data/exchange        # 2750 ถ้าฝั่งปลายทางอ่านอย่างเดียว
```
ให้ service ฝั่งที่เขียนไฟล์ ตั้ง umask ใน systemd unit ให้ group อ่านได้:
```ini
[Service]
# ไฟล์ใหม่ = 640, โฟลเดอร์ = 750
UMask=0027
```
ถ้าต้องการสิทธิ์ละเอียด / เปลี่ยนเจ้าของไม่ได้ → ใช้ **POSIX ACL**:
```bash
sudo setfacl -R  -m g:datax:rX /data/exchange     # ให้สิทธิ์ตอนนี้
sudo setfacl -R -d -m g:datax:rX /data/exchange   # default: ไฟล์ใหม่สืบทอด
getfacl /data/exchange                            # ตรวจ
```
> 💡 **อธิบาย — `rX` (X ตัวใหญ่):** ให้สิทธิ์ execute **เฉพาะโฟลเดอร์** (ต้อง execute ถึงจะเข้าโฟลเดอร์ได้) แต่**ไม่ติด execute ให้ไฟล์ข้อมูลธรรมดา** — ปลอดภัยกว่า `rx` ตัวเล็กที่จะทำให้ไฟล์ทุกอันกลายเป็น executable

หลัก: **ฝั่งสร้างไฟล์เป็นเจ้าของ, ฝั่งที่ใช้แค่อ่านให้ `r`/`rX` พอ** อย่าให้เขียนถ้าไม่จำเป็น

> ⚠️ **ถ้าไฟล์อยู่บน HDFS (ไม่ใช่ดิสก์ local):** สิทธิ์ POSIX ข้างบนใช้ไม่ได้ ต้องใช้สิทธิ์ของ HDFS เอง (`hdfs dfs -chmod`, `hdfs dfs -setfacl`) + Kerberos/Ranger ถ้าเปิด security — แพทเทิร์น shared-group ใช้ได้เฉพาะเมื่อทั้งสอง service แชร์โฟลเดอร์บนเครื่อง/mount เดียวกัน (ถ้าต้องการหัวข้อ HDFS เต็ม บอกได้ว่าเป็น single node หรือ cluster และใช้ Kerberos ไหม)

---
