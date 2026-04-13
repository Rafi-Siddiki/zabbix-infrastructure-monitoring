#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?discover|type|health|wear|wearpct|dynamic}"
BASEDEV="${2:-/dev/sda}"
DID="${3:-}"

probe() {
    smartctl -a -d megaraid,"$1" "$BASEDEV" 2>/dev/null || true
}

json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])'
}

get_name() {
    awk -F: '
        /Device Model:|Model Number:|Product:/ {
            gsub(/^[ \t]+/, "", $2);
            print $2;
            exit
        }'
}

get_serial() {
    awk -F: '
        /Serial Number:/ {
            gsub(/^[ \t]+/, "", $2);
            print $2;
            exit
        }'
}

get_type() {
    if grep -qiE 'Rotation Rate:[[:space:]]*Solid State Device|Wear_Leveling_Count|Media_Wearout_Indicator|Percentage Used:'; then
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

get_wear_pct() {
    awk '
        # Prefer Intel/Lenovo SMART ID 233 if present
        /^[[:space:]]*233[[:space:]]+Media_Wearout_Indicator([[:space:]]|$)/ {
            v = $4
            gsub(/^0+/, "", v)
            if (v == "") v = 0
            print v
            found233 = 1
            exit
        }

        # Save ID 177 only as fallback, do NOT exit yet
        /^[[:space:]]*177[[:space:]]+Wear_Leveling_Count([[:space:]]|$)/ {
            if (!have177) {
                v177 = $4
                gsub(/^0+/, "", v177)
                if (v177 == "") v177 = 0
                have177 = 1
            }
        }

        # NVMe style: Percentage Used: 2%
        /Percentage Used:/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9]+%?$/) {
                    v = $i
                    gsub(/%/, "", v)
                    used = v + 0
                    have_nvme = 1
                    break
                }
            }
        }

        END {
            if (found233) exit
            if (have177) {
                print v177
                exit
            }
            if (have_nvme) {
                print 100 - used
                exit
            }
            print ""
        }'
}
get_dynamic_status() {
    local out="$1"
    # NEW: If probe is empty, return 0 immediately (Not Found)
    if [ -z "$out" ]; then echo 0; return; fi

    local dtype health pct
    dtype="$(printf '%s\n' "$out" | get_type)"
    
    if [ "$dtype" = "SSD" ]; then
        pct="$(printf '%s\n' "$out" | get_wear_pct)"
        if [ -z "$pct" ]; then echo 0; return; fi
        # Ensure we treat as number and remove leading zeros to avoid octal errors
        pct_num=$(echo "$pct" | sed 's/^0*//')
        [ -z "$pct_num" ] && pct_num=0
        
        if [ "$pct_num" -lt 30 ]; then echo 5; return; fi
        if [ "$pct_num" -lt 40 ]; then echo 3; return; fi
        echo 1; return
    fi

    health="$(printf '%s\n' "$out" | get_health_raw | tr '[:upper:]' '[:lower:]')"
    case "$health" in
        passed|ok|normal ) echo 1 ;;
        *degrad*|*warn*|*pre-fail*|*prefail*|*suspect* ) echo 3 ;;
        * ) echo 5 ;;
    esac
}


case "$MODE" in
    discover)
        first=1
        printf '['
        for i in $(seq 0 31); do
            out="$(probe "$i")"
            echo "$out" | grep -qE 'Device Model:|Model Number:|Product:|Serial Number:' || continue

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
        probe "$DID" | get_type
        ;;
    health)
        out="$(probe "$DID")"
        dtype="$(printf '%s\n' "$out" | get_type)"
        if [ "$dtype" = "SSD" ]; then
            printf 'Not Applicable\n'
        else
            printf '%s\n' "$(printf '%s\n' "$out" | get_health_raw)"
        fi
        ;;
    wear)
        out="$(probe "$DID")"
        dtype="$(printf '%s\n' "$out" | get_type)"
        if [ "$dtype" != "SSD" ]; then
            printf 'Not Available\n'
        else
            pct="$(printf '%s\n' "$out" | get_wear_pct)"
            if [ -n "$pct" ]; then printf '%s%% life left\n' "$pct"; else printf 'Not Available\n'; fi
        fi
        ;;
    wearpct)
        out="$(probe "$DID")"
        dtype="$(printf '%s\n' "$out" | get_type)"
        if [ "$dtype" = "SSD" ]; then
            printf '%s\n' "$(printf '%s\n' "$out" | get_wear_pct)"
        else
            printf '\n'
        fi
        ;;
    dynamic)
        out="$(probe "$DID")"
        get_dynamic_status "$out"
        ;;
    *)
        exit 1
        ;;
esac
