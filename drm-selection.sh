#!/bin/bash

# Match the character device identity, never its container filename or card index.
drm_card_for_id() {
    local root=$1 id=$2 card value name
    for card in "$root"/card*; do
        name=${card##*/}
        [[ $name =~ ^card[0-9]+$ ]] || continue
        if [[ -r $card/dev ]] && IFS= read -r value < "$card/dev" && [[ $value == "$id" ]]; then
            printf '%s\n' "$name"
            return 0
        fi
    done
    echo "Cannot identify DRM card for device $id in $root." >&2
    return 1
}

drm_resolve_connector() {
    local root=$1 card=$2 mode=$3 wanted=$4 path status name hash
    local -a connected=() matches=()
    if [[ $mode != auto ]]; then
        printf '%s\n' "$mode"
        return 0
    fi
    if [[ -n $wanted && ! $wanted =~ ^[[:xdigit:]]{64}$ ]]; then
        echo 'Invalid EDID SHA256: expected 64 hexadecimal characters.' >&2
        return 1
    fi
    wanted=${wanted,,}
    for path in "$root/$card-"*; do
        [[ -e $path ]] || continue
        if [[ ! -r $path/status ]] || ! IFS= read -r status < "$path/status"; then
            echo "Cannot read connector status: $path/status" >&2
            return 1
        fi
        [[ $status == connected ]] || continue
        name=${path##*/}; name=${name#"$card-"}
        connected+=("$name")
        if [[ -n $wanted ]]; then
            # sysfs attributes may report size zero even when reading returns data.
            if [[ ! -r $path/edid ]] || ! hash=$(cat "$path/edid" | sha256sum); then
                echo "Cannot read EDID for $name." >&2
                continue
            fi
            hash=${hash%% *}
            if [[ $hash == e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]]; then
                echo "Empty EDID for $name." >&2
                continue
            fi
            [[ $hash != "$wanted" ]] || matches+=("$name")
        fi
    done
    if (( ${#connected[@]} == 0 )); then
        echo "No connected DRM connectors found for $card." >&2
        return 1
    fi
    if [[ -n $wanted ]]; then
        if (( ${#matches[@]} == 0 )); then
            echo "No connected DRM connector matching EDID SHA256 $wanted. Candidates: ${connected[*]}" >&2
            return 1
        fi
    else
        matches=("${connected[@]}")
    fi
    if (( ${#matches[@]} != 1 )); then
        echo "Multiple connected DRM connectors found. Candidates: ${matches[*]}" >&2
        echo 'Set DRM_MONITOR_EDID_SHA256 to select the target monitor; duplicate EDIDs require an explicit DRM_CONNECTOR.' >&2
        return 1
    fi
    printf '%s\n' "${matches[0]}"
}
