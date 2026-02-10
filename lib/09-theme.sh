#!/usr/bin/env bash
# lib/09-theme.sh — Omarchy-inspired template engine for Tokyo Night theming
# Sourced by install.sh. Defines run_theme() only.
#
# Reads colors.toml and processes .tpl template files to generate themed
# configuration files in the config/ directory.

# ---------------------------------------------------------------------------
# Template-to-output mapping (strict contract with Task 6)
# ---------------------------------------------------------------------------

# Parallel arrays: template filenames and their corresponding output paths
# (relative to REPO_DIR). Order must match between the two arrays.
_THEME_TEMPLATES=(
    hyprland-colors.conf.tpl
    waybar-colors.css.tpl
    ghostty-theme.tpl
    mako-colors.tpl
    tofi-colors.tpl
    hyprlock-colors.conf.tpl
    gtk3-settings.ini.tpl
    gtk4-settings.ini.tpl
)
_THEME_OUTPUTS=(
    config/hypr/colors.conf
    config/waybar/colors.css
    config/ghostty/theme
    config/mako/colors
    config/tofi/colors
    config/hypr/hyprlock-colors.conf
    config/gtk-3.0/settings.ini
    config/gtk-4.0/settings.ini
)

# ---------------------------------------------------------------------------
# Helpers (prefixed to avoid namespace collisions)
# ---------------------------------------------------------------------------

_theme_hex_to_rgb() {
    # Convert a hex color (with or without #) to decimal R,G,B
    # Usage: _theme_hex_to_rgb "#7aa2f7" -> "122,162,247"
    local hex="$1"
    hex="${hex#\#}"  # strip leading #

    # Use printf to convert hex pairs to decimal
    local r g b
    r=$(printf '%d' "0x${hex:0:2}")
    g=$(printf '%d' "0x${hex:2:2}")
    b=$(printf '%d' "0x${hex:4:2}")

    printf '%d,%d,%d' "$r" "$g" "$b"
}

_theme_escape_sed() {
    # Escape characters that are special in sed replacement strings: \ & |
    # We use | as the sed delimiter, so it must be escaped too.
    local val="$1"
    # Escape backslash first (order matters), then & and |
    val="${val//\\/\\\\}"
    val="${val//&/\\&}"
    val="${val//|/\\|}"
    printf '%s' "$val"
}

_theme_parse_colors() {
    # Parse colors.toml and build a sed script with all substitutions.
    # Args: $1 = colors file path, $2 = output sed script path
    local colors_file="$1"
    local sed_script="$2"

    : > "$sed_script"  # truncate

    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Parse key = "value" (TOML string format)
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"

            # Variant 1: {{ key }} -> raw value (e.g. #7aa2f7)
            local escaped_val
            escaped_val="$(_theme_escape_sed "$val")"
            printf 's|{{ %s }}|%s|g\n' "$key" "$escaped_val" >> "$sed_script"

            # Variant 2: {{ key_strip }} -> without # prefix (e.g. 7aa2f7)
            local stripped="${val#\#}"
            local escaped_stripped
            escaped_stripped="$(_theme_escape_sed "$stripped")"
            printf 's|{{ %s_strip }}|%s|g\n' "$key" "$escaped_stripped" >> "$sed_script"

            # Variant 3: {{ key_rgb }} -> decimal R,G,B (e.g. 122,162,247)
            local rgb
            rgb="$(_theme_hex_to_rgb "$val")"
            local escaped_rgb
            escaped_rgb="$(_theme_escape_sed "$rgb")"
            printf 's|{{ %s_rgb }}|%s|g\n' "$key" "$escaped_rgb" >> "$sed_script"
        fi
    done < "$colors_file"
}

_theme_process_template() {
    # Process a single .tpl file through the sed script and write output.
    local tpl_file="$1"
    local output_file="$2"
    local sed_script="$3"

    # Create parent directory for the output file
    mkdir -p "$(dirname "$output_file")"

    # Apply all substitutions
    sed -f "$sed_script" "$tpl_file" > "$output_file"
}

# ---------------------------------------------------------------------------
# run_theme — Process all templates to generate themed config files
# ---------------------------------------------------------------------------

run_theme() {
    local colors_file="${REPO_DIR}/colors.toml"
    local templates_dir="${REPO_DIR}/templates"

    if [[ ! -f "$colors_file" ]]; then
        error "colors.toml not found at ${colors_file}"
        return 1
    fi

    if [[ ! -d "$templates_dir" ]]; then
        error "templates/ directory not found at ${templates_dir}"
        return 1
    fi

    info "Parsing color palette from colors.toml..."

    # Build sed script in a temp file
    local sed_script
    sed_script="$(mktemp /tmp/theme-sed.XXXXXX)"
    _theme_parse_colors "$colors_file" "$sed_script"

    local count
    count="$(wc -l < "$sed_script" | tr -d ' ')"
    info "Generated ${count} sed substitution rules ($(( count / 3 )) colors x 3 variants)"

    # Process each template per the contract mapping
    local i tpl_name output_rel tpl_path output_path
    local processed=0

    for i in "${!_THEME_TEMPLATES[@]}"; do
        tpl_name="${_THEME_TEMPLATES[$i]}"
        output_rel="${_THEME_OUTPUTS[$i]}"
        tpl_path="${templates_dir}/${tpl_name}"
        output_path="${REPO_DIR}/${output_rel}"

        if [[ ! -f "$tpl_path" ]]; then
            error "Template not found: ${tpl_path}"
            rm -f "$sed_script"
            return 1
        fi

        info "Processing ${tpl_name} -> ${output_rel}"
        _theme_process_template "$tpl_path" "$output_path" "$sed_script"
        processed=$(( processed + 1 ))
    done

    # Clean up temp file
    rm -f "$sed_script"

    success "Theme engine complete: ${processed} config files generated"
}
