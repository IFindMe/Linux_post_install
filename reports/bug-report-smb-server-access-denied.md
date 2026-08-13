Here is a concise bug report you can hand off to the developers of `pos` (or use to fix the script if you maintain it yourself).

---

## 🐛 Bug Report: `pos share smb-server` Creates Inaccessible Shares

### **Issue Description**

When adding a share with `pos share smb-server share <path> --users <user>`, the command successfully adds the share to `/etc/samba/smb.conf` and reloads `smbd`. However, clients receive `NT_STATUS_ACCESS_DENIED` upon connecting.

---

### **Root Causes**

1. **Missing Samba User Credentials (`smbpasswd`)**
* **Problem:** `pos` configures `valid users = <user>` in `smb.conf`, but fails to initialize or sync the user in Samba's passdb (`passdb.tdb`). Standard Linux account credentials in `/etc/shadow` are not recognized by Samba without `smbpasswd`.
* **Result:** Samba rejects authentication or tree connection requests.


2. **Parent Directory Permission Lockdown**
* **Problem:** When sharing a path inside a user's home directory (e.g., `/home/username/shared`), default Linux home permissions are set to `700` (`drwx------`). Samba cannot traverse `/home/username` to reach `/home/username/shared`.
* **Result:** `NT_STATUS_ACCESS_DENIED` due to missing `+x` (traversal) permission on parent directories.



---

### **Proposed Fixes for `pos` CLI**

#### **Fix 1: Register User in Samba Database**

When `--users <user>` is passed, check if the user exists in `pdbedit -L`. If missing, prompt for a Samba password or run:

```bash
sudo smbpasswd -a <user>
sudo smbpasswd -e <user>

```

#### **Fix 2: Automate Parent Directory Traversal Sanity Check**

Before adding a share path (e.g., `/home/user/share`), inspect parent directory permissions. If `others` lack execution rights (`+x`), automatically run or prompt:

```bash
chmod o+x /home/<user>

```

---

### **Workaround (Manual Fix)**

To fix the share created by `pos` right now, run:

```bash
# 1. Set traversal rights on home directory
chmod o+x /home/unknown

# 2. Add user to Samba database
sudo smbpasswd -a unknown

# 3. Restart Samba daemon
sudo systemctl restart smbd

```
