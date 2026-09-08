#!/usr/bin/env bash
# hw-inventory.sh v5 — emit a Markdown block describing this host.
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
#
# Exit codes (the report is written in full either way — read it, not just $?):
#   0  collection complete
#   1  completed, but one or more collectors failed; see `## Collection
#      warnings` at the end of the report for which ones
# A section skipped because the hardware or tool is genuinely absent is NOT a
# warning. A tool that was present, permitted, and still returned nothing IS.
# That distinction is the whole point: this output is consumed as ground truth,
# so a silently empty section must not read as "this host has none of that".

set -u
export LC_ALL=C

# ------------------------------------------------------- output-cap limits --
# Every `head -N` that truncates real, potentially-large output (as opposed
# to extracting a single known-shape value — see the bare `head -1` sites at
# dmi(), the Proxmox VE identity line, and the default route) has a named
# constant here, consumed through cap() below instead of head directly, so a
# hit limit grows a visible marker instead of vanishing silently (F-014).
#
# Two sites that share a NUMBER are not merged into one constant unless they
# also share a PURPOSE: MegaCLI's physical-drive listing and df's table cap
# both happen to land on 60/90-ish values, but they are unrelated knobs a
# future change should be able to retune independently.

# SMART
SMART_SCAN_LINES=40          # `smartctl --scan` enumerates every device it can
                              # see, not just $DISKS — generous headroom for a
                              # host with several controllers attached.

# RAID controller / vendor CLI
RAID_CTRL_LINES=4            # lspci lines matching a RAID-controller string;
                              # a host would need 5+ distinct controllers to
                              # hit this, effectively a sanity bound.
RAID_CLI_SUMMARY_LINES=45    # perccli/storcli controller info and virtual-
                              # drive listing (/call show, /call/vall show).
RAID_CLI_DRIVES_LINES=70     # perccli/storcli physical-drive listing
                              # (/call/eall/sall show) — scales with drive
                              # count, so more headroom than the summary.
MEGACLI_LD_LINES=60          # MegaCLI logical/virtual drive listing.
MEGACLI_PD_LINES=90          # MegaCLI physical-drive listing — one block of
                              # named fields per drive, so this scales with
                              # drive count, unlike the IPMI field caps below.

# Filesystems and pools
FS_TABLE_LINES=60            # df -hT and findmnt real-mount tables.
FS_BTRFS_LINES=20            # `btrfs filesystem show` — compact even with
                              # several volumes, so a smaller cap than df/findmnt.

# PCI
PCI_DEVICE_LINES=60          # notable PCI devices, after the
                              # vga|3d|ethernet|... keep filter.

# IPMI / BMC
IPMI_IDENTITY_LINES=6        # `ipmitool mc info` grepped for 4 named fields
                              # (Manufacturer/Product/Firmware/IPMI Version).
                              # Tracks an expected FIELD count, not an
                              # open-ended corpus — headroom is for a field
                              # appearing twice, not for "more BMCs".
IPMI_LAN_LINES=8             # `ipmitool lan print` grepped for 4 named
                              # fields; same reasoning as IPMI_IDENTITY_LINES.
                              # The grep patterns can each match more than one
                              # line (e.g. "IP Address" also matches inside
                              # "Default Gateway IP Address"), hence 2x.
IPMI_SENSOR_LINES=45         # `ipmitool sdr elist` — a big server can have
                              # dozens of sensors; this one IS a real corpus cap.
RACADM_LINES=35              # `racadm getsysinfo`.

# Proxmox
PVE_VERSIONS_LINES=30        # `pveversion -v` package list.
PVE_CLUSTER_LINES=20         # `pvecm status`.

# Docker — shared by the visible container table and the container-name list
# that drives the network-IP lookup loop. See the CNAMES site in the Docker
# section for why the latter cannot use cap()'s inline marker.
DOCKER_LIST_LIMIT=100

# systemd
SYSTEMD_FAILED_LINES=20      # `systemctl --failed`.

# cap N noun — read stdin, emit at most N lines, and if there was a
# truncated (N+1)th line, append one "--- truncated at N noun ---" marker,
# matching the "--- xyz ---" divider style already used throughout this file
# for meta-commentary lines inside a fenced block.
#
# Built on `head -$((N+1))`, not a read loop: cap's own `head` subprocess is
# what's attached to the incoming pipe, so it closes its read end after N+1
# lines exactly like a bare `head -N` would, and a slow upstream producer
# (smartctl, ipmitool, perccli) still gets SIGPIPE and exits promptly. The
# `set -o pipefail` rejection in .claude/rules/ rests on that early-close
# behaviour continuing to hold; a manual read loop would not preserve it.
#
# Zero lines in -> zero lines out, marker included: sections are captured to
# a variable and printed only if non-empty (Conventions, .claude/rules/),
# and a marker on empty input would defeat that at every call site at once —
# a host with no RAID controller would grow a "truncated" note where nothing
# should print at all.
#
# Never calls warn(): truncation is not a collector failure, the tool ran and
# answered. warn() could not be called from here safely regardless — cap runs
# as the tail of a pipeline, which is a subshell, and a warn() mutation from
# inside one is silently lost (G-002, docs/DISPOSITIONS.md).
#
# Not used for the Docker CNAMES site: that list is word-split into
# `docker inspect` arguments downstream, so a marker line appended to its
# output would be passed as a bogus container name. See that site instead.
cap() {
  local n=$1 noun=$2
  local out
  out=$(head -n "$((n + 1))")
  [ -z "$out" ] && return
  local total
  total=$(printf '%s\n' "$out" | wc -l)
  printf '%s\n' "$out" | head -n "$n"
  if [ "$total" -gt "$n" ]; then
    printf -- '--- truncated at %d %s ---\n' "$n" "$noun"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }
NA="—"

# Wrap anything that can block on an unresponsive network mount or storage
# backend. df, findmnt and pvesm are the usual suspects. TMO is the default
# 10s wrapper; tmo() below applies the same "have timeout" gate for call
# sites that need a different duration, instead of hardcoding `timeout N`
# and bypassing the fallback for systems without coreutils timeout.
TMO=()
have timeout && TMO=(timeout 10)

# tmo N cmd... — run cmd under `timeout N` if installed, or run it bare.
tmo() {
  local n=$1; shift
  if have timeout; then timeout "$n" "$@"; else "$@"; fi
}

# Collection warnings. A collector that was present and permitted but returned
# nothing appends here; the report ends with a `## Collection warnings` block
# and the script exits 1. Accumulated as a newline-joined string rather than an
# array so it stays safe under `set -u` on older bash, matching how MRROWS and
# CTROWS are built below.
#
# warn() MUST only be called from the main shell. Pipeline bodies and command
# substitutions run in subshells, so a warn() inside one is silently lost (see
# G-002 in docs/DISPOSITIONS.md). Where a section's rows are produced
# by a `... | while read` pipeline, capture the pipeline into a variable first
# and test that variable out here — see the storage and network tables.
WARNINGS=""
WARNCOUNT=0
warn() {
  WARNCOUNT=$((WARNCOUNT + 1))
  WARNINGS="${WARNINGS}- ${1}
"
}

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
  "${TMO[@]}" dmidecode -s "$1" 2>/dev/null | grep -v '^#' | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
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
  CPUMODEL=$("${TMO[@]}" lscpu 2>/dev/null | awk -F: '/^Model name/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
fi
[ -z "$CPUMODEL" ] && CPUMODEL=$(awk -F: '/model name/{gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
[ -z "$CPUMODEL" ] && warn 'CPU model unknown: neither `lscpu` nor /proc/cpuinfo yielded a model name.'

RAMTOTAL=""
have free && RAMTOTAL=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}')
if have free && [ -z "$RAMTOTAL" ]; then
  warn '`free` is installed but reported no total memory — RAM fields are empty.'
fi

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
LSBLK_RAW=""
if have lsblk; then
  LSBLK_RAW=$("${TMO[@]}" lsblk -dn -o NAME,TYPE 2>/dev/null || true)
  DISKS=$(printf '%s\n' "$LSBLK_RAW" \
    | awk '$2=="disk"{print $1}' | grep -Ev '^(loop|ram|zram|sr|zd[0-9])' || true)
  # lsblk returning nothing at all means the query failed. A host with zero
  # block devices is not a real case; an empty DISKS after a successful lsblk
  # (all devices filtered as zvols/loop) is, so only the raw form is checked.
  [ -z "$LSBLK_RAW" ] && warn '`lsblk` is installed but listed no block devices — the storage and SMART sections are empty as a result.'
fi

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
printf 'collector: hw-inventory.sh v5\n'
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
  if [ -z "$PROD" ] && [ -z "$MFR" ] && [ -z "$SERIAL" ] && [ -z "$BOARD" ]; then
    warn '`dmidecode` returned no system identity as root — manufacturer, model, service tag and motherboard are all unknown.'
  fi
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
  LC=$("${TMO[@]}" lscpu 2>/dev/null)
  [ -z "$LC" ] && warn '`lscpu` is installed but returned nothing — socket, core and thread counts are missing.'
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
  # Two passes, because a credential can hide in either half of a parameter.
  #
  # By NAME: rd.luks.key, rd.iscsi.password and friends — the name matches, so
  # the whole value goes. Covers dracut's LUKS keyfile spec via "key".
  #
  # By VALUE: dracut's iSCSI root packs CHAP secrets into the value itself,
  # where no name match can see them:
  #   netroot=iscsi:user:pass:rev_user:rev_pass@host:port:...:targetname
  # Everything between "iscsi:" and "@" is credential material and is replaced
  # wholesale — including the usernames, which are half of a CHAP pair rather
  # than merely identifying. Host, port, LUN and target name stay visible,
  # which is the part with inventory value. A target with no credentials has
  # no "@" and is left alone.
  #
  # This is still a filter, not a proof: it catches the forms known to appear
  # here, not every way a secret could be written on a kernel command line.
  awk '{
    out=""
    for (i=1;i<=NF;i++) {
      tok=$i; name=tok; sub(/=.*/,"",name)
      if (tok ~ /=/ && tolower(name) ~ /(password|secret|token|key)/) tok=name"=REDACTED"
      else if (tok ~ /iscsi:[^@]+@/) sub(/iscsi:[^@]+@/, "iscsi:REDACTED@", tok)
      out = (out=="") ? tok : out" "tok
    }
    print out
  }' /proc/cmdline 2>/dev/null
  printf '```\n\n'
fi

# ---------------------------------------------------------------- MEMORY ----
printf '### Memory\n\n| Field | Value |\n|---|---|\n'
have free && kv "Total RAM" "$RAMTOTAL"
have free && kv "Swap total" "$(free -h 2>/dev/null | awk '/^Swap:/{print $2}')"
DMIMEM=""
if is_root && have dmidecode; then
  # Captured once: the emptiness check below needs it, and the three parses
  # that follow previously re-ran dmidecode for each.
  DMIMEM=$("${TMO[@]}" dmidecode -t memory 2>/dev/null)
  SLOTS=$(printf '%s\n' "$DMIMEM" | grep -c '^Memory Device$')
  FILLED=$(printf '%s\n' "$DMIMEM" | awk '/^\tSize:/ && $2 != "No" {c++} END{print c+0}')
  # Keyed on the record count, not on DMIMEM being empty: a dmidecode that
  # cannot read /dev/mem still prints a banner to stdout, so an emptiness test
  # here would never fire on the failure it is meant to catch.
  [ "$SLOTS" -eq 0 ] && warn '`dmidecode -t memory` reported no memory devices as root — DIMM slot counts and the module table are missing.'
  kv "DIMM slots (filled / total)" "$FILLED / $SLOTS"
  MAXCAP=$("${TMO[@]}" dmidecode -t 16 2>/dev/null | awk -F: '/Maximum Capacity/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
  kv "Max supported" "${MAXCAP:-$NA}"
fi
echo

if is_root && have dmidecode; then
  MODLINES=$(printf '%s\n' "$DMIMEM" | awk '
    function emit() {
      if (size != "" && size !~ /^No/) printf "| %s | %s | %s | %s | %s |\n", loc, size, sp, mf, pn
    }
    /^Memory Device$/ {emit(); loc="";size="";sp="";pn="";mf=""}
    /^\tLocator:/ {sub(/^\tLocator:[ \t]*/,""); loc=$0}
    /^\tSize:/ {sub(/^\tSize:[ \t]*/,""); size=$0}
    /^\tSpeed:/ && sp=="" {sub(/^\tSpeed:[ \t]*/,""); sp=$0}
    /^\tManufacturer:/ {sub(/^\tManufacturer:[ \t]*/,""); mf=$0}
    /^\tPart Number:/ {sub(/^\tPart Number:[ \t]*/,""); pn=$0}
    END {emit()}
  ')
  if [ -n "$MODLINES" ]; then
    printf '#### Installed DIMMs\n\n| Slot | Size | Speed | Vendor | Part number |\n|---|---|---|---|---|\n%s\n\n' "$MODLINES"
  fi
fi

# ---------------------------------------------------------------- STORAGE ---
printf '### Storage — physical devices\n\n'
if have lsblk; then
  # -P (key="value") is used deliberately: plain columnar output collapses
  # empty MODEL/SERIAL fields and silently shifts every later column.
  fld() { printf '%s' "$2" | sed -n "s/.*[[:space:]]\{0,\}$1=\"\([^\"]*\)\".*/\1/p"; }
  # Captured rather than printed straight through: the row loop is a pipeline
  # body, so it cannot warn() from inside (G-002). Testing the captured rows
  # out here also keeps the header from being printed above nothing.
  DEVROWS=$("${TMO[@]}" lsblk -dn -P -o NAME,TYPE,SIZE,ROTA,TRAN,MODEL,SERIAL 2>/dev/null \
    | grep -Ev 'NAME="(loop|ram|zram|sr)[0-9]*"|NAME="zd[0-9][0-9]*"' \
    | grep -F 'TYPE="disk"' \
    | while IFS= read -r line; do
        name=$(fld NAME "$line");   [ -z "$name" ] && continue
        size=$(fld SIZE "$line");   rota=$(fld ROTA "$line")
        tran=$(fld TRAN "$line");   model=$(fld MODEL "$line")
        serial=$(fld SERIAL "$line")
        case "$rota" in 1) kind="HDD";; 0) kind="SSD/NVMe";; *) kind="$NA";; esac
        printf '| /dev/%s | %s | %s | %s | %s | %s |\n' \
          "$name" "${size:-$NA}" "${model:-$NA}" "${serial:-$NA}" "$kind" "${tran:-$NA}"
      done)
  if [ -n "$DEVROWS" ]; then
    printf '| Device | Size | Model | Serial | Type | Bus |\n|---|---|---|---|---|---|\n'
    printf '%s\n\n' "$DEVROWS"
  else
    printf '_No physical disks reported._\n\n'
    # Only when the plain listing worked — otherwise the probe near the top
    # already warned, and one broken lsblk should not report twice.
    if [ -n "$LSBLK_RAW" ]; then
      warn '`lsblk` listed block devices but none survived the physical-disk filter — the device table is empty.'
    fi
  fi
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
    # This is a plain for loop in the main shell, not a pipeline body, so the
    # counter survives — see the note on warn().
    SMOK=0; SMTOTAL=0
    for d in $DISKS; do
      SMTOTAL=$((SMTOTAL + 1))
      # -n standby: if the drive is spun down, report and move on rather than
      # waking it. Matters on a NAS with spun-down array disks.
      SM=$(tmo 15 smartctl -n standby -H -A -d auto "/dev/$d" 2>/dev/null || true)
      if printf '%s' "$SM" | grep -qi 'STANDBY mode'; then
        # A standby answer is a successful query — the drive was reached.
        SMOK=$((SMOK + 1))
        printf '| /dev/%s | (standby — not woken) | %s | %s | %s | %s |\n' "$d" "$NA" "$NA" "$NA" "$NA"
        continue
      fi
      [ -z "$SM" ] && { printf '| /dev/%s | %s | %s | %s | %s | %s |\n' "$d" "(no data)" "$NA" "$NA" "$NA" "$NA"; continue; }
      SMOK=$((SMOK + 1))

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
    if [ "$SMOK" -eq 0 ]; then
      warn "\`smartctl\` answered for none of the $SMTOTAL disk(s) as root — every health row is empty. Drives behind a RAID controller are expected here; a plain SATA/NVMe host is not."
    fi
    echo
    if tmo 15 smartctl --scan 2>/dev/null | grep -q .; then
      printf '**`smartctl --scan` sees:**\n\n```\n'
      tmo 15 smartctl --scan 2>/dev/null | cap "$SMART_SCAN_LINES" "scan lines"
      printf '```\n\n'
    fi
    printf '_Drives behind a hardware RAID controller do not appear above — see the RAID controller section._\n\n'
  fi
fi

# ------------------------------------------------------------ RAID CTRL ----
# Hardware RAID (Dell PERC, LSI/Broadcom MegaRAID, HP Smart Array).
# Vendor CLIs are invoked with `show` verbs only. Never add/delete/set/start.
RAIDCTL=""
LSPCI_RAW=""
if have lspci; then
  LSPCI_RAW=$("${TMO[@]}" lspci 2>/dev/null || true)
  # No RAID controller in the list is normal. An empty list is not: it means
  # the PCI bus was never enumerated, so "no controller found" below would be
  # an assertion this host has none, which is exactly the wrong answer.
  [ -z "$LSPCI_RAW" ] && warn '`lspci` is installed but enumerated no PCI devices — the RAID controller and PCI sections cannot be trusted as "none present".'
  RAIDCTL=$(printf '%s\n' "$LSPCI_RAW" | grep -iE 'MegaRAID|PERC|LSI.*RAID|Smart Array|cciss|RAID bus controller' | cap "$RAID_CTRL_LINES" "RAID controller matches")
fi

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
    tmo 25 "$RCLI" /call show 2>/dev/null | cap "$RAID_CLI_SUMMARY_LINES" "controller summary lines"
    echo
    echo "--- virtual drives ---"
    tmo 25 "$RCLI" /call/vall show 2>/dev/null | cap "$RAID_CLI_SUMMARY_LINES" "virtual drive lines"
    echo
    echo "--- physical drives ---"
    tmo 25 "$RCLI" /call/eall/sall show 2>/dev/null | cap "$RAID_CLI_DRIVES_LINES" "physical drive lines"
    printf '```\n\n'
  elif have megacli || have MegaCli64; then
    MCLI=$(command -v megacli 2>/dev/null || command -v MegaCli64 2>/dev/null)
    printf '#### Controller and array topology (MegaCLI)\n\n```\n'
    tmo 25 "$MCLI" -LDInfo -Lall -aALL -NoLog 2>/dev/null | cap "$MEGACLI_LD_LINES" "logical drive lines"
    echo
    echo "--- physical drives ---"
    tmo 25 "$MCLI" -PDList -aALL -NoLog 2>/dev/null \
      | grep -E 'Slot Number|Inquiry Data|Raw Size|Firmware state|Media Error|Other Error|Predictive|Drive Temperature' \
      | cap "$MEGACLI_PD_LINES" "physical drive lines"
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
        MS=$(tmo 6 smartctl -n standby -H -A -d "megaraid,$n" "/dev/$MRTGT" 2>/dev/null || true)
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
    else
      # disks.ini exists and was readable, so this is an Unraid host whose
      # array slots did not parse — not a machine that simply has no array.
      warn 'Unraid disks.ini is readable but no array slots parsed — the array slot table is empty.'
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
  DFOUT=$("${TMO[@]}" df -hT 2>/dev/null | grep -Ev '^(tmpfs|devtmpfs|efivarfs|overlay|none)' | cap "$FS_TABLE_LINES" "filesystem table lines")
  printf '%s\n' "$DFOUT"
  [ -z "$DFOUT" ] && warn '`df` is installed but reported no real filesystems.'
fi
if have findmnt; then
  echo
  echo "--- findmnt (mount options) ---"
  FMOUT=$("${TMO[@]}" findmnt --real -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null | cap "$FS_TABLE_LINES" "filesystem table lines")
  printf '%s\n' "$FMOUT"
  [ -z "$FMOUT" ] && warn '`findmnt` is installed but listed no mounted filesystems.'
fi
# No warning for zpool or btrfs, deliberately. Unlike df/findmnt/lsblk, which
# describe facts every host has, these describe optional subsystems: zfsutils
# and btrfs-progs are routinely installed as dependencies on hosts that use
# neither, where an empty listing is the correct answer rather than a failure.
# Warning here would fire on ordinary ext4 machines and train readers to skip
# the section. Do not add one.
if have zpool; then
  echo
  echo "--- zpool list ---"
  tmo 20 zpool list 2>/dev/null
  echo "--- zpool status -x ---"
  tmo 20 zpool status -x 2>/dev/null
fi
if have btrfs; then
  echo
  echo "--- btrfs filesystem show ---"
  "${TMO[@]}" btrfs filesystem show 2>/dev/null | cap "$FS_BTRFS_LINES" "btrfs filesystem lines"
fi
if have pvesm; then
  echo
  echo "--- pvesm status ---"
  PVSOUT=$("${TMO[@]}" pvesm status 2>/dev/null)
  printf '%s\n' "$PVSOUT"
  if is_root && [ -z "$PVSOUT" ]; then
    warn '`pvesm` is installed but reported no storage as root — the Proxmox storage list is missing.'
  fi
fi
printf '```\n\n'

# ---------------------------------------------------------------- NETWORK ---
printf '### Network interfaces\n\n'
if ! have ip; then
  printf '`ip` (iproute2) not available — record interfaces manually.\n\n'
else
  # Captured for the same reason as the storage table: the row loop is a
  # pipeline body and cannot warn() from inside it.
  IFROWS=$("${TMO[@]}" ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//' | while read -r ifc; do
    [ "$ifc" = "lo" ] && continue
    state=$(cat "/sys/class/net/$ifc/operstate" 2>/dev/null || echo "$NA")
    mac=$(cat "/sys/class/net/$ifc/address" 2>/dev/null || echo "$NA")
    addrs=$("${TMO[@]}" ip -o -4 addr show dev "$ifc" 2>/dev/null | awk '{print $4}' | paste -sd', ' -)
    [ -z "$addrs" ] && addrs="$NA"
    spd=$(cat "/sys/class/net/$ifc/speed" 2>/dev/null)
    if [ -n "$spd" ] && [ "$spd" -gt 0 ] 2>/dev/null; then spd="${spd} Mb/s"; else spd="$NA"; fi
    printf '| %s | %s | %s | %s | %s |\n' "$ifc" "$state" "$mac" "$addrs" "$spd"
  done)
  if [ -n "$IFROWS" ]; then
    printf '| Interface | State | MAC | Addresses | Link speed |\n|---|---|---|---|---|\n'
    printf '%s\n' "$IFROWS"
  else
    printf '_No interfaces other than loopback reported._\n'
    warn '`ip` is installed but listed no non-loopback interfaces — the network table is empty.'
  fi
  echo
  DEFRT=$("${TMO[@]}" ip route show default 2>/dev/null | head -1)
  [ -n "$DEFRT" ] && printf 'Default route: `%s`\n\n' "$DEFRT"
  if [ -r /etc/resolv.conf ]; then
    printf 'Resolvers: `%s`\n\n' "$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd', ' -)"
  fi
fi

# ---------------------------------------------------------------- PCI -------
# -nn gives vendor:device IDs, -k gives the bound driver. Both matter more
# than the human-readable name when diagnosing a driver problem.
if have lspci; then
  # The raw listing and the filtered one are separate variables on purpose. The
  # filter selects a handful of device classes, so a host can legitimately match
  # none of them — a VM whose NIC and disks are paravirtual (VMBus, virtio) has
  # a full PCI list with nothing interesting in it. Warning on the *filtered*
  # emptiness called that host broken, which is the over-warning half of the
  # exit-code contract: it made CI red on every run this workflow ever made,
  # blaming lspci for hardware the runner genuinely does not have.
  PCIRAW=$("${TMO[@]}" lspci -nnk 2>/dev/null || true)
  PCIOUT=$(printf '%s\n' "$PCIRAW" | awk '
    /^[0-9a-f][0-9a-f]:/ { keep = (tolower($0) ~ /vga|3d controller|display|ethernet|network|raid|sata|non-volatile|serial attached/) }
    keep
  ' | cap "$PCI_DEVICE_LINES" "PCI device lines")
  # Printed only when non-empty, like every other section: an empty code fence
  # is a section announcing its shape and collecting nothing.
  [ -n "$PCIOUT" ] && printf '### Notable PCI devices\n\n```\n%s\n```\n\n' "$PCIOUT"
  # Only warn when plain lspci worked — otherwise the probe above already did,
  # and one broken tool should not produce two warnings.
  if [ -n "$LSPCI_RAW" ] && [ -z "$PCIRAW" ]; then
    warn '`lspci -nnk` returned nothing although plain `lspci` worked — the PCI device list with bound drivers is missing.'
  fi
fi

# ------------------------------------------------------------- DISPLAYS ----
# The one category of attached hardware this script could not otherwise see.
# EDID comes straight out of sysfs, which is a plain file read: it works
# headless and over SSH, where `xrandr` needs a session.
#
# `ddcutil` is deliberately not used and must not be added. DDC/CI is a
# bidirectional protocol over i2c-dev — "querying" a monitor that way writes to
# it, so it is a write by any reading of the rule. `edid-decode` and `strings`
# are pure parsers of bytes handed to them on stdin: no config file, so nothing
# on the host can turn either into an execution (the FR-003 lesson).
#
# Never warns, on purpose. A host with no connected display is not a broken
# host and an LXC has no /sys/class/drm at all, so absence is the normal case —
# same call as zpool/btrfs, and for the same reason.
MONROWS=""
for e in /sys/class/drm/card*-*/edid; do
  [ -r "$e" ] || continue
  conn=${e%/edid}; conn=${conn##*/}
  # Writeback connectors are virtual encoders, not physical outputs — the same
  # class of false row as the zvols a TYPE=="disk" filter alone misses (C-012).
  case "$conn" in *-Writeback-*) continue;; esac
  # Gate on bytes actually READ, not on file size: every edid attribute stats
  # as 0 bytes, including the connectors that return a full 256. This is the
  # dmidecode-banner trap again — test the thing that indicates the fact.
  n=$(wc -c 2>/dev/null < "$e")
  [ "${n:-0}" -gt 0 ] || continue
  disp=""
  if have edid-decode; then
    disp=$("${TMO[@]}" edid-decode 2>/dev/null < "$e" | awk -F': ' '
      /^[[:space:]]*Manufacturer:/                 && v=="" {v=$2}
      /^[[:space:]]*Display Product Name:/         && m=="" {m=$2}
      /^[[:space:]]*Display Product Serial Number:/&& s=="" {s=$2}
      END {
        gsub(/\047/,"",m); gsub(/\047/,"",s)
        out = v
        if (m != "") out = out " " m
        if (s != "") out = out " (s/n " s ")"
        print out
      }')
  elif have strings; then
    # Without a parser the descriptor bytes are unlabelled, so the model and
    # the serial cannot be told apart — both are still recovered, which is
    # enough for inventory. The filter drops timing-block bytes that happen to
    # be printable ("UP0 5" and friends).
    disp=$(strings -n 4 2>/dev/null < "$e" \
      | grep -E '^[[:alnum:]][[:alnum:] ._+/-]{5,}$' | paste -sd' ' -)
  fi
  # Worded for both empty cases: no parser installed, and a parser that ran and
  # gave nothing back. The row is still emitted either way — a connector
  # handing over 128 bytes of EDID is an attached display whether or not
  # anything on this host could read it.
  MONROWS="${MONROWS}| ${conn} | ${disp:-(EDID present, not parsed)} |
"
done
if [ -n "$MONROWS" ]; then
  printf '### Displays\n\n| Connector | Display |\n|---|---|\n%s\n' "$MONROWS"
  have edid-decode || printf '_`edid-decode` is not installed — the Display column is raw EDID text, so the model and the serial are not separated._\n\n'
fi

# ------------------------------------------------------------------ UPS -----
# Whether this host can actually talk to its UPS, which is otherwise knowable
# only by asking someone.
#
# The primary signal is a direct sysfs read of each USB device's idVendor, not
# `lsusb` — the data is already in a file, so read the file, the same move as
# parsing emhttp's .ini instead of calling `mdcmd`. `lsusb -v` in particular is
# out: it issues USB control transfers to the device instead of reading the
# descriptors the kernel has already cached.
#
# /sys/class/power_supply is NOT the gate. Verified empty on a host with a
# CyberPower UPS attached and claimed by usbhid; it is corroboration where it
# is populated and useless as the test.
#
# Never warns, and prints nothing at all when nothing is found. Most hosts have
# no UPS, so absence of the section is the negative answer, exactly as it is
# for every other category of hardware here.
UPSROWS=""
# A whitelist of USB vendor IDs, not a protocol, and it WILL go stale: APC and
# CyberPower are simply the two brands seen so far. Adding a third brand's ID
# here is the intended maintenance, not a workaround.
UPS_VENDORS="051d 0764"   # APC, CyberPower
for f in /sys/bus/usb/devices/*/idVendor; do
  [ -r "$f" ] || continue
  vid=$(cat "$f" 2>/dev/null)
  case " $UPS_VENDORS " in *" $vid "*) ;; *) continue;; esac
  dev=${f%/idVendor}
  # A bound interface driver is the evidence that the host can talk to it at
  # all, as opposed to a device sitting on the bus that nothing has claimed.
  drv=""
  for i in "$dev"/*:*/driver; do
    [ -e "$i" ] || continue
    drv=$(readlink "$i" 2>/dev/null)
    [ -n "$drv" ] && drv=", driver ${drv##*/}"
    break
  done
  UPSROWS="${UPSROWS}$(kv "USB device" \
    "$(cat "$dev/manufacturer" 2>/dev/null) $(cat "$dev/product" 2>/dev/null) ($vid:$(cat "$dev/idProduct" 2>/dev/null)$drv)")
"
done
# Corroboration only — see the gate note above.
PSUP=$(grep -lx UPS /sys/class/power_supply/*/type 2>/dev/null | sed 's#.*/\([^/]*\)/type$#\1#' | paste -sd', ' -)
[ -n "$PSUP" ] && UPSROWS="${UPSROWS}$(kv "Kernel power_supply" "$PSUP")
"
# The configured intent, which is readable whether or not apcupsd is running —
# detection must not depend on a daemon answering. Keys are whitelisted rather
# than dumped, as everywhere else config files are read here.
if [ -r /etc/apcupsd/apcupsd.conf ]; then
  APCCFG=$(awk '$1=="UPSCABLE"||$1=="UPSTYPE"||$1=="DEVICE"{printf "%s%s=%s", sep, $1, $2; sep=", "}' \
    /etc/apcupsd/apcupsd.conf 2>/dev/null)
  [ -n "$APCCFG" ] && UPSROWS="${UPSROWS}$(kv "apcupsd config" "$APCCFG")
"
fi
# `apcaccess status` is a query to apcupsd's NIS port. Load percentage and
# battery age are out of scope; MODEL and STATUS are the two fields that answer
# "is the data link up".
if have apcaccess; then
  APCS=$(tmo 10 apcaccess status 2>/dev/null \
    | awk '/^(MODEL|STATUS)[[:space:]]*:/{sub(/[[:space:]]*:[[:space:]]*/,": "); sub(/[[:space:]]+$/,""); print}' \
    | paste -sd'; ' -)
  [ -n "$APCS" ] && UPSROWS="${UPSROWS}$(kv "apcaccess" "$APCS")
"
fi
# A third signal, and a read. Yields little on a headless host with no session.
if have upower; then
  UPWR=$("${TMO[@]}" upower -e 2>/dev/null | grep -i 'ups' | paste -sd', ' -)
  [ -n "$UPWR" ] && UPSROWS="${UPSROWS}$(kv "UPower" "$UPWR")
"
fi
if [ -n "$UPSROWS" ]; then
  printf '### UPS\n\n| Signal | Value |\n|---|---|\n%s\n' "$UPSROWS"
fi

# ------------------------------------------------------------ BMC / IPMI ---
# Local baseboard controller (iDRAC, iLO, generic IPMI). Read-only verbs only:
# info, print, list, sdr. Never `chassis power`, never `sel clear`, never
# `mc reset`. If the ipmi kernel modules are not loaded there is no device
# node and this section skips — the script does not modprobe, that is a change.
if have ipmitool && is_root && { [ -e /dev/ipmi0 ] || [ -e /dev/ipmi/0 ] || [ -e /dev/ipmidev/0 ]; }; then
  printf '### BMC / IPMI (iDRAC, iLO)\n\n'

  MCINFO=$(tmo 15 ipmitool mc info 2>/dev/null \
    | grep -E 'Manufacturer Name|Product Name|Firmware Revision|IPMI Version' | cap "$IPMI_IDENTITY_LINES" "BMC identity lines")
  # The gate above already confirmed root and a live IPMI device node, so a
  # BMC that will not identify itself is a real failure, not absent hardware.
  if [ -n "$MCINFO" ]; then
    printf '```\n%s\n```\n\n' "$MCINFO"
  else
    warn '`ipmitool mc info` returned nothing although an IPMI device node is present — BMC details are missing.'
  fi

  # Community strings and auth settings are filtered out deliberately.
  LANINFO=$(tmo 15 ipmitool lan print 1 2>/dev/null \
    | grep -viE 'community|password|cipher|auth type' \
    | grep -E 'IP Address|Subnet Mask|MAC Address|Default Gateway' | cap "$IPMI_LAN_LINES" "BMC network lines")
  [ -n "$LANINFO" ] && printf '**BMC network**\n\n```\n%s\n```\n\n' "$LANINFO"

  SENS=$(tmo 30 ipmitool sdr elist 2>/dev/null | grep -viE '\| ns \|' | cap "$IPMI_SENSOR_LINES" "sensor lines")
  [ -n "$SENS" ] && printf '**Sensors**\n\n```\n%s\n```\n\n' "$SENS"

  SEL=$(tmo 25 ipmitool sel list 2>/dev/null | tail -15)
  [ -n "$SEL" ] && printf '**System event log (last 15 entries)**\n\n```\n%s\n```\n\n' "$SEL"
elif have ipmitool && is_root; then
  printf '### BMC / IPMI\n\n'
  printf '_`ipmitool` present but no IPMI device node. The `ipmi_si` and `ipmi_devintf` modules are not loaded; this script will not load them. Load them yourself if you want BMC data here._\n\n'
fi

if have racadm && is_root; then
  RAC=$(tmo 20 racadm getsysinfo 2>/dev/null \
    | grep -viE 'password|community' | cap "$RACADM_LINES" "racadm lines")
  if [ -n "$RAC" ]; then
    printf '### racadm getsysinfo\n\n```\n%s\n```\n\n' "$RAC"
  fi
fi

# ---------------------------------------------------------------- PROXMOX ---
if have pveversion || have pct || have qm; then
  printf '### Proxmox\n\n'

  if have pveversion; then
    PVEV=$(tmo 15 pveversion -v 2>/dev/null | cap "$PVE_VERSIONS_LINES" "package version lines")
    if [ -n "$PVEV" ]; then
      printf '#### Package versions\n\n```\n%s\n```\n\n' "$PVEV"
    else
      warn '`pveversion -v` returned nothing on a host that has it installed — Proxmox package versions are missing.'
    fi
  fi

  # Reads the config text held in $CFG by the loops below.
  cfgget() { printf '%s\n' "$CFG" | awk -F': ' -v k="$1" '$1==k{sub(/^[^:]*: /,""); print; exit}'; }

  # ---- LXC containers ----
  if have pct; then
    # A host with zero containers still prints a header line, so an entirely
    # empty result means the command failed rather than "no containers".
    # Warned only as root, since pct needs root to talk to the cluster fs.
    PCTRAW=$(tmo 20 pct list 2>/dev/null)
    if is_root && [ -z "$PCTRAW" ]; then
      warn '`pct list` returned nothing as root — LXC containers could not be enumerated and are absent from the report.'
    fi
    CTIDS=$(printf '%s\n' "$PCTRAW" | awk 'NR>1{print $1}')
    CTROWS=""
    for id in $CTIDS; do
      CFG=$(tmo 10 pct config "$id" 2>/dev/null || true)
      [ -z "$CFG" ] && continue
      st=$(tmo 10 pct status "$id" 2>/dev/null | awk '{print $2}')
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
    QMRAW=$(tmo 20 qm list 2>/dev/null)
    if is_root && [ -z "$QMRAW" ]; then
      warn '`qm list` returned nothing as root — QEMU VMs could not be enumerated and are absent from the report.'
    fi
    VMIDS=$(printf '%s\n' "$QMRAW" | awk 'NR>1{print $1}')
    VMROWS=""
    for id in $VMIDS; do
      CFG=$(tmo 10 qm config "$id" 2>/dev/null || true)
      [ -z "$CFG" ] && continue
      vst=$(tmo 10 qm status "$id" 2>/dev/null | awk '{print $2}')
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

  # No warning here on purpose: `pvecm status` fails on a standalone node that
  # was never joined to a cluster, which is a normal Proxmox install, not a
  # collection failure. Do not "fix" this by adding one.
  if have pvecm; then
    CLU=$(tmo 15 pvecm status 2>/dev/null | cap "$PVE_CLUSTER_LINES" "cluster status lines")
    [ -n "$CLU" ] && printf '#### Cluster\n\n```\n%s\n```\n\n' "$CLU"
  fi
fi

# ---------------------------------------------------------------- DOCKER ----
# `docker info` failing is the gate, not a warning: an installed docker with a
# stopped daemon, or a user outside the docker group, is a legitimate state and
# the section is skipped. Past the gate the daemon answered, so a collector
# that then returns nothing has failed.
if have docker && "${TMO[@]}" docker info >/dev/null 2>&1; then
  printf '### Docker\n\n```\n'
  DVER=$("${TMO[@]}" docker version --format 'Docker {{.Server.Version}}' 2>/dev/null)
  printf '%s\n' "$DVER"
  [ -z "$DVER" ] && warn '`docker version` returned nothing although the daemon answered `docker info`.'
  echo
  "${TMO[@]}" docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | cap "$DOCKER_LIST_LIMIT" "container lines"
  printf '```\n\n'
  # Network + container IP for every container in one call. docker inspect
  # is read-only; container names are whitespace-free by construction, same
  # as the device/VMID lists elsewhere in this script.
  #
  # Deliberately NOT run through cap(): CNAMES is word-split into docker
  # inspect's argument list below, so cap()'s trailing "--- truncated ---"
  # marker would be passed as a bogus container name and either error out or
  # silently desync the NF==2 parsing that follows. The full (uncapped) list
  # is read first instead — docker ps terminates on its own regardless of how
  # much of it we read, unlike the SIGPIPE-sensitive scans elsewhere in this
  # file, so there is no early-close reason to cap the read itself — and the
  # truncation marker for this one site is deferred to after the container
  # networks table, where it can no longer land inside anyone's argument list.
  CNAMES_ALL=$("${TMO[@]}" docker ps -a --format '{{.Names}}' 2>/dev/null)
  CNAMES=$(printf '%s\n' "$CNAMES_ALL" | head -n "$DOCKER_LIST_LIMIT")
  CNAMES_TRUNCATED=0
  if [ -n "$CNAMES_ALL" ]; then
    CNAMES_TOTAL=$(printf '%s\n' "$CNAMES_ALL" | wc -l)
    [ "$CNAMES_TOTAL" -gt "$DOCKER_LIST_LIMIT" ] && CNAMES_TRUNCATED=1
  fi
  # Initialised before the guard because the emptiness test below sits outside
  # it: a daemon that answers `docker info` with zero containers is a healthy
  # state, but it leaves CNAMES empty, and an unset DNET then aborts the whole
  # script under `set -u` — truncating the report mid-section with no footer
  # and no `## Collection warnings` block, while still exiting 1 as though the
  # contract had been honoured. Same reason DMIMEM is initialised before its
  # own root gate. T12 covers it.
  DNET=""
  if [ -n "$CNAMES" ]; then
    # shellcheck disable=SC2086
    DNET=$(tmo 15 docker inspect -f '{{.Name}}|{{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{if $v.IPAddress}}{{$v.IPAddress}}{{else}}—{{end}} {{end}}' $CNAMES 2>/dev/null \
      | sed 's#^/##' \
      | awk -F'|' 'NF==2 && $2!=""{printf "| %s | %s |\n", $1, $2}')
  fi
  if [ -n "$DNET" ]; then
    printf '#### Container networks\n\n| Container | Network=IP |\n|---|---|\n%s\n\n' "$DNET"
  fi
  if [ "$CNAMES_TRUNCATED" -eq 1 ]; then
    printf '_(container network lookups capped at %d containers; later containers are not shown above)_\n\n' "$DOCKER_LIST_LIMIT"
  fi
fi

# ---------------------------------------------------------------- SERVICES --
# An empty `--failed` list is the healthy case, never a warning.
if have systemctl; then
  FAILED=$("${TMO[@]}" systemctl --failed --no-legend --no-pager 2>/dev/null | cap "$SYSTEMD_FAILED_LINES" "failed unit lines")
  printf '### Failed systemd units\n\n'
  if [ -n "$FAILED" ]; then
    printf '```\n%s\n```\n\n' "$FAILED"
  else
    printf 'None.\n\n'
  fi
fi

# ------------------------------------------------------------- WARNINGS -----
# Printed before the footer so the footer stays the last line of the report.
if [ "$WARNCOUNT" -gt 0 ]; then
  printf '## Collection warnings\n\n'
  printf 'A collector that was present and permitted returned nothing. Treat the\n'
  printf 'sections named below as **unknown**, not as "this host has none":\n\n'
  printf '%s\n' "$WARNINGS"
  printf '_%d collector(s) affected. The script exits 1 when this section is present._\n\n' "$WARNCOUNT"
fi

printf -- '---\n*End of report for %s.*\n' "$HOST"

# Exit non-zero so a caller that only checks $? still learns the report is
# incomplete. The report itself is always written in full first.
[ "$WARNCOUNT" -eq 0 ] || exit 1
exit 0
