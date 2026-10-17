## 2. Install Ubuntu + disk encryption (LUKS) [Critical]

> ⚠️ Must be done during installation — once installed, encrypting later means wiping and reinstalling

1. Boot from the ISO → pick language / keyboard / network
2. On **"Guided storage configuration"** → choose **"Use an entire disk"**
3. Tick ✅ **"Encrypt the LVM group with LUKS"** and set the **disk passphrase**
4. Create the first admin account — **remember this username** (e.g. `somchai`); it becomes the main admin in section 3 and must be added to SSH's `AllowUsers`
5. On "SSH Setup" → enable the OpenSSH server (so you can SSH in right after install)
6. Finish installing and reboot (boot will prompt for the disk passphrase)

> 💡 **Explain — how LUKS works:** LUKS encrypts the whole partition with a master key locked by your passphrase · at boot you must enter the passphrase to unlock the disk before it can mount and continue booting · it protects against a **stolen disk/machine** — pull the disk, plug it into another machine, and it's unreadable · but it does **not** help while the machine is running or is breached over the network (the disk is unlocked then)

**Verify it's actually encrypted** — find the mapper name first (differs per machine):
```bash
lsblk -f | grep crypto_LUKS          # seeing type crypto_LUKS = the partition is encrypted
lsblk                                # look for the mapper name e.g. dm_crypt-0 or <disk>_crypt
sudo cryptsetup status <mapper-name> # replace <mapper-name> with what you saw → should show type: LUKS2
```

### 2.1 Remote unlock at reboot (headless machines) [High]

Every reboot the machine **waits for the passphrase before booting**. For a data-center machine with no monitor, set up a remote unlock method **before** going live.

**Option A — Dropbear (type the passphrase over SSH at boot)**
```bash
sudo apt install -y dropbear-initramfs
# 1) add the public key used for unlock (can be a different file from the normal authorized_keys)
sudo tee /etc/dropbear/initramfs/authorized_keys < unlock_key.pub
# 2) set a static IP for initramfs (required! otherwise you can't SSH in at boot)
#    edit /etc/initramfs-tools/initramfs.conf, add a line (IP=client::gateway:netmask::iface:off):
#    IP=10.0.0.10::10.0.0.1:255.255.255.0::eth0:off
sudo update-initramfs -u
```
At boot: SSH to the machine IP (the initramfs's port 22) and run the unlock command:
```bash
ssh -i unlock_key root@10.0.0.10
cryptroot-unlock          # enter the passphrase → the machine continues booting
```
> ⚠️ **Caution:** if you skip the static IP step the machine boots and hangs with SSH unreachable — you'd have to attach a physical monitor. **Test one reboot in staging** to be sure remote unlock works before going to production

**Option B — Clevis + TPM2 (auto-unlock via the TPM chip)**
```bash
sudo apt install -y clevis clevis-luks clevis-initramfs
lsblk                                        # find the crypto_LUKS partition, e.g. /dev/sda3
sudo clevis luks bind -d /dev/sda3 tpm2 '{}' # bind the key to this machine's TPM
sudo update-initramfs -u
```
> 💡 **Explain:** the TPM stores the key in a chip on the motherboard, so this machine can boot itself without typing a passphrase · but **move the disk to another machine and there's no TPM → it can't unlock** (which is exactly what we want) · suited to machines that reboot themselves often · **always keep a backup passphrase** in case the TPM/motherboard fails

> 💡 **Cloud (AWS/GCP/Azure):** you can skip section 2 entirely — enable the provider's disk encryption when creating the volume instead (EBS encryption / CMEK); it auto-unlocks via KMS with no dropbear/TPM to deal with

---
