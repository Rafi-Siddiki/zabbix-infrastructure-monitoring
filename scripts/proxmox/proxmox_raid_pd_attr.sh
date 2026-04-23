#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?discover|type|health|wear|wearpct|dynamic|vddiscover|vdstate.raw|vdstate|vddynamic|pdstate.raw|pdstate|pddynamic}"
BASEDEV="${2:-/dev/sda}"
DID="${3:-}"
MAX_PD="${MAX_PD:-31}"

smart_probe() {
    local did="$1"
    {
        smartctl -x -d megaraid,"$did" "$BASEDEV" 2>/dev/null || \
        smartctl -a -d megaraid,"$did" "$BASEDEV" 2>/dev/null || true
        smartctl -l ssd -d megaraid,"$did" "$BASEDEV" 2>/dev/null || true
    }
}

json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])'
}

normalize_pct() {
    local v="${1:-}"
    v="$(printf '%s' "$v" | tr -cd '0-9')"
    [ -n "$v" ] || return 1
    v=$((10#$v))
    [ "$v" -lt 0 ] && v=0
    [ "$v" -gt 100 ] && v=100
    printf '%s\n' "$v"
}

get_name() {
    awk -F: '
        /Device Model:|Model Number:|Product:/ {
            gsub(/^[ \t]+/, "", $2)
            print $2
            exit
        }'
}

get_serial() {
    awk -F: '
        /Serial Number:/ {
            gsub(/^[ \t]+/, "", $2)
            print $2
            exit
        }'
}

get_type() {
    if grep -qiE 'Rotation Rate:[[:space:]]*Solid State Device|Wear_Leveling_Count|Media_Wearout_Indicator|Percentage Used:|Percentage Used Endurance Indicator|Solid State Device Statistics'; then
        echo "SSD"
    else
        echo "HDD"
    fi
}

get_health_raw() {
    awk -F: '
        /SMART overall-health self-assessment test result:/ {
            gsub(/^[ \t]+/, "", $2); print $2; found=1; exit
        }
        /SMART Health Status:/ {
            gsub(/^[ \t]+/, "", $2); print $2; found=1; exit
        }
        END { if (!found) print "" }'
}

get_used_pct() {
    awk '
        /^[[:space:]]*0x07[[:space:]]+0x008[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+.*Percentage Used Endurance Indicator/ {
            print $4; found=1; exit
        }
        /Percentage Used Endurance Indicator/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9]+$/) {
                    print $i; found=1; exit
                }
            }
        }
        /Percentage Used:/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9]+%?$/) {
                    gsub(/%/, "", $i)
                    print $i; found=1; exit
                }
            }
        }
        END { if (!found) print "" }'
}

get_life_left_attr_pct() {
    awk '
        /^[[:space:]]*233[[:space:]]+Media_Wearout_Indicator([[:space:]]|$)/ {
            print $4; found=1; exit
        }
        /^[[:space:]]*231[[:space:]]+(SSD_Life_Left|Life_Left|SSD_Life_Left_Indicator)([[:space:]]|$)/ {
            print $4; found=1; exit
        }
        /^[[:space:]]*202[[:space:]]+(Percent_Lifetime_Remain|Percentage_Lifetime_Remain)([[:space:]]|$)/ {
            print $4; found=1; exit
        }
        /^[[:space:]]*177[[:space:]]+Wear_Leveling_Count([[:space:]]|$)/ {
            print $4; found=1; exit
        }
        END { if (!found) print "" }'
}

get_wear_pct() {
    local out="${1:-}"
    local used=""
    local left=""

    used="$(printf '%s\n' "$out" | get_used_pct || true)"
    if [ -n "$used" ]; then
        used="$(normalize_pct "$used" 2>/dev/null || true)"
        if [ -n "$used" ]; then
            printf '%s\n' "$((100 - used))"
            return 0
        fi
    fi

    left="$(printf '%s\n' "$out" | get_life_left_attr_pct || true)"
    if [ -n "$left" ]; then
        left="$(normalize_pct "$left" 2>/dev/null || true)"
        if [ -n "$left" ]; then
            printf '%s\n' "$left"
            return 0
        fi
    fi

    printf '\n'
}

get_dynamic_status() {
    local out="$1"
    if [ -z "$out" ]; then echo 0; return; fi

    local dtype health pct
    dtype="$(printf '%s\n' "$out" | get_type)"

    if [ "$dtype" = "SSD" ]; then
        pct="$(get_wear_pct "$out")"
        if [ -z "$pct" ]; then echo 0; return; fi
        pct=$((10#$pct))

        if [ "$pct" -lt 30 ]; then echo 5; return; fi
        if [ "$pct" -lt 40 ]; then echo 3; return; fi
        echo 1; return
    fi

    health="$(printf '%s\n' "$out" | get_health_raw | tr '[:upper:]' '[:lower:]')"
    case "$health" in
        passed|ok|normal ) echo 1 ;;
        *degrad*|*warn*|*pre-fail*|*prefail*|*suspect* ) echo 3 ;;
        * ) echo 5 ;;
    esac
}

find_raid_cli() {
    local c
    for c in \
        /opt/MegaRAID/storcli/storcli64 \
        /opt/MegaRAID/perccli/perccli64 \
        /opt/MegaRAID/storcli/storcli \
        /opt/MegaRAID/perccli/perccli \
        /usr/local/bin/storcli64 \
        /usr/local/bin/perccli64 \
        /usr/local/bin/storcli \
        /usr/local/bin/perccli \
        storcli64 storcli perccli64 perccli
    do
        if [ -x "$c" ]; then
            echo "$c"
            return 0
        fi
        if command -v "$c" >/dev/null 2>&1; then
            command -v "$c"
            return 0
        fi
    done
    return 1
}

raid_cli_show_vall() {
    local cli
    cli="$(find_raid_cli)" || return 1

    "$cli" /c0 /vall show J 2>/dev/null || \
    "$cli" /call /vall show J 2>/dev/null || \
    "$cli" /c0 /vall show 2>/dev/null || \
    "$cli" /call /vall show 2>/dev/null || true
}

raid_cli_show_vall_all() {
    local cli
    cli="$(find_raid_cli)" || return 1

    "$cli" /c0 /vall show all J 2>/dev/null || \
    "$cli" /call /vall show all J 2>/dev/null || \
    "$cli" /c0 /vall show all 2>/dev/null || \
    "$cli" /call /vall show all 2>/dev/null || true
}

vd_discover() {
    local out
    out="$(raid_cli_show_vall)"
    [ -n "$out" ] || { printf '[]\n'; return; }

    if printf '%s\n' "$out" | grep -q '"Controllers"'; then
        printf '%s\n' "$out" | python3 -c '
import sys, json
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    print("[]")
    raise SystemExit

items = []
for ctl in data.get("Controllers", []):
    resp = ctl.get("Response Data", {})
    vds = resp.get("Virtual Drives", [])
    if isinstance(vds, list):
        for row in vds:
            if not isinstance(row, dict):
                continue
            dgvd = str(row.get("DG/VD", "")).strip()
            state = str(row.get("State", "")).strip()
            typ = str(row.get("TYPE", row.get("Type", ""))).strip()
            name = str(row.get("Name", "")).strip()
            if dgvd:
                items.append({
                    "{#VDID}": dgvd,
                    "{#VDNAME}": name if name else dgvd,
                    "{#VDTYPE}": typ,
                    "{#VDSTATE}": state
                })

seen = set()
final = []
for item in items:
    key = item["{#VDID}"]
    if key in seen:
        continue
    seen.add(key)
    final.append(item)

print(json.dumps(final, separators=(",", ":")))
'
        return
    fi

    awk '
        BEGIN { first=1; printf "[" }
        /^[0-9]+\/[0-9]+[[:space:]]+/ {
            dgvd=$1
            type=$2
            state=$3
            name=""
            if (NF >= 10) {
                for (i=10; i<=NF; i++) {
                    name = name (name=="" ? "" : " ") $i
                }
            }
            if (name=="") name=dgvd
            gsub(/"/, "\\\"", name)
            gsub(/"/, "\\\"", type)
            gsub(/"/, "\\\"", state)

            if (!first) printf ","
            first=0
            printf "{\"{#VDID}\":\"%s\",\"{#VDNAME}\":\"%s\",\"{#VDTYPE}\":\"%s\",\"{#VDSTATE}\":\"%s\"}", dgvd, name, type, state
        }
        END { printf "]\n" }' <<<"$out"
}

get_vd_state_raw() {
    local want="$1"
    local out
    out="$(raid_cli_show_vall)"
    [ -n "$out" ] || { printf '\n'; return; }

    if printf '%s\n' "$out" | grep -q '"Controllers"'; then
        printf '%s\n' "$out" | python3 -c '
import sys, json
want = sys.argv[1]
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    print("")
    raise SystemExit

for ctl in data.get("Controllers", []):
    resp = ctl.get("Response Data", {})
    vds = resp.get("Virtual Drives", [])
    if isinstance(vds, list):
        for row in vds:
            if isinstance(row, dict) and str(row.get("DG/VD", "")).strip() == want:
                print(str(row.get("State", "")).strip())
                raise SystemExit
print("")
' "$want"
        return
    fi

    awk -v want="$want" '
        /^[0-9]+\/[0-9]+[[:space:]]+/ {
            if ($1 == want) { print $3; found=1; exit }
        }
        END { if (!found) print "" }' <<<"$out"
}

normalize_vd_state() {
    local s="${1:-}"
    case "$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')" in
        optl|optimal ) echo "optimal" ;;
        dgrd|degraded|pdgd|partiallydegraded ) echo "degraded" ;;
        rbld|rebuild|rebuilding ) echo "rebuilding" ;;
        fail|failed|offln|offline|missing ) echo "failed" ;;
        * ) echo "$s" ;;
    esac
}

get_vd_dynamic() {
    local raw norm
    raw="$(get_vd_state_raw "$1")"
    norm="$(normalize_vd_state "$raw")"

    case "$norm" in
        optimal ) echo 1 ;;
        degraded|rebuilding ) echo 3 ;;
        failed ) echo 5 ;;
        * ) echo 0 ;;
    esac
}

get_pd_state_raw() {
    local want="$1"
    local out
    out="$(raid_cli_show_vall_all)"
    [ -n "$out" ] || { printf '\n'; return; }

    if printf '%s\n' "$out" | grep -q '"Controllers"'; then
        printf '%s\n' "$out" | python3 -c '
import sys, json
want = str(sys.argv[1]).strip()
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    print("")
    raise SystemExit

for ctl in data.get("Controllers", []):
    resp = ctl.get("Response Data", {})
    for k, v in resp.items():
        if not isinstance(v, list):
            continue
        if not str(k).startswith("PDs for VD"):
            continue
        for row in v:
            if not isinstance(row, dict):
                continue
            did = str(row.get("DID", "")).strip()
            if did == want:
                print(str(row.get("State", "")).strip())
                raise SystemExit
print("")
' "$want"
        return
    fi

    awk -v want="$want" '
        $0 ~ /^[[:space:]]*[0-9]+:[0-9]+[[:space:]]+[0-9]+[[:space:]]+/ {
            did=$2
            state=$3
            if (did == want) { print state; found=1; exit }
        }
        END { if (!found) print "" }' <<<"$out"
}

normalize_pd_state() {
    local s="${1:-}"
    case "$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')" in
        onln|online ) echo "online" ;;
        ugood|jbod|good|unconfiguredgood ) echo "good" ;;
        ghs|dhs|spare|hotspare ) echo "spare" ;;
        rbld|rebuild|rebuilding ) echo "rebuilding" ;;
        offln|offline|failed|fail|ubad|bad|missing ) echo "failed" ;;
        * ) echo "$s" ;;
    esac
}

get_pd_dynamic() {
    local raw norm
    raw="$(get_pd_state_raw "$1")"
    norm="$(normalize_pd_state "$raw")"

    case "$norm" in
        online|good ) echo 1 ;;
        rebuilding|spare ) echo 3 ;;
        failed ) echo 5 ;;
        * ) echo 0 ;;
    esac
}

case "$MODE" in
    discover)
        first=1
        printf '['
        for i in $(seq 0 "$MAX_PD"); do
            out="$(smart_probe "$i")"
            printf '%s\n' "$out" | grep -qE 'Device Model:|Model Number:|Product:|Serial Number:' || continue

            name="$(printf '%s\n' "$out" | get_name)"
            serial="$(printf '%s\n' "$out" | get_serial)"
            dtype="$(printf '%s\n' "$out" | get_type)"

            [ -n "$name" ] || name="DID $i"
            [ -n "$serial" ] && name="$name [$serial]"
            esc_name="$(printf '%s' "$name" | json_escape)"

            [ "$first" -eq 1 ] || printf ','
            first=0
            printf '{"{#SNMPINDEX}":"%s","{#PDNAME}":"%s","{#PDTYPE}":"%s"}' "$i" "$esc_name" "$dtype"
        done
        printf ']\n'
        ;;
    type)
        smart_probe "$DID" | get_type
        ;;
    health)
        out="$(smart_probe "$DID")"
        dtype="$(printf '%s\n' "$out" | get_type)"
        if [ "$dtype" = "SSD" ]; then
            printf 'Not Applicable\n'
        else
            printf '%s\n' "$(printf '%s\n' "$out" | get_health_raw)"
        fi
        ;;
    wear)
        out="$(smart_probe "$DID")"
        dtype="$(printf '%s\n' "$out" | get_type)"
        if [ "$dtype" != "SSD" ]; then
            printf 'Not Available\n'
        else
            pct="$(get_wear_pct "$out")"
            if [ -n "$pct" ]; then
                printf '%s%% life left\n' "$pct"
            else
                printf 'Not Available\n'
            fi
        fi
        ;;
    wearpct)
        out="$(smart_probe "$DID")"
        dtype="$(printf '%s\n' "$out" | get_type)"
        if [ "$dtype" = "SSD" ]; then
            printf '%s\n' "$(get_wear_pct "$out")"
        else
            printf '\n'
        fi
        ;;
    dynamic)
        out="$(smart_probe "$DID")"
        get_dynamic_status "$out"
        ;;
    vddiscover)
        vd_discover
        ;;
    vdstate.raw)
        get_vd_state_raw "$DID"
        ;;
    vdstate)
        normalize_vd_state "$(get_vd_state_raw "$DID")"
        ;;
    vddynamic)
        get_vd_dynamic "$DID"
        ;;
    pdstate.raw)
        get_pd_state_raw "$DID"
        ;;
    pdstate)
        normalize_pd_state "$(get_pd_state_raw "$DID")"
        ;;
    pddynamic)
        get_pd_dynamic "$DID"
        ;;
    *)
        exit 1
        ;;
esac
