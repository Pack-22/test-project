## 1. Preparation

### 1.1 Supported Ubuntu versions

This guide is tested on **Ubuntu Server LTS** — use LTS only for production (long support, continuous patching).

| Version | Status | Recommended |
|---|---|---|
| **24.04 LTS** (Noble) | supported until 2029 (ESM 2034) | ✅ **Recommended** — newest proven release |
| **22.04 LTS** (Jammy) | supported until 2027 (ESM 2032) | ✅ Supported — if your existing systems use it |
| **20.04 LTS** (Focal) | standard support ended (ESM only) | ⚠️ Avoid for new installs |
| **26.04 LTS** (if released) | very new | ⚠️ Wait for the first patch round + verify packages are ready |
| non-LTS (e.g. 25.x) | only 9 months of support | ❌ Don't use on servers |

> 💡 Commands in this guide target **24.04 / 22.04** · on other versions, verify package names/paths (e.g. `default-jre`, the MySQL config path) match

### 1.2 Prerequisites

- Ubuntu Server ISO **24.04 LTS** (recommended) or **22.04 LTS**
- **An SSH key pair per person**, generated on their own machine (not on the server) with the command below. Keep the **private key only on that person's machine**; hand only the `.pub` file to the admin to install on the server

```bash
ssh-keygen -t ed25519 -C "somchai@company"      # produces ~/.ssh/id_ed25519 (private) + .pub (public)
```

- A domain name whose A record points to the server IP (required to obtain a TLS cert in section 6)
- Recommended minimum spec: 2 vCPU / 4 GB RAM / 40 GB disk or more (MySQL + Tomcat + JVM use a fair amount of RAM)
- Plan ahead: the disk passphrase and where it's stored (password manager / safe) — **somewhere other than the machine**

> 💡 **Explain — why SSH keys, not passwords:** a key is a long, random public/private pair that's practically impossible to guess or brute-force, unlike passwords that people set short and reuse · we disable all password login in section 3 to shut down password-guessing attacks

---
