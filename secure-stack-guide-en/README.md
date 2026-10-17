# Secure Stack Installation Guide

`Updated 2026-10-17` · for System Engineers (setup & deploy) · supports Ubuntu 24.04 / 22.04 LTS

Step-by-step installation guide for a **Secure Stack (Ubuntu · Nginx · Tomcat 9 · MySQL)**,
from a bare machine to a running, secured system — split into small files for easy reading and editing.

## Files in this set

| File | Contents |
|------|----------|
| `00-cover.md` | Cover · intro · severity labels (`[Critical]`/`[High]`/`[Hardening]`) · how to read |
| `01-toc.md` | Table of contents |
| `main-sections/` | Main content, sections 1 → 10, one file each (`02-01-…` to `02-10-…`) |
| `03-appendix.md` | Appendix A–E (retention standards · per-log details · ship logs to central · runbook · preventive maintenance) + the "Must not miss" summary |

## How to use

1. Start with `00-cover.md` to understand the labels and how to read
2. Follow the files in `main-sections/` in order **1 → 10** (do not skip section 2 — disk encryption can't be done retroactively)
3. Use `03-appendix.md` as reference (retention standards, the troubleshooting runbook, routine maintenance)

## Before you start

- 🧪 Always test in **staging** before touching production
- 🔒 Do not skip **section 2** (disk encryption) — it cannot be done retroactively
- Keep an SSH session open while editing SSH/firewall (avoid locking yourself out)
