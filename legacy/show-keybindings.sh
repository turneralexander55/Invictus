#!/usr/bin/env bash

# ------------------------------------------------------------
# show-keybindings.sh
# Displays all Hyprland keybindings by parsing the config
# Shows actual resolved values for variables like $mainMod
# ------------------------------------------------------------

set -euo pipefail

HYPR_CONFIG="$HOME/.config/hypr/config/keybindings.conf"

# Check if config exists
if [[ ! -f "$HYPR_CONFIG" ]]; then
    notify-send "Keybindings" "Config file not found: $HYPR_CONFIG"
    exit 1
fi

# ------------------------------------------------------------
# Parse variables from config
# ------------------------------------------------------------
declare -A VARS

# Get mainMod and other variables
while IFS= read -r line; do
    # Remove leading/trailing whitespace
    line=$(echo "$line" | xargs)

    # Match lines like: $mainMod = SUPER
    if [[ $line =~ ^\$([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*([^#]+) ]]; then
        var_name="${BASH_REMATCH[1]}"
        var_value="${BASH_REMATCH[2]}"
        # Trim whitespace
        var_value=$(echo "$var_value" | xargs)
        VARS["$var_name"]="$var_value"
    fi
done < "$HYPR_CONFIG"

# Debug: show found variables
# for var in "${!VARS[@]}"; do
#     echo "VAR: \$$var = ${VARS[$var]}" >&2
# done

# ------------------------------------------------------------
# Function to resolve variables in a string
# ------------------------------------------------------------
resolve_vars() {
    local text="$1"

    # Replace $variableName with actual value
    for var_name in "${!VARS[@]}"; do
        text="${text//\$$var_name/${VARS[$var_name]}}"
    done

    echo "$text"
}

# ------------------------------------------------------------
# Parse keybindings
# ------------------------------------------------------------
OUTPUT_FILE=$(mktemp)

echo "=== HYPRLAND KEYBINDINGS ===" > "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

CURRENT_SECTION=""

while IFS= read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Detect section headers from comments
    if [[ $line =~ ^#[[:space:]]+(.+)$ ]]; then
        content="${BASH_REMATCH[1]}"

        # Skip separator lines
        [[ $content =~ ^─+ ]] && continue

        # Check if it's a section title (contains letters and is reasonably short)
        if [[ $content =~ ^[A-Za-z] ]] && [[ ${#content} -lt 80 ]]; then
            CURRENT_SECTION="$content"
            echo "" >> "$OUTPUT_FILE"
            echo "─── $CURRENT_SECTION ───" >> "$OUTPUT_FILE"
        fi
        continue
    fi

    # Match bind lines: bind = modifiers, key, action
    if [[ $line =~ ^bind[elm]*[[:space:]]*=[[:space:]]*(.+)$ ]]; then
        binding="${BASH_REMATCH[1]}"

        # Split by comma
        IFS=',' read -ra PARTS <<< "$binding"

        if [[ ${#PARTS[@]} -ge 3 ]]; then
            modifiers="${PARTS[0]}"
            key="${PARTS[1]}"
            action="${PARTS[2]}"

            # Get any remaining parts (parameters to the action)
            params=""
            if [[ ${#PARTS[@]} -gt 3 ]]; then
                params="${PARTS[*]:3}"
            fi

            # Clean up whitespace
            modifiers=$(echo "$modifiers" | xargs)
            key=$(echo "$key" | xargs)
            action=$(echo "$action" | xargs)
            params=$(echo "$params" | xargs)

            # Resolve variables
            modifiers=$(resolve_vars "$modifiers")
            key=$(resolve_vars "$key")

            # Build readable key combo
            if [[ -n "$modifiers" ]]; then
                # Replace common modifier names
                modifiers="${modifiers//SUPER/Super}"
                modifiers="${modifiers//SHIFT/Shift}"
                modifiers="${modifiers//CTRL/Ctrl}"
                modifiers="${modifiers//ALT/Alt}"

                key_combo="$modifiers + $key"
            else
                key_combo="$key"
            fi

            # Build description
            if [[ -n "$params" ]]; then
                description="$action, $params"
            else
                description="$action"
            fi

            # Format and add to output
            printf "  %-35s  →  %s\n" "$key_combo" "$description" >> "$OUTPUT_FILE"
        fi
    fi

    # Match bindm lines (mouse bindings)
    if [[ $line =~ ^bindm[[:space:]]*=[[:space:]]*(.+)$ ]]; then
        binding="${BASH_REMATCH[1]}"

        IFS=',' read -ra PARTS <<< "$binding"

        if [[ ${#PARTS[@]} -ge 3 ]]; then
            modifiers=$(echo "${PARTS[0]}" | xargs)
            button=$(echo "${PARTS[1]}" | xargs)
            action=$(echo "${PARTS[2]}" | xargs)

            modifiers=$(resolve_vars "$modifiers")
            modifiers="${modifiers//SUPER/Super}"

            printf "  %-35s  →  %s\n" "$modifiers + $button" "$action" >> "$OUTPUT_FILE"
        fi
    fi
done < "$HYPR_CONFIG"

echo "" >> "$OUTPUT_FILE"

# ------------------------------------------------------------
# Display the keybindings
# ------------------------------------------------------------

if command -v rofi &>/dev/null; then
    # Use rofi
    cat "$OUTPUT_FILE" | rofi -dmenu \
        -i \
        -p "Keybindings" \
        -theme-str 'window {width: 60%;} listview {lines: 25;}' \
        -no-custom

elif command -v yad &>/dev/null; then
    # Use yad
    yad --text-info \
        --title="Hyprland Keybindings" \
        --filename="$OUTPUT_FILE" \
        --width=900 \
        --height=700 \
        --button=gtk-close

else
    # Fallback: terminal
    if command -v kitty &>/dev/null; then
        kitty --title "Keybindings" -e less "$OUTPUT_FILE"
    else
        xterm -title "Keybindings" -e less "$OUTPUT_FILE"
    fi
fi

# Cleanup
rm -f "$OUTPUT_FILE"
