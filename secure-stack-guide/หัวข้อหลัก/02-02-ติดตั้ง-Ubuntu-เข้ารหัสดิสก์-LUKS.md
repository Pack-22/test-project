## 2. ติดตั้ง Ubuntu + เข้ารหัสดิสก์ (LUKS) [Critical]

> ⚠️ ต้องทำตอนติดตั้งเท่านั้น — ลงไปแล้วมาเข้ารหัสทีหลังต้องล้างลงใหม่

1. บูตจาก ISO → เลือกภาษา / คีย์บอร์ด / เน็ตเวิร์ก
2. หน้า **"Guided storage configuration"** → เลือก **"Use an entire disk"**
3. ติ๊ก ✅ **"Encrypt the LVM group with LUKS"** แล้วตั้ง **passphrase ดิสก์**
4. สร้าง admin account แรก — **จำชื่อ user นี้ไว้** (เช่น `somchai`) จะใช้เป็น admin หลักต่อในหัวข้อ 3 และต้องใส่ใน `AllowUsers` ของ SSH
5. หน้า "SSH Setup" → ติ๊กเปิด OpenSSH server (จะได้ SSH เข้าได้ทันทีหลังลงเสร็จ)
6. ติดตั้งจนเสร็จ รีบูต (ตอนบูตจะถาม passphrase ดิสก์)

> 💡 **อธิบาย — LUKS ทำงานยังไง:** LUKS เข้ารหัสทั้ง partition ด้วย master key ที่ล็อกด้วย passphrase ของคุณ · ตอนบูตต้องใส่ passphrase เพื่อปลดล็อก ดิสก์ ถึงจะ mount และบูตต่อได้ · ป้องกันกรณี **ดิสก์/เครื่องถูกขโมย** — ถอดดิสก์ไปเสียบเครื่องอื่นก็อ่านไม่ออก · แต่ **ไม่ช่วย**ตอนเครื่องเปิดรันอยู่หรือโดนเจาะผ่านเน็ต (ตอนนั้น ดิสก์ ปลดล็อกแล้ว)

**ตรวจว่าเข้ารหัสจริง** — หา mapper name ก่อน (ชื่อต่างกันแต่ละเครื่อง):
```bash
lsblk -f | grep crypto_LUKS          # เห็น type crypto_LUKS = partition ถูกเข้ารหัส
lsblk                                # ดูชื่อ mapper เช่น dm_crypt-0 หรือ <disk>_crypt
sudo cryptsetup status <mapper-name> # แทน <mapper-name> ด้วยชื่อที่เห็น → ต้องขึ้น type: LUKS2
```

### 2.1 ปลดล็อกระยะไกลตอนรีบูต (เครื่อง headless) [High]

ทุกครั้งที่รีบูต เครื่องจะ**ค้างรอ passphrase ก่อนบูต** ถ้าเป็นเครื่องในศูนย์ข้อมูลไม่มีจอ ต้องตั้งวิธีปลดล็อกจากระยะไกล **ก่อน**เอาขึ้นจริง

**ตัวเลือก A — Dropbear (พิมพ์ passphrase ผ่าน SSH ตอนบูต)**
```bash
sudo apt install -y dropbear-initramfs
# 1) ใส่ public key สำหรับ unlock (คนละไฟล์กับ authorized_keys ปกติได้)
sudo tee /etc/dropbear/initramfs/authorized_keys < unlock_key.pub
# 2) ตั้ง static IP ให้ initramfs (จำเป็น! ไม่งั้น SSH เข้าตอนบูตไม่ได้)
#    แก้ /etc/initramfs-tools/initramfs.conf เพิ่มบรรทัด (IP=client::gateway:netmask::iface:off):
#    IP=10.0.0.10::10.0.0.1:255.255.255.0::eth0:off
sudo update-initramfs -u
```
ตอนบูต: SSH เข้าไปที่ IP เครื่อง (port 22 ของ initramfs) แล้วรันคำสั่งปลดล็อก:
```bash
ssh -i unlock_key root@10.0.0.10
cryptroot-unlock          # ใส่ passphrase → เครื่องบูตต่อ
```
> ⚠️ **ระวัง:** ถ้าข้ามขั้นตั้ง static IP เครื่องจะบูตมาค้างโดย SSH เข้าไม่ได้ ต้องไปต่อจอที่เครื่องจริง — **ทดสอบรีบูต 1 รอบใน staging** ให้แน่ใจว่า unlock ระยะไกลได้ก่อนขึ้น production

**ตัวเลือก B — Clevis + TPM2 (ปลดล็อกอัตโนมัติด้วยชิป TPM)**
```bash
sudo apt install -y clevis clevis-luks clevis-initramfs
lsblk                                        # หา partition ที่เป็น crypto_LUKS เช่น /dev/sda3
sudo clevis luks bind -d /dev/sda3 tpm2 '{}' # ผูก key กับ TPM ของเครื่องนี้
sudo update-initramfs -u
```
> 💡 **อธิบาย:** TPM เก็บ key ไว้ในชิปบนเมนบอร์ด เครื่องนี้บูตเองได้โดยไม่ต้องพิมพ์ passphrase · แต่ถ้า**ถอดดิสก์ไปเครื่องอื่น TPM ไม่มี → ปลดไม่ได้** (ซึ่งเป็นสิ่งที่เราต้องการ) · เหมาะกับเครื่องที่ต้องรีบูตเองบ่อย · **ควรเก็บ passphrase สำรองไว้เสมอ** เผื่อ TPM/เมนบอร์ดเสีย

> 💡 **คลาวด์ (AWS/GCP/Azure):** ข้ามหัวข้อ 2 ทั้งหมดได้ — เปิด การเข้ารหัสดิสก์ ของ provider ตอนสร้าง volume แทน (EBS encryption / CMEK) มัน unlock อัตโนมัติด้วย KMS ไม่ต้องยุ่งกับ dropbear/TPM

---
