---
name: Bug report
about: Something doesn't work as expected
labels: bug
---

**What happened**

**What you expected**

**Steps to reproduce**
1.
2.

**Your Mac**
- macOS version:
- shyCloud version (About window):
- Mode in the menu (Scheduled, Sync On or Sync Off):

**If an app froze**, run this in Terminal and paste the output:
```
ps -axo pid,stat,comm | grep -E "/(bird|cloudd|photoanalysisd)$"
```
