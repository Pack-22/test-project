# Secure Stack Installation Guide

### Ubuntu · Nginx · Tomcat · MySQL

`Updated 2026-10-17`

A step-by-step installation guide from a bare machine to a running, secured system — follow sections 1 → 10 in order.

**Before you start**
- 🧪 Always test in **staging** before touching production
- 🔒 Do **not** skip **section 2** (disk encryption) — it cannot be done retroactively

**Severity labels** — `[Critical]` must not skip · `[High]` should do · `[Hardening]` optional extra

**How to read** — each section has 💡 **Explain** (why / how it works) and ⚠️ **Caution** (where it breaks) · replace `<...>` placeholders and sample names (`somchai`, `yourdomain.com`) with your real values

---
