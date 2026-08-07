#!/usr/bin/env bash
# hw-inventory.sh v4 — emit a Markdown block describing this host.
#
# Read-only. Collects nothing off-box, writes nothing, sends nothing.
# Every command is a query. Deliberately absent: smartctl -t (self-tests),
# zpool scrub/import, btrfs balance/scrub, docker run/exec, mount/umount,
# systemctl start/stop, and any package operation. Unraid array state is read
# from emhttp's own .ini files rather than via `mdcmd`, which would mean
# writing a command into /proc/mdcmd — a read-only script should not do that.
#
# Run as root where possible: dmidecode (model, DIMM layout) and smartctl
# (disk health) need it. Without root the script still runs and marks those
# fields "(needs root)".
#
# Usage:
#   sudo bash hw-inventory.sh > "$(hostname)-$(date +%F).md"
#
# Note: run with `bash`, not `./`, and your fish shell stays out of the way.

set -u

have() { command -v "$1" >/dev/null 2>&1; }
NA="—"

# Wrap anything that can block on an unresponsive network mount or storage
# backend. df, findmnt and pvesm are the usual suspects.
TMO=""
have timeout && TMO="timeout 10"

kv() { printf '| %s | %s |\n' "$1" "${2:-$NA}"; }

# YAML-safe scalar for the frontmatter block.
yk() {
  local v=${2:-}
  v=${v//\\/\\\\}
  v=${v//\"/\\\"}
  if [ -z "$v" ]; then printf '%s: null\n' "$1"; else printf '%s: "%s"\n' "$1" "$v"; fi
}

# dmidecode wrapper: quiet, returns empty on failure or non-root
dmi() {
  have dmidecode || { echo ""; return; }
  $TMO dmidecode -s "$1" 2>/dev/null | grep -v '^#' | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

is_root() { [ "$(id -u)" -eq 0 ]; }

# =========================================================== gather first ===
# Frontmatter needs these before anything is printed.

HOST=$(hostname 2>/dev/null || echo unknown)

OSNAME=""; OSID=""
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  OSNAME=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-${NAME:-}}")
  OSID=$(. /etc/os-release 2>/dev/null && echo "${ID:-}")
fi
if [ -z "$OSNAME" ] && [ -r /etc/unraid-version ]; then
  OSNAME="Unraid $(sed 's/.*=//;s/"//g' /etc/unraid-version 2>/dev/null)"
  OSID="unraid"
fi
[ -z "$OSNAME" ] && OSNAME=$(uname -o 2>/dev/null || echo unknown)

KERN=$(uname -r)
ARCH=$(uname -m)

CPUMODEL=""
if have lscpu; then
  CPUMODEL=$($TMO lscpu 2>/dev/null | awk -F: '/^Model name/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
fi
[ -z "$CPUMODEL" ] && CPUMODEL=$(awk -F: '/model name/{gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)

RAMTOTAL=""
have free && RAMTOTAL=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}')

PLATFORM="bare-metal"
if have systemd-detect-virt; then
  DV=$(systemd-detect-virt 2>/dev/null || true)
  [ -n "$DV" ] && [ "$DV" != "none" ] && PLATFORM="$DV"
fi

PROD=$(dmi system-product-name)
MFR=$(dmi system-manufacturer)
SERIAL=$(dmi system-serial-number)
BOARD=$(dmi baseboard-product-name)
BIOS=$(dmi bios-version)

# Disks, used by both the inventory table and the SMART table.
DISKS=""
have lsblk && DISKS=$($TMO lsblk -dn -o NAME,TYPE 2>/dev/null \
  | awk '$2=="disk"{print $1}' | grep -Ev '^(loop|ram|zram|sr)' || true)

# ============================================================ frontmatter ===
printf -- '---\n'
yk host "$HOST"
yk os "$OSNAME"
yk os_id "$OSID"
yk kernel "$KERN"
yk arch "$ARCH"
yk platform "$PLATFORM"
yk model "${PROD:-}"
yk cpu "$CPUMODEL"
yk ram "${RAMTOTAL:-}"
printf 'role: ""            # fill in: nas | hypervisor | desktop | laptop\n'
printf 'collected: %s\n' "$(date '+%Y-%m-%d')"
printf 'collector: hw-inventory.sh v4\n'
printf 'tags: [homelab, inventory, hardware]\n'
printf -- '---\n\n'

# ---------------------------------------------------------------- header ----
printf '## %s\n\n' "$HOST"
printf '> Collected %s by `hw-inventory.sh`%s\n\n' \
  "$(date '+%Y-%m-%d %H:%M %Z')" \
  "$(is_root || echo ' — **not run as root**, some fields incomplete')"

# ------------------------------------------------------------ identity ------
printf '### Identity\n\n| Field | Value |\n|---|---|\n'
kv "Hostname" "$HOST"
kv "OS" "$OSNAME"
kv "Kernel" "$KERN"
kv "Arch" "$ARCH"
kv "Platform" "$PLATFORM"

if have pveversion; then
  kv "Proxmox VE" "$(pveversion 2>/dev/null | head -1)"
fi

if is_root && have dmidecode; then
  kv "Manufacturer" "${MFR:-$NA}"
  kv "Model" "${PROD:-$NA}"
  kv "Service tag / serial" "${SERIAL:-$NA}"
  kv "Motherboard" "${BOARD:-$NA}"
  kv "BIOS" "${BIOS:-$NA}"
else
  kv "Manufacturer / model" "(needs root — install/run dmidecode as root)"
fi
echo

# ------------------------------------------------------- volatile snapshot --
# Everything below changes between runs. Ignore this section when diffing two
# reports to spot real hardware changes.
printf '### Snapshot (volatile)\n\n| Field | Value |\n|---|---|\n'
UP=$(uptime -p 2>/dev/null || uptime 2>/dev/null | sed 's/.*up //;s/,.*load.*//')
kv "Uptime" "${UP:-$NA}"
if [ -r /proc/loadavg ]; then
  kv "Load average" "$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null)"
fi
if have free; then
  kv "RAM used / available" "$(free -h 2>/dev/null | awk '/^Mem:/{print $3" / "$7}')"
  kv "Swap used / total" "$(free -h 2>/dev/null | awk '/^Swap:/{print $3" / "$2}')"
fi
echo

# ----------------------------------------------------------------- CPU ------
printf '### CPU\n\n| Field | Value |\n|---|---|\n'
if have lscpu; then
  LC=$($TMO lscpu 2>/dev/null)
  kv "Model" "$CPUMODEL"
  kv "Sockets" "$(echo "$LC" | awk -F: '/^Socket\(s\)/{gsub(/ /,"",$2); print $2; exit}')"
  kv "Cores per socket" "$(echo "$LC" | awk -F: '/^Core\(s\) per socket/{gsub(/ /,"",$2); print $2; exit}')"
  kv "Threads per core" "$(echo "$LC" | awk -F: '/^Thread\(s\) per core/{gsub(/ /,"",$2); print $2; exit}')"
  kv "Logical CPUs" "$(echo "$LC" | awk -F: '/^CPU\(s\):/{gsub(/ /,"",$2); print $2; exit}')"
else
  kv "Model" "$CPUMODEL"
  kv "Logical CPUs" "$(grep -c ^processor /proc/cpuinfo 2>/dev/null)"
fi

VIRT="none detected"
grep -qm1 ' vmx' /proc/cpuinfo 2>/dev/null && VIRT="VT-x (vmx)"
grep -qm1 ' svm' /proc/cpuinfo 2>/dev/null && VIRT="AMD-V (svm)"
kv "Hardware virtualisation" "$VIRT"
echo

# ------------------------------------------------------- boot / kernel ------
printf '### Boot and kernel parameters\n\n| Field | Value |\n|---|---|\n'
if [ -d /sys/kernel/iommu_groups ] && [ -n "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
  kv "IOMMU groups" "$(ls /sys/kernel/iommu_groups 2>/dev/null | wc -l) (IOMMU active)"
else
  kv "IOMMU groups" "not active"
fi
if [ -r /sys/module/kvm_amd/parameters/nested ]; then
  kv "Nested virt (kvm_amd)" "$(cat /sys/module/kvm_amd/parameters/nested 2>/dev/null)"
elif [ -r /sys/module/kvm_intel/parameters/nested ]; then
  kv "Nested virt (kvm_intel)" "$(cat /sys/module/kvm_intel/parameters/nested 2>/dev/null)"
fi
if [ -r /sys/kernel/mm/transparent_hugepage/enabled ]; then
  kv "Transparent hugepages" "$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)"
fi
echo
if [ -r /proc/cmdline ]; then
  printf '**Kernel command line**\n\n```\n'
  cat /proc/cmdline 2>/dev/null
  printf '```\n\n'
fi

# ---------------------------------------------------------------- MEMORY ----
printf '### Memory\n\n| Field | Value |\n|---|---|\n'
have free && kv "Total RAM" "$RAMTOTAL"
have free && kv "Swap total" "$(free -h 2>/dev/null | awk '/^Swap:/{print $2}')"
if is_root && have dmidecode; then
  SLOTS=$($TMO dmidecode -t memory 2>/dev/null | grep -c '^Memory Device$')
  FILLED=$($TMO dmidecode -t memory 2>/dev/null | awk '/^\tSize:/ && $2 != "No" {c++} END{print c+0}')
  kv "DIMM slots (filled / total)" "$FILLED / $SLOTS"
  MAXCAP=$($TMO dmidecode -t 16 2>/dev/null | awk -F: '/Maximum Capacity/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
  kv "Max supported" "${MAXCAP:-$NA}"
fi
echo

if is_root && have dmidecode; then
  MODLINES=$($TMO dmidecode -t memory 2>/dev/null | awk '
    /^Memory Device$/ {loc="";size="";sp="";pn="";mf=""}
    /^\tLocator:/ {sub(/^\tLocator:[ \t]*/,""); loc=$0}
    /^\tSize:/ {sub(/^\tSize:[ \t]*/,""); size=$0}
    /^\tSpeed:/ && sp=="" {sub(/^\tSpeed:[ \t]*/,""); sp=$0}
    /^\tManufacturer:/ {sub(/^\tManufacturer:[ \t]*/,""); mf=$0}
    /^\tPart Number:/ {sub(/^\tPart Number:[ \t]*/,""); pn=$0
      if (size !~ /^No/) printf "| %s | %s | %s | %s | %s |\n", loc, size, sp, mf, pn}
  ')
  if [ -n "$MODLINES" ]; then
    printf '#### Installed DIMMs\n\n| Slot | Size | Speed | Vendor | Part number |\n|---|---|---|---|---|\n%s\n\n' "$MODLINES"
  fi
fi

# ---------------------------------------------------------------- STORAGE ---
printf '### Storage — physical devices\n\n'
if have lsblk; then
  printf '| Device | Size | Model | Serial | Type | Bus |\n|---|---|---|---|---|---|\n'
  # -P (key="value") is used deliberately: plain columnar output collapses
  # empty MODEL/SERIAL fields and silently shifts every later column.
  fld() { printf '%s' "$2" | sed -n "s/.*[[:space:]]\{0,\}$1=\"\([^\"]*\)\".*/\1/p"; }
  $TMO lsblk -dn -P -o NAME,SIZE,ROTA,TRAN,MODEL,SERIAL 2>/dev/null \
    | grep -Ev 'NAME="(loop|ram|zram|sr)[0-9]*"' \
    | while IFS= read -r line; do
        name=$(fld NAME "$line");   [ -z "$name" ] && continue
        size=$(fld SIZE "$line");   rota=$(fld ROTA "$line")
        tran=$(fld TRAN "$line");   model=$(fld MODEL "$line")
        serial=$(fld SERIAL "$line")
        case "$rota" in 1) kind="HDD";; 0) kind="SSD/NVMe";; *) kind="$NA";; esac
        printf '| /dev/%s | %s | %s | %s | %s | %s |\n' \
          "$name" "${size:-$NA}" "${model:-$NA}" "${serial:-$NA}" "$kind" "${tran:-$NA}"
      done
  echo
else
  printf '`lsblk` not available — list disks manually.\n\n'
fi

# ------------------------------------------------------------ SMART ---------
# -H (health summary) and -A (attributes) only. No -t: nothing is started,
# nothing is written to the drive.
if have smartctl && [ -n "$DISKS" ]; then
  printf '### Storage — SMART health\n\n'
  if ! is_root; then
    printf '_Not run as root — SMART data unavailable._\n\n'
  else
    printf '| Device | Health | Power-on hrs | Realloc / Pending | Wear | Temp |\n|---|---|---|---|---|---|\n'
    for d in $DISKS; do
      # -n standby: if the drive is spun down, report and move on rather than
      # waking it. Matters on a NAS with spun-down array disks.
      SM=$(timeout 15 smartctl -n standby -H -A -d auto "/dev/$d" 2>/dev/null || true)
      if printf '%s' "$SM" | grep -qi 'STANDBY mode'; then
        printf '| /dev/%s | (standby — not woken) | %s | %s | %s | %s |\n' "$d" "$NA" "$NA" "$NA" "$NA"
        continue
      fi
      [ -z "$SM" ] && { printf '| /dev/%s | %s | %s | %s | %s | %s |\n' "$d" "(no data)" "$NA" "$NA" "$NA" "$NA"; continue; }

      health=$(printf '%s\n' "$SM" | awk -F: '/overall-health|SMART Health Status/{gsub(/^[ \t]+/,"",$2); print $2; exit}')

      poh=$(printf '%s\n' "$SM" | awk '/Power_On_Hours/{print $10; exit}')
      [ -z "$poh" ] && poh=$(printf '%s\n' "$SM" | awk -F: '/^Power On Hours/{gsub(/[ ,]/,"",$2); print $2; exit}')

      ra=$(printf '%s\n' "$SM" | awk '/Reallocated_Sector_Ct/{print $10; exit}')
      pe=$(printf '%s\n' "$SM" | awk '/Current_Pending_Sector/{print $10; exit}')
      if [ -n "$ra" ] || [ -n "$pe" ]; then rp="${ra:-$NA} / ${pe:-$NA}"; else rp="$NA"; fi

      wear=$(printf '%s\n' "$SM" | awk -F: '/^Percentage Used/{gsub(/[ ]/,"",$2); print $2" used"; exit}')
      [ -z "$wear" ] && wear=$(printf '%s\n' "$SM" | awk '/Wear_Leveling_Count|Media_Wearout_Indicator/{print $4" (norm)"; exit}')

      tmp=$(printf '%s\n' "$SM" | awk '/Temperature_Celsius|Airflow_Temperature/{print $10"C"; exit}')
      [ -z "$tmp" ] && tmp=$(printf '%s\n' "$SM" | awk -F: '/^Temperature:/{gsub(/^[ \t]+/,"",$2); print $2; exit}')

      printf '| /dev/%s | %s | %s | %s | %s | %s |\n' \
        "$d" "${health:-$NA}" "${poh:-$NA}" "$rp" "${wear:-$NA}" "${tmp:-$NA}"
    done
    echo
    if timeout 15 smartctl --scan 2>/dev/null | grep -q .; then
      printf '**`smartctl --scan` sees:**\n\n```\n'
      timeout 15 smartctl --scan 2>/dev/null | head -40
      printf '```\n\n'
    fi
    printf '_Drives behind a hardware RAID controller do not appear above — see the RAID controller section._\n\n'
  fi
fi

# ------------------------------------------------------------ RAID CTRL ----
# Hardware RAID (Dell PERC, LSI/Broadcom MegaRAID, HP Smart Array).
# Vendor CLIs are invoked with `show` verbs only. Never add/delete/set/start.
RAIDCTL=""
have lspci && RAIDCTL=$($TMO lspci 2>/dev/null | grep -iE 'MegaRAID|PERC|LSI.*RAID|Smart Array|cciss|RAID bus controller' | head -4)

if [ -n "$RAIDCTL" ]; then
  printf '### RAID controller\n\n```\n%s\n```\n\n' "$RAIDCTL"

  RCLI=""
  for c in perccli64 perccli storcli64 storcli; do
    have "$c" && { RCLI=$(command -v "$c"); break; }
  done

  if [ -n "$RCLI" ]; then
    # /call = all controllers, /vall = all virtual drives, /eall/sall = all
    # physical drives on all enclosures. All read-only.
    printf '#### Controller and array topology\n\n```\n'
    timeout 25 "$RCLI" /call show 2>/dev/null | head -45
    echo
    echo "--- virtual drives ---"
    timeout 25 "$RCLI" /call/vall show 2>/dev/null | head -45
    echo
    echo "--- physical drives ---"
    timeout 25 "$RCLI" /call/eall/sall show 2>/dev/null | head -70
    printf '```\n\n'
  elif have megacli || have MegaCli64; then
    MCLI=$(command -v megacli 2>/dev/null || command -v MegaCli64 2>/dev/null)
    printf '#### Controller and array topology (MegaCLI)\n\n```\n'
    timeout 25 "$MCLI" -LDInfo -Lall -aALL -NoLog 2>/dev/null | head -60
    echo
    echo "--- physical drives ---"
    timeout 25 "$MCLI" -PDList -aALL -NoLog 2>/dev/null \
      | grep -E 'Slot Number|Inquiry Data|Raw Size|Firmware state|Media Error|Other Error|Predictive|Drive Temperature' \
      | head -90
    printf '```\n\n'
  else
    printf '_No vendor CLI found. Install `perccli64` (Dell) or `storcli64` (Broadcom) for array topology — neither is required for the per-drive SMART below._\n\n'
  fi

  # Per-drive SMART behind the controller. The controller hides drives from
  # normal addressing, so each is queried by its controller device ID.
  if is_root && have smartctl; then
    MRTGT=""
    for d in $DISKS; do
      case "$d" in nvme*) continue;; esac
      MRTGT="$d"; break
    done
    if [ -n "$MRTGT" ]; then
      MRROWS=""; misses=0
      for n in {0..31}; do
        MS=$(timeout 6 smartctl -n standby -H -A -d "megaraid,$n" "/dev/$MRTGT" 2>/dev/null || true)
        if ! printf '%s' "$MS" | grep -qiE '^Device Model:|^Model Number:|^Product:|^Serial Number:'; then
          misses=$((misses + 1))
          # Device IDs can be sparse; give up only after a long empty run.
          [ "$misses" -ge 10 ] && break
          continue
        fi
        misses=0
        mdl=$(printf '%s\n' "$MS" | awk -F: '/^Device Model:|^Model Number:|^Product:/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
        ser=$(printf '%s\n' "$MS" | awk -F: '/^Serial Number:/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
        hlt=$(printf '%s\n' "$MS" | awk -F: '/overall-health|SMART Health Status/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
        poh=$(printf '%s\n' "$MS" | awk '/Power_On_Hours/{print $10; exit}')
        [ -z "$poh" ] && poh=$(printf '%s\n' "$MS" | awk -F: '/number of hours powered up/{gsub(/[ ,]/,"",$2); print int($2); exit}')
        ra=$(printf '%s\n' "$MS" | awk '/Reallocated_Sector_Ct/{print $10; exit}')
        tmp=$(printf '%s\n' "$MS" | awk '/Temperature_Celsius|Airflow_Temperature/{print $10"C"; exit}')
        [ -z "$tmp" ] && tmp=$(printf '%s\n' "$MS" | awk -F: '/^Current Drive Temperature/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
        MRROWS="${MRROWS}| megaraid,${n} | ${mdl:-$NA} | ${ser:-$NA} | ${hlt:-$NA} | ${poh:-$NA} | ${ra:-$NA} | ${tmp:-$NA} |
"
      done
      if [ -n "$MRROWS" ]; then
        printf '#### Physical drive SMART (behind controller)\n\n'
        printf '| Device ID | Model | Serial | Health | Power-on hrs | Realloc | Temp |\n'
        printf '|---|---|---|---|---|---|---|\n%s\n' "$MRROWS"
      else
        printf '_No drives answered `-d megaraid,N`. The controller may be in HBA/IT mode (drives already listed above), or may need `-d cciss,N` instead._\n\n'
      fi
    fi
  fi
fi

# ---------------------------------------------------------------- UNRAID ---
# emhttp maintains these as plain files; reading them avoids `mdcmd`, which
# would require writing a command into /proc/mdcmd. Keys are whitelisted
# deliberately — var.ini also holds a csrf_token that must never be emitted.
if [ -r /var/local/emhttp/var.ini ] || [ -r /var/local/emhttp/disks.ini ]; then
  printf '### Unraid array\n\n'

  if [ -r /var/local/emhttp/var.ini ]; then
    printf '| Field | Value |\n|---|---|\n'
    uval() { awk -F= -v k="$1" '$1==k{gsub(/"/,"",$2); print $2; exit}' /var/local/emhttp/var.ini 2>/dev/null; }
    kv "Array state"        "$(uval mdState)"
    kv "Data disks"         "$(uval mdNumDisks)"
    kv "Disks missing"      "$(uval mdNumMissing)"
    kv "Disks invalid"      "$(uval mdNumInvalid)"
    kv "Disks disabled"     "$(uval mdNumDisabled)"
    kv "Parity check state" "$(uval mdResyncAction)"
    kv "Last sync errors"   "$(uval sbSyncErrs)"
    kv "Filesystem state"   "$(uval fsState)"
    echo
  fi

  if [ -r /var/local/emhttp/disks.ini ]; then
    UDISKS=$(awk -F= '
      function hs(kb,  x) {
        x = kb + 0
        if (kb == "" || x == 0) return "—"
        if (x >= 1073741824) return sprintf("%.2f TB", x/1073741824)
        if (x >= 1048576)    return sprintf("%.1f GB", x/1048576)
        return sprintf("%.0f MB", x/1024)
      }
      function pct(u, t) { if (t+0 == 0) return "—"; return sprintf("%.0f%%", (u+0)*100/(t+0)) }
      function row() {
        if (sec == "") return
        if (dev == "" && id == "") return
        printf "| %s | %s | %s | %s | %s | %s | %s | %s |\n", \
          sec, (dev==""?"—":"/dev/" dev), (id==""?"—":id), hs(sz), \
          (fs==""?"—":fs), (fsz==""?"—":hs(fsz) " (" pct(fu,fsz) " used)"), \
          (st==""?"—":st), (tp==""||tp=="*"?"—":tp "C")
      }
      /^\[/ { row(); sec=$0; gsub(/[\["\]]/,"",sec)
              dev="";id="";sz="";st="";tp="";fs="";fsz="";fu=""; next }
      {
        k=$1; v=$0; sub(/^[^=]*=/,"",v); gsub(/"/,"",v)
        if      (k=="device") dev=v
        else if (k=="id")     id=v
        else if (k=="size")   sz=v
        else if (k=="status") st=v
        else if (k=="temp")   tp=v
        else if (k=="fsType") fs=v
        else if (k=="fsSize") fsz=v
        else if (k=="fsUsed") fu=v
      }
      END { row() }
    ' /var/local/emhttp/disks.ini 2>/dev/null)
    if [ -n "$UDISKS" ]; then
      printf '#### Array slots\n\n'
      printf '| Slot | Device | Identity | Raw size | FS | Filesystem | Status | Temp |\n'
      printf '|---|---|---|---|---|---|---|---|\n%s\n\n' "$UDISKS"
      printf '_Slot names are Unraid roles: `parity` is parity, `disk1..N` are array data disks, `cache*` are pools, `flash` is the USB boot device._\n\n'
    fi
  fi

  # Share-level cache and allocation policy. Relevant to mover behaviour.
  if [ -d /boot/config/shares ]; then
    USHARES=$(for f in /boot/config/shares/*.cfg; do
      [ -r "$f" ] || continue
      n=$(basename "$f" .cfg)
      g() { awk -F= -v k="$1" '$1==k{gsub(/"/,"",$2); print $2; exit}' "$f" 2>/dev/null; }
      printf '| %s | %s | %s | %s | %s |\n' \
        "$n" "$(g shareUseCache)" "$(g shareCachePool)" \
        "$(g shareAllocator)" "$(g shareInclude)"
    done)
    if [ -n "$USHARES" ]; then
      printf '#### Shares\n\n| Share | Use cache | Cache pool | Allocator | Included disks |\n|---|---|---|---|---|\n%s\n\n' "$USHARES"
      printf '_`shareUseCache`: `yes` = land on cache, mover migrates to array; `prefer` = keep on cache; `only` = cache only, mover never touches; `no` = array only._\n\n'
    fi
  fi

  if [ -r /boot/config/ident.cfg ]; then
    kv2=$(awk -F= '$1=="NAME"||$1=="COMMENT"{gsub(/"/,"",$2); print $1"="$2}' /boot/config/ident.cfg 2>/dev/null | paste -sd', ' -)
    [ -n "$kv2" ] && printf 'Flash identity: `%s`\n\n' "$kv2"
  fi
fi

printf '### Storage — filesystems and pools\n\n'
printf '```\n'
if have df; then
  echo "--- df -hT ---"
  $TMO df -hT 2>/dev/null | grep -Ev '^(tmpfs|devtmpfs|efivarfs|overlay|none)' | head -60
fi
if have findmnt; then
  echo
  echo "--- findmnt (mount options) ---"
  $TMO findmnt --real -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null | head -60
fi
if have zpool; then
  echo
  echo "--- zpool list ---"
  timeout 20 zpool list 2>/dev/null
  echo "--- zpool status -x ---"
  timeout 20 zpool status -x 2>/dev/null
fi
if have btrfs; then
  echo
  echo "--- btrfs filesystem show ---"
  $TMO btrfs filesystem show 2>/dev/null | head -20
fi
if have pvesm; then
  echo
  echo "--- pvesm status ---"
  $TMO pvesm status 2>/dev/null
fi
printf '```\n\n'

# ---------------------------------------------------------------- NETWORK ---
printf '### Network interfaces\n\n'
if ! have ip; then
  printf '`ip` (iproute2) not available — record interfaces manually.\n\n'
else
  printf '| Interface | State | MAC | Addresses | Link speed |\n|---|---|---|---|---|\n'
  $TMO ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//' | while read -r ifc; do
    [ "$ifc" = "lo" ] && continue
    state=$(cat "/sys/class/net/$ifc/operstate" 2>/dev/null || echo "$NA")
    mac=$(cat "/sys/class/net/$ifc/address" 2>/dev/null || echo "$NA")
    addrs=$($TMO ip -o -4 addr show dev "$ifc" 2>/dev/null | awk '{print $4}' | paste -sd', ' -)
    [ -z "$addrs" ] && addrs="$NA"
    spd=$(cat "/sys/class/net/$ifc/speed" 2>/dev/null)
    if [ -n "$spd" ] && [ "$spd" -gt 0 ] 2>/dev/null; then spd="${spd} Mb/s"; else spd="$NA"; fi
    printf '| %s | %s | %s | %s | %s |\n' "$ifc" "$state" "$mac" "$addrs" "$spd"
  done
  echo
  DEFRT=$($TMO ip route show default 2>/dev/null | head -1)
  [ -n "$DEFRT" ] && printf 'Default route: `%s`\n\n' "$DEFRT"
  if [ -r /etc/resolv.conf ]; then
    printf 'Resolvers: `%s`\n\n' "$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd', ' -)"
  fi
fi

# ---------------------------------------------------------------- PCI -------
# -nn gives vendor:device IDs, -k gives the bound driver. Both matter more
# than the human-readable name when diagnosing a driver problem.
if have lspci; then
  printf '### Notable PCI devices\n\n```\n'
  $TMO lspci -nnk 2>/dev/null | awk '
    /^[0-9a-f][0-9a-f]:/ { keep = (tolower($0) ~ /vga|3d controller|display|ethernet|network|raid|sata|non-volatile|serial attached/) }
    keep
  ' | head -60
  printf '```\n\n'
fi

# ------------------------------------------------------------ BMC / IPMI ---
# Local baseboard controller (iDRAC, iLO, generic IPMI). Read-only verbs only:
# info, print, list, sdr. Never `chassis power`, never `sel clear`, never
# `mc reset`. If the ipmi kernel modules are not loaded there is no device
# node and this section skips — the script does not modprobe, that is a change.
if have ipmitool && is_root && { [ -e /dev/ipmi0 ] || [ -e /dev/ipmi/0 ] || [ -e /dev/ipmidev/0 ]; }; then
  printf '### BMC / IPMI (iDRAC, iLO)\n\n'

  MCINFO=$(timeout 15 ipmitool mc info 2>/dev/null \
    | grep -E 'Manufacturer Name|Product Name|Firmware Revision|IPMI Version' | head -6)
  [ -n "$MCINFO" ] && printf '```\n%s\n```\n\n' "$MCINFO"

  # Community strings and auth settings are filtered out deliberately.
  LANINFO=$(timeout 15 ipmitool lan print 1 2>/dev/null \
    | grep -viE 'community|password|cipher|auth type' \
    | grep -E 'IP Address|Subnet Mask|MAC Address|Default Gateway' | head -8)
  [ -n "$LANINFO" ] && printf '**BMC network**\n\n```\n%s\n```\n\n' "$LANINFO"

  SENS=$(timeout 30 ipmitool sdr elist 2>/dev/null | grep -viE '\| ns \|' | head -45)
  [ -n "$SENS" ] && printf '**Sensors**\n\n```\n%s\n```\n\n' "$SENS"

  SEL=$(timeout 25 ipmitool sel list 2>/dev/null | tail -15)
  [ -n "$SEL" ] && printf '**System event log (last 15 entries)**\n\n```\n%s\n```\n\n' "$SEL"
elif have ipmitool && is_root; then
  printf '### BMC / IPMI\n\n'
  printf '_`ipmitool` present but no IPMI device node. The `ipmi_si` and `ipmi_devintf` modules are not loaded; this script will not load them. Load them yourself if you want BMC data here._\n\n'
fi

if have racadm; then
  RAC=$(timeout 20 racadm getsysinfo 2>/dev/null \
    | grep -viE 'password|community' | head -35)
  [ -n "$RAC" ] && printf '**racadm getsysinfo**\n\n```\n%s\n```\n\n' "$RAC"
fi

# ---------------------------------------------------------------- PROXMOX ---
if have pveversion || have pct || have qm; then
  printf '### Proxmox\n\n'

  if have pveversion; then
    PVEV=$(timeout 15 pveversion -v 2>/dev/null | head -30)
    [ -n "$PVEV" ] && printf '#### Package versions\n\n```\n%s\n```\n\n' "$PVEV"
  fi

  # Reads the config text held in $CFG by the loops below.
  cfgget() { printf '%s\n' "$CFG" | awk -F': ' -v k="$1" '$1==k{sub(/^[^:]*: /,""); print; exit}'; }

  # ---- LXC containers ----
  if have pct; then
    CTIDS=$(timeout 20 pct list 2>/dev/null | awk 'NR>1{print $1}')
    CTROWS=""
    for id in $CTIDS; do
      CFG=$(timeout 10 pct config "$id" 2>/dev/null || true)
      [ -z "$CFG" ] && continue
      st=$(timeout 10 pct status "$id" 2>/dev/null | awk '{print $2}')
      net0=$(cfgget net0)
      ctip=$(printf '%s' "$net0" | sed -n 's/.*ip=\([^,]*\).*/\1/p')
      ctbr=$(printf '%s' "$net0" | sed -n 's/.*bridge=\([^,]*\).*/\1/p')
      mem=$(cfgget memory)
      unp=$(cfgget unprivileged)
      case "$unp" in 1) unp="yes";; 0) unp="no";; *) unp="no";; esac
      CTROWS="${CTROWS}| ${id} | $(cfgget hostname) | ${st:-$NA} | $(cfgget ostype) | $(cfgget cores) | ${mem:-$NA} MiB | $(cfgget rootfs) | ${unp} | $(cfgget features) | ${ctip:-$NA} | ${ctbr:-$NA} | $(cfgget onboot) |
"
    done
    if [ -n "$CTROWS" ]; then
      printf '#### LXC containers\n\n'
      printf '| VMID | Hostname | Status | OS | Cores | RAM | Root disk | Unpriv | Features | IP | Bridge | Onboot |\n'
      printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n%s\n' "$CTROWS"
    fi
  fi

  # ---- QEMU VMs ----
  if have qm; then
    VMIDS=$(timeout 20 qm list 2>/dev/null | awk 'NR>1{print $1}')
    VMROWS=""
    for id in $VMIDS; do
      CFG=$(timeout 10 qm config "$id" 2>/dev/null || true)
      [ -z "$CFG" ] && continue
      vst=$(timeout 10 qm status "$id" 2>/dev/null | awk '{print $2}')
      vdisks=$(printf '%s\n' "$CFG" | grep -E '^(scsi|virtio|sata|ide)[0-9]+:' \
        | grep -v 'media=cdrom' | sed 's/: /=/' | paste -sd'; ' -)
      vnet=$(printf '%s\n' "$CFG" | grep -E '^net[0-9]+:' | sed 's/: /=/' | paste -sd'; ' -)
      VMROWS="${VMROWS}| ${id} | $(cfgget name) | ${vst:-$NA} | $(cfgget cores) | $(cfgget memory) MiB | ${vdisks:-$NA} | ${vnet:-$NA} | $(cfgget ostype) | $(cfgget onboot) |
"
    done
    if [ -n "$VMROWS" ]; then
      printf '#### QEMU virtual machines\n\n'
      printf '| VMID | Name | Status | Cores | RAM | Disks | Network | OS type | Onboot |\n'
      printf '|---|---|---|---|---|---|---|---|---|\n%s\n' "$VMROWS"
    fi
  fi

  if have pvecm; then
    CLU=$(timeout 15 pvecm status 2>/dev/null | head -20)
    [ -n "$CLU" ] && printf '#### Cluster\n\n```\n%s\n```\n\n' "$CLU"
  fi
fi

# ---------------------------------------------------------------- DOCKER ----
if have docker && $TMO docker info >/dev/null 2>&1; then
  printf '### Docker\n\n```\n'
  $TMO docker version --format 'Docker {{.Server.Version}}' 2>/dev/null
  echo
  $TMO docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | head -100
  printf '```\n\n'
  # Network + container IP per container. docker inspect is read-only.
  DNET=$($TMO docker ps -a --format '{{.Names}}' 2>/dev/null | head -100 | while read -r c; do
    nets=$(timeout 5 docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{if $v.IPAddress}}{{$v.IPAddress}}{{else}}—{{end}} {{end}}' "$c" 2>/dev/null)
    [ -n "$nets" ] && printf '| %s | %s |\n' "$c" "$nets"
  done)
  if [ -n "$DNET" ]; then
    printf '#### Container networks\n\n| Container | Network=IP |\n|---|---|\n%s\n\n' "$DNET"
  fi
fi

# ---------------------------------------------------------------- SERVICES --
if have systemctl; then
  FAILED=$($TMO systemctl --failed --no-legend --no-pager 2>/dev/null | head -20)
  printf '### Failed systemd units\n\n'
  if [ -n "$FAILED" ]; then
    printf '```\n%s\n```\n\n' "$FAILED"
  else
    printf 'None.\n\n'
  fi
fi

printf -- '---\n*End of report for %s.*\n' "$HOST"
