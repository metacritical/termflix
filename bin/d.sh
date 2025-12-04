#!/usr/bin/env bash

# Color constants
COLOR_RESET=$'\033[0m'
COLOR_RED=$'\033[31m'
COLOR_GREEN=$'\033[32m'
COLOR_YELLOW=$'\033[33m'
COLOR_BLUE=$'\033[34m'
COLOR_PURPLE=$'\033[35m'
COLOR_CYAN=$'\033[36m'
COLOR_WHITE=$'\033[37m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
UNDERLINE=$'\033[4m'

# Function to execute docker commands
exec_docker_command() {
    local args="$*"
    local output
    output=$(docker $args 2>&1)
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        # Just return the output, as Docker commands often return exit codes for legitimate reasons
        echo "$output"
        return 0  # Continue execution
    fi
    echo "$output"
}

# Function to execute docker commands with proper I/O
exec_docker_command_with_error() {
    docker "$@"
    return $?
}

# Helper: filter only tab-separated docker rows (tolerate banners)
filter_tabbed_lines() {
    local min_tabs="$1"; shift
    local -a in_lines=("$@")
    local out=()
    for _l in "${in_lines[@]}"; do
        # Count tabs by removing non-tabs and measuring length
        local tabs_only=${_l//[^$'\t']/}
        local count=${#tabs_only}
        if [ "$count" -ge "$min_tabs" ]; then
            out+=("$_l")
        fi
    done
    printf '%s\n' "${out[@]}"
}

trim_whitespace() {
    local var="$1"
    # remove leading whitespace
    var="${var#"${var%%[!$' \t\r\n']*}"}"
    # remove trailing whitespace
    var="${var%"${var##*[!$' \t\r\n']}"}"
    printf '%s' "$var"
}

# Function to parse number ranges like "1-3,5,7" into an array
parse_number_ranges() {
    local input="$1"
    local -a result=()
    
    IFS=',' read -ra parts <<< "$input"
    
    for part in "${parts[@]}"; do
        part=$(trim_whitespace "$part")
        if [[ $part == *-* ]]; then
            # Handle range like "1-3"
            IFS='-' read -ra range_parts <<< "$part"
            if [ ${#range_parts[@]} -ne 2 ]; then
                continue
            fi
            
            local start=${range_parts[0]}
            local end=${range_parts[1]}
            
            # Verify they're numbers
            if ! [[ "$start" =~ ^[0-9]+$ ]] || ! [[ "$end" =~ ^[0-9]+$ ]]; then
                continue
            fi
            
            for ((i=start; i<=end; i++)); do
                result+=("$i")
            done
        else
            # Handle single number
            if [[ "$part" =~ ^[0-9]+$ ]]; then
                result+=("$part")
            fi
        fi
    done
    
    echo "${result[@]}"
}

# Function to format containers similar to SCM Breeze
format_containers_for_scm_breeze() {
    local -a containers=("$@")
    
    if [ ${#containers[@]} -eq 0 ]; then
        printf "${COLOR_RED}No containers found${COLOR_RESET}\n"
        return
    fi

    # Parse all containers first to calculate column widths
    local -a parsed_containers=()
    for container in "${containers[@]}"; do
        container=$(trim_whitespace "$container")
        IFS=$'\t' read -ra fields <<< "$container"
        # Ensure we have at least 3 fields (ID, Name, Status)
        # If ports is empty, we still want to include the container
        if [ ${#fields[@]} -ge 3 ]; then
            # Pad with empty string if ports field is missing
            if [ ${#fields[@]} -eq 3 ]; then
                fields+=("")  # Add empty ports field
            fi
            if [ ${#fields[@]} -ge 4 ]; then
                parsed_containers+=("${fields[0]}	${fields[1]}	${fields[2]}	${fields[3]}")
            fi
        fi
    done

    if [ ${#parsed_containers[@]} -eq 0 ]; then
        printf "${COLOR_RED}No containers found${COLOR_RESET}\n"
        return
    fi

    # Calculate max width for each column (excluding ports which will be formatted separately)
    local container_count=${#parsed_containers[@]}
    local max_num_width=${#container_count}
    local max_id_width=10   # minimum width for ID column
    local max_name_width=15 # minimum width for NAMES column
    local max_status_width=15 # minimum width for STATUS column

    for container in "${parsed_containers[@]}"; do
        local field_id field_name field_status field_ports
        IFS=$'\t' read -r field_id field_name field_status field_ports <<< "${container}$'\t'"
        if [ -n "$field_id" ] && [ ${#field_id} -gt $max_id_width ]; then
            max_id_width=${#field_id}
        fi
        if [ -n "$field_name" ] && [ ${#field_name} -gt $max_name_width ]; then
            max_name_width=${#field_name}
        fi
        if [ -n "$field_status" ] && [ ${#field_status} -gt $max_status_width ]; then
            max_status_width=${#field_status}
        fi
    done

    # Add some padding to column widths
    max_id_width=$((max_id_width + 2))
    max_name_width=$((max_name_width + 2))
    max_status_width=$((max_status_width + 2))

    # Build output
    local output=""
    local line header separator
    local line
    printf -v line "${COLOR_BLUE}# Docker Containers (%d found)${COLOR_RESET}\n" "$container_count"
    output+="$line"
    printf -v line "${COLOR_YELLOW}# Use: d c rm 1 2 3  or  d c rm 1-3 to select containers by number${COLOR_RESET}\n"
    output+="$line"
    output+="#\n"
    
    # Build header with calculated widths (use a reasonable default for ports width)
    printf -v header "#   ${COLOR_CYAN}NUM %-${max_id_width}s %-${max_name_width}s %-${max_status_width}s PORTS${COLOR_RESET}\n" "ID" "NAMES" "STATUS"
    output+="$header"

    # Build separator with calculated widths
    local separator
    printf -v separator "#   ${COLOR_CYAN}--- %-${max_id_width}s %-${max_name_width}s %-${max_status_width}s %s${COLOR_RESET}\n" \
        "$(printf '%*s' "$max_id_width" | tr ' ' '-')" \
        "$(printf '%*s' "$max_name_width" | tr ' ' '-')" \
        "$(printf '%*s' "$max_status_width" | tr ' ' '-')" \
        "$(printf '%*s' "30" | tr ' ' '-')"
    output+="$separator"

    # Output each container with proper column alignment
    local i=0
    for container in "${parsed_containers[@]}"; do
        i=$((i + 1))
        local field_id field_name field_status field_ports
        IFS=$'\t' read -r field_id field_name field_status field_ports <<< "${container}$'\t'"
        if [ -n "$field_id" ]; then
            # Format ports as multi-line if there are multiple ports
            # Split exactly on ", " sequence to match Go version
            local ports_lines=()
            if [ -n "$field_ports" ]; then
                local ports_string="$field_ports"
                ports_string=${ports_string//, /$'\n'}
                while IFS= read -r _pline; do
                    ports_lines+=("$_pline")
                done <<< "$ports_string"
            else
                ports_lines=("")
            fi
            
            # Process each port line
            for j in "${!ports_lines[@]}"; do
                local port_line="${ports_lines[$j]}"
                port_line=$(trim_whitespace "$port_line")
                
                if [ $j -eq 0 ]; then
                    # First line includes all columns
                    local aligned_port_line
                    aligned_port_line=$(add_ipv6_indicator "$port_line")
                    printf -v line "#   ${COLOR_GREEN}[%*d]${COLOR_RESET} %-${max_id_width}s %-${max_name_width}s %-${max_status_width}s %s\n" \
                        $max_num_width $i \
                        "$field_id" \
                        "$field_name" \
                        "$field_status" \
                        "$aligned_port_line"
                    output+="$line"
                else
                    # Subsequent lines have empty space for other columns
                    local aligned_port_line
                    aligned_port_line=$(add_ipv6_indicator "$port_line")
                    printf -v line "#   %*s   %-${max_id_width}s %-${max_name_width}s %-${max_status_width}s %s\n" \
                        $max_num_width "" \
                        "" \
                        "" \
                        "" \
                        "$aligned_port_line"
                    output+="$line"
                fi
            done
        fi
    done

    printf '%b' "$output"
}

# Function to format images similar to SCM Breeze
format_images_for_scm_breeze() {
    local -a images=("$@")
    
    if [ ${#images[@]} -eq 0 ]; then
        printf "${COLOR_RED}No images found${COLOR_RESET}\n"
        return
    fi

    # Parse all images first to calculate column widths
    local -a parsed_images=()
    for image in "${images[@]}"; do
        image=$(trim_whitespace "$image")
        IFS=$'\t' read -ra fields <<< "$image"
        if [ ${#fields[@]} -ge 4 ]; then
            parsed_images+=("${fields[0]}	${fields[1]}	${fields[2]}	${fields[3]}")
        fi
    done

    if [ ${#parsed_images[@]} -eq 0 ]; then
        printf "${COLOR_RED}No images found${COLOR_RESET}\n"
        return
    fi

    # Calculate max width for each column
    local image_count=${#parsed_images[@]}
    local max_num_width=${#image_count}
    local max_repo_width=12 # minimum width for repository column
    local max_tag_width=8   # minimum width for tag column
    local max_id_width=12   # minimum width for ID column
    local max_size_width=8  # minimum width for size column

    for image in "${parsed_images[@]}"; do
        IFS=$'\t' read -ra fields <<< "$image"
        if [ ${#fields[@]} -ge 4 ]; then
            if [ ${#fields[0]} -gt $max_repo_width ]; then
                max_repo_width=${#fields[0]}
            fi
            if [ ${#fields[1]} -gt $max_tag_width ]; then
                max_tag_width=${#fields[1]}
            fi
            if [ ${#fields[2]} -gt $max_id_width ]; then
                max_id_width=${#fields[2]}
            fi
            if [ ${#fields[3]} -gt $max_size_width ]; then
                max_size_width=${#fields[3]}
            fi
        fi
    done

    # Add some padding to column widths
    max_repo_width=$((max_repo_width + 2))
    max_tag_width=$((max_tag_width + 2))
    max_id_width=$((max_id_width + 2))
    max_size_width=$((max_size_width + 2))

    local output=""
    local line header separator
    printf -v line "${COLOR_BLUE}# Docker Images (%d found)${COLOR_RESET}\n" "$image_count"
    output+="$line"
    printf -v line "${COLOR_YELLOW}# Use: d rm 1 2 3  or  d rm 1-3 to select images by number${COLOR_RESET}\n"
    output+="$line"
    output+="#\n"
    
    # Build header with calculated widths
    printf -v header "#   ${COLOR_CYAN}NUM %-${max_repo_width}s %-${max_tag_width}s %-${max_id_width}s %-${max_size_width}s${COLOR_RESET}\n" "REPOSITORY" "TAG" "ID" "SIZE"
    output+="$header"
    
    # Build separator with calculated widths
    local separator
    printf -v separator "#   ${COLOR_CYAN}--- %-${max_repo_width}s %-${max_tag_width}s %-${max_id_width}s %-${max_size_width}s${COLOR_RESET}\n" \
        "$(printf '%*s' "$max_repo_width" | tr ' ' '-')" \
        "$(printf '%*s' "$max_tag_width" | tr ' ' '-')" \
        "$(printf '%*s' "$max_id_width" | tr ' ' '-')" \
        "$(printf '%*s' "$max_size_width" | tr ' ' '-')"
    output+="$separator"

    # Output each image with proper column alignment
    local i=0
    for image in "${parsed_images[@]}"; do
        i=$((i + 1))
        IFS=$'\t' read -ra fields <<< "$image"
        if [ ${#fields[@]} -ge 4 ]; then
            printf -v line "#   ${COLOR_GREEN}[%*d]${COLOR_RESET} %-${max_repo_width}s %-${max_tag_width}s %-${max_id_width}s %-${max_size_width}s\n" \
                $max_num_width $i \
                "${fields[0]}" \
                "${fields[1]}" \
                "${fields[2]}" \
                "${fields[3]}"
            output+="$line"
        fi
    done

    printf '%b' "$output"
}

# Function to format volumes similar to SCM Breeze
format_volumes_for_scm_breeze() {
    local -a volumes=("$@")
    
    if [ ${#volumes[@]} -eq 0 ]; then
        printf "${COLOR_RED}No volumes found${COLOR_RESET}\n"
        return
    fi

    # Parse all volumes first to calculate column widths
    local -a parsed_volumes=()
    for volume in "${volumes[@]}"; do
        volume=$(trim_whitespace "$volume")
        IFS=$'\t' read -ra fields <<< "$volume"
        if [ ${#fields[@]} -ge 2 ]; then
            parsed_volumes+=("${fields[0]}	${fields[1]}")
        fi
    done

    if [ ${#parsed_volumes[@]} -eq 0 ]; then
        printf "${COLOR_RED}No volumes found${COLOR_RESET}\n"
        return
    fi

    # Calculate max width for each column
    local volume_count=${#parsed_volumes[@]}
    local max_num_width=${#volume_count}
    local max_driver_width=10 # minimum width for DRIVER column
    local max_name_width=15   # minimum width for NAME column

    for volume in "${parsed_volumes[@]}"; do
        IFS=$'\t' read -ra fields <<< "$volume"
        if [ ${#fields[@]} -ge 2 ]; then
            if [ ${#fields[0]} -gt $max_driver_width ]; then
                max_driver_width=${#fields[0]}
            fi
            if [ ${#fields[1]} -gt $max_name_width ]; then
                max_name_width=${#fields[1]}
            fi
        fi
    done

    # Add some padding to column widths
    max_driver_width=$((max_driver_width + 2))
    max_name_width=$((max_name_width + 2))

    local output=""
    local line header separator
    printf -v line "${COLOR_BLUE}# Docker Volumes (%d found)${COLOR_RESET}\n" "$volume_count"
    output+="$line"
    printf -v line "${COLOR_YELLOW}# Use: d v rm 1 2 3  or  d v rm 1-3 to select volumes by number${COLOR_RESET}\n"
    output+="$line"
    output+="#\n"
    
    # Build header with calculated widths
    printf -v header "#   ${COLOR_CYAN}NUM %-${max_driver_width}s %-${max_name_width}s${COLOR_RESET}\n" "DRIVER" "NAME"
    output+="$header"
    
    # Build separator with calculated widths
    local separator
    printf -v separator "#   ${COLOR_CYAN}--- %-${max_driver_width}s %-${max_name_width}s${COLOR_RESET}\n" \
        "$(printf '%*s' "$max_driver_width" | tr ' ' '-')" \
        "$(printf '%*s' "$max_name_width" | tr ' ' '-')"
    output+="$separator"

    # Output each volume with proper column alignment
    local i=0
    for volume in "${parsed_volumes[@]}"; do
        i=$((i + 1))
        IFS=$'\t' read -ra fields <<< "$volume"
        if [ ${#fields[@]} -ge 2 ]; then
            printf -v line "#   ${COLOR_GREEN}[%*d]${COLOR_RESET} %-${max_driver_width}s %-${max_name_width}s\n" \
                $max_num_width $i \
                "${fields[0]}" \
                "${fields[1]}"
            output+="$line"
        fi
    done

    printf '%b' "$output"
}

# Function to format networks similar to SCM Breeze
format_networks_for_scm_breeze() {
    local -a networks=("$@")
    
    if [ ${#networks[@]} -eq 0 ]; then
        printf "${COLOR_RED}No networks found${COLOR_RESET}\n"
        return
    fi

    # Parse all networks first to calculate column widths
    local -a parsed_networks=()
    for network in "${networks[@]}"; do
        network=$(trim_whitespace "$network")
        IFS=$'\t' read -ra fields <<< "$network"
        if [ ${#fields[@]} -ge 4 ]; then
            parsed_networks+=("${fields[0]}	${fields[1]}	${fields[2]}	${fields[3]}")
        fi
    done

    if [ ${#parsed_networks[@]} -eq 0 ]; then
        printf "${COLOR_RED}No networks found${COLOR_RESET}\n"
        return
    fi

    # Calculate max width for each column
    local network_count=${#parsed_networks[@]}
    local max_num_width=${#network_count}
    local max_id_width=10     # minimum width for ID column
    local max_name_width=15   # minimum width for NAME column
    local max_driver_width=10 # minimum width for DRIVER column
    local max_scope_width=8   # minimum width for SCOPE column

    for network in "${parsed_networks[@]}"; do
        IFS=$'\t' read -ra fields <<< "$network"
        if [ ${#fields[@]} -ge 4 ]; then
            if [ ${#fields[0]} -gt $max_id_width ]; then
                max_id_width=${#fields[0]}
            fi
            if [ ${#fields[1]} -gt $max_name_width ]; then
                max_name_width=${#fields[1]}
            fi
            if [ ${#fields[2]} -gt $max_driver_width ]; then
                max_driver_width=${#fields[2]}
            fi
            if [ ${#fields[3]} -gt $max_scope_width ]; then
                max_scope_width=${#fields[3]}
            fi
        fi
    done

    # Add some padding to column widths
    max_id_width=$((max_id_width + 2))
    max_name_width=$((max_name_width + 2))
    max_driver_width=$((max_driver_width + 2))
    max_scope_width=$((max_scope_width + 2))

    local output=""
    local line header separator
    printf -v line "${COLOR_BLUE}# Docker Networks (%d found)${COLOR_RESET}\n" "$network_count"
    output+="$line"
    printf -v line "${COLOR_YELLOW}# Use: d n rm 1 2 3  or  d n rm 1-3 to select networks by number${COLOR_RESET}\n"
    output+="$line"
    output+="#\n"
    
    # Build header with calculated widths
    printf -v header "#   ${COLOR_CYAN}NUM %-${max_id_width}s %-${max_name_width}s %-${max_driver_width}s %-${max_scope_width}s${COLOR_RESET}\n" "ID" "NAME" "DRIVER" "SCOPE"
    output+="$header"
    
    # Build separator with calculated widths
    local separator
    printf -v separator "#   ${COLOR_CYAN}--- %-${max_id_width}s %-${max_name_width}s %-${max_driver_width}s %-${max_scope_width}s${COLOR_RESET}\n" \
        "$(printf '%*s' "$max_id_width" | tr ' ' '-')" \
        "$(printf '%*s' "$max_name_width" | tr ' ' '-')" \
        "$(printf '%*s' "$max_driver_width" | tr ' ' '-')" \
        "$(printf '%*s' "$max_scope_width" | tr ' ' '-')"
    output+="$separator"

    # Output each network with proper column alignment
    local i=0
    for network in "${parsed_networks[@]}"; do
        i=$((i + 1))
        IFS=$'\t' read -ra fields <<< "$network"
        if [ ${#fields[@]} -ge 4 ]; then
            printf -v line "#   ${COLOR_GREEN}[%*d]${COLOR_RESET} %-${max_id_width}s %-${max_name_width}s %-${max_driver_width}s %-${max_scope_width}s\n" \
                $max_num_width $i \
                "${fields[0]}" \
                "${fields[1]}" \
                "${fields[2]}" \
                "${fields[3]}"
            output+="$line"
        fi
    done

    printf '%b' "$output"
}

# Function to list running containers in SCM Breeze format
list_running_containers_scm() {
    local output
    output=$(exec_docker_command "ps" "--format" '{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}')
    local -a lines=()
    while IFS= read -r _line; do
        lines+=("$_line")
    done <<< "$output"
    local filtered_lines=()
    while IFS= read -r _line; do
        filtered_lines+=("$_line")
    done < <(filter_tabbed_lines 2 "${lines[@]}")
    lines=("${filtered_lines[@]}")
    format_containers_for_scm_breeze "${lines[@]}"
}

# Function to list all containers in SCM Breeze format
list_all_containers_scm() {
    local output
    output=$(exec_docker_command "ps" "-a" "--format" '{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}')
    local -a lines=()
    while IFS= read -r _line; do
        lines+=("$_line")
    done <<< "$output"
    local filtered_lines=()
    while IFS= read -r _line; do
        filtered_lines+=("$_line")
    done < <(filter_tabbed_lines 2 "${lines[@]}")
    lines=("${filtered_lines[@]}")
    format_containers_for_scm_breeze "${lines[@]}"
}

# Function to list images in SCM Breeze format
list_images_scm() {
    local output
    output=$(exec_docker_command "images" "--format" '{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}')
    local -a lines=()
    while IFS= read -r _line; do
        lines+=("$_line")
    done <<< "$output"
    local filtered_lines=()
    while IFS= read -r _line; do
        filtered_lines+=("$_line")
    done < <(filter_tabbed_lines 3 "${lines[@]}")
    lines=("${filtered_lines[@]}")
    format_images_for_scm_breeze "${lines[@]}"
}

# Function to list volumes in SCM Breeze format
list_volumes_scm() {
    local output
    output=$(exec_docker_command "volume" "ls" "--format" '{{.Driver}}\t{{.Name}}')
    local -a lines=()
    while IFS= read -r _line; do
        lines+=("$_line")
    done <<< "$output"
    local filtered_lines=()
    while IFS= read -r _line; do
        filtered_lines+=("$_line")
    done < <(filter_tabbed_lines 1 "${lines[@]}")
    lines=("${filtered_lines[@]}")
    format_volumes_for_scm_breeze "${lines[@]}"
}

# Function to list networks in SCM Breeze format
list_networks_scm() {
    local output
    output=$(exec_docker_command "network" "ls" "--format" '{{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}')
    local -a lines=()
    while IFS= read -r _line; do
        lines+=("$_line")
    done <<< "$output"
    local filtered_lines=()
    while IFS= read -r _line; do
        filtered_lines+=("$_line")
    done < <(filter_tabbed_lines 3 "${lines[@]}")
    lines=("${filtered_lines[@]}")
    format_networks_for_scm_breeze "${lines[@]}"
}

# Function to get container IDs based on selected line numbers
get_container_ids_from_lines() {
    local -a lines=("$@")
    local -a numbers=()
    
    # Extract numbers from the end of the array
    local num_args=${lines[${#lines[@]}-1]}
    numbers=($num_args)
    
    # Remove the last element (numbers) from lines array
    unset 'lines[${#lines[@]}-1]'
    
    local -a ids=()
    for num in "${numbers[@]}"; do
        # Adjust for 1-based user input to 0-based array indexing
        local index=$((num - 1))
        if [ $index -ge 0 ] && [ $index -lt ${#lines[@]} ]; then
            local line="${lines[$index]}"
            line=$(trim_whitespace "$line")
            IFS=$'\t' read -ra fields <<< "$line"
            # Ensure we have at least 3 fields (ID, Name, Status) and add empty ports if needed
            if [ ${#fields[@]} -ge 3 ]; then
                # If we only have 3 fields (ID, Name, Status), and ports are missing,
                # we still want to process this container
                if [ ${#fields[@]} -eq 3 ]; then
                    fields+=("")  # Add empty ports field to make 4 total
                fi
                if [ ${#fields[@]} -ge 4 ]; then
                    ids+=("${fields[0]}")  # First field is container ID
                fi
            fi
        fi
    done
    echo "${ids[@]}"
}

# Function to get image IDs based on selected line numbers
get_image_ids_from_lines() {
    local -a lines=("$@")
    local -a numbers=()
    
    # Extract numbers from the end of the array
    local num_args=${lines[${#lines[@]}-1]}
    numbers=($num_args)
    
    # Remove the last element (numbers) from lines array
    unset 'lines[${#lines[@]}-1]'
    
    local -a ids=()
    for num in "${numbers[@]}"; do
        # Adjust for 1-based user input to 0-based array indexing
        local index=$((num - 1))
        if [ $index -ge 0 ] && [ $index -lt ${#lines[@]} ]; then
            local line="${lines[$index]}"
            line=$(trim_whitespace "$line")
            IFS=$'\t' read -ra fields <<< "$line"
            if [ ${#fields[@]} -ge 4 ]; then
                ids+=("${fields[2]}")  # Third field (0-indexed) is image ID
            fi
        fi
    done
    echo "${ids[@]}"
}

# Function to get volume names based on selected line numbers
get_volume_names_from_lines() {
    local -a lines=("$@")
    local -a numbers=()
    
    # Extract numbers from the end of the array
    local num_args=${lines[${#lines[@]}-1]}
    numbers=($num_args)
    
    # Remove the last element (numbers) from lines array
    unset 'lines[${#lines[@]}-1]'
    
    local -a names=()
    for num in "${numbers[@]}"; do
        # Adjust for 1-based user input to 0-based array indexing
        local index=$((num - 1))
        if [ $index -ge 0 ] && [ $index -lt ${#lines[@]} ]; then
            local line="${lines[$index]}"
            line=$(trim_whitespace "$line")
            IFS=$'\t' read -ra fields <<< "$line"
            if [ ${#fields[@]} -ge 2 ]; then
                names+=("${fields[1]}")  # Second field is volume name
            fi
        fi
    done
    echo "${names[@]}"
}

# Function to get network IDs based on selected line numbers
get_network_ids_from_lines() {
    local -a lines=("$@")
    local -a numbers=()
    
    # Extract numbers from the end of the array
    local num_args=${lines[${#lines[@]}-1]}
    numbers=($num_args)
    
    # Remove the last element (numbers) from lines array
    unset 'lines[${#lines[@]}-1]'
    
    local -a ids=()
    for num in "${numbers[@]}"; do
        # Adjust for 1-based user input to 0-based array indexing
        local index=$((num - 1))
        if [ $index -ge 0 ] && [ $index -lt ${#lines[@]} ]; then
            local line="${lines[$index]}"
            line=$(trim_whitespace "$line")
            IFS=$'\t' read -ra fields <<< "$line"
            if [ ${#fields[@]} -ge 4 ]; then
                ids+=("${fields[0]}")  # First field is network ID
            fi
        fi
    done
    echo "${ids[@]}"
}

# Function to add IPv6 indicator to port lines
add_ipv6_indicator() {
    local port_line="$1"
    if [[ $port_line == *"[::]"* ]]; then
        # Color the [::] part and add IPv6 indicator
        local indicated_port
        indicated_port=$(echo "$port_line" | sed "s/\[::\]/${COLOR_YELLOW}[::]${COLOR_RESET}(IPv6)/")
        echo "$indicated_port"
    else
        echo "$port_line"
    fi
}

# Container subcommand function
container_subcommand() {
    local -a args=("$@")
    
    if [ ${#args[@]} -eq 0 ]; then
        printf "${COLOR_CYAN}Container commands:${COLOR_RESET}\\n"
        echo "  ${COLOR_GREEN}ps${COLOR_RESET}                    - List running containers"
        echo "  ${COLOR_GREEN}ls${COLOR_RESET}                    - List all containers"
        echo "  ${COLOR_GREEN}start 1 2 3${COLOR_RESET}           - Start containers by number"
        echo "  ${COLOR_GREEN}stop 1 2 3${COLOR_RESET}            - Stop containers by number"
        echo "  ${COLOR_GREEN}restart 1 2 3${COLOR_RESET}         - Restart containers by number"
        echo "  ${COLOR_GREEN}rm 1 2 3${COLOR_RESET}              - Remove containers by number"
        echo "  ${COLOR_GREEN}logs 1${COLOR_RESET}                - View logs for container by number"
        echo "  ${COLOR_GREEN}exec 1 [command]${COLOR_RESET}      - Execute command in container by number"
        return
    fi
    
    case "${args[0]}" in
        "ps")
            list_running_containers_scm
            ;;
        "ls")
            list_all_containers_scm
            ;;
        "start")
            if [ ${#args[@]} -lt 2 ]; then
                echo "Usage: d c start [number range] (e.g., d c start 1 2 3 or d c start 1-3)"
                return
            fi
            # Get current containers
            local output
            output=$(exec_docker_command "ps" "-a" "--format" '{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}')
            local -a lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done <<< "$output"
            local filtered_lines=()
            while IFS= read -r _line; do
                filtered_lines+=("$_line")
            done < <(filter_tabbed_lines 2 "${lines[@]}")
            lines=("${filtered_lines[@]}")
            if [ ${#lines[@]} -lt 1 ]; then
                echo "No containers found"
                return
            fi

            # Parse number ranges
            local all_numbers=()
            for ((i=1; i<${#args[@]}; i++)); do
                local numbers
                numbers=$(parse_number_ranges "${args[$i]}")
                all_numbers+=($numbers)
            done

            # Get container IDs
            local numbers_str="${all_numbers[*]}"
            local container_ids
            container_ids=$(get_container_ids_from_lines "${lines[@]}" "$numbers_str")
            if [ ${#container_ids} -eq 0 ]; then
                echo "No valid container numbers found"
                return
            fi

            # Execute docker start command
            exec_docker_command "start" $container_ids
            ;;
        "stop")
            if [ ${#args[@]} -lt 2 ]; then
                echo "Usage: d c stop [number range] (e.g., d c stop 1 2 3 or d c stop 1-3)"
                return
            fi
            # Get current containers
            local output
            output=$(exec_docker_command "ps" "-a" "--format" '{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}')
            local -a lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done <<< "$output"
            local filtered_lines=()
            while IFS= read -r _line; do
                filtered_lines+=("$_line")
            done < <(filter_tabbed_lines 2 "${lines[@]}")
            lines=("${filtered_lines[@]}")
            if [ ${#lines[@]} -lt 1 ]; then
                echo "No containers found"
                return
            fi

            # Parse number ranges
            local all_numbers=()
            for ((i=1; i<${#args[@]}; i++)); do
                local numbers
                numbers=$(parse_number_ranges "${args[$i]}")
                all_numbers+=($numbers)
            done

            # Get container IDs
            local numbers_str="${all_numbers[*]}"
            local container_ids
            container_ids=$(get_container_ids_from_lines "${lines[@]}" "$numbers_str")
            if [ ${#container_ids} -eq 0 ]; then
                echo "No valid container numbers found"
                return
            fi

            # Execute docker stop command
            exec_docker_command "stop" $container_ids
            ;;
        "restart")
            if [ ${#args[@]} -lt 2 ]; then
                echo "Usage: d c restart [number range] (e.g., d c restart 1 2 3 or d c restart 1-3)"
                return
            fi
            # Get current containers
            local output
            output=$(exec_docker_command "ps" "-a" "--format" '{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}')
            local -a lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done <<< "$output"
            local filtered_lines=()
            while IFS= read -r _line; do
                filtered_lines+=("$_line")
            done < <(filter_tabbed_lines 2 "${lines[@]}")
            lines=("${filtered_lines[@]}")
            if [ ${#lines[@]} -lt 1 ]; then
                echo "No containers found"
                return
            fi

            # Parse number ranges
            local all_numbers=()
            for ((i=1; i<${#args[@]}; i++)); do
                local numbers
                numbers=$(parse_number_ranges "${args[$i]}")
                all_numbers+=($numbers)
            done

            # Get container IDs
            local numbers_str="${all_numbers[*]}"
            local container_ids
            container_ids=$(get_container_ids_from_lines "${lines[@]}" "$numbers_str")
            if [ ${#container_ids} -eq 0 ]; then
                echo "No valid container numbers found"
                return
            fi

            # Execute docker restart command
            exec_docker_command "restart" $container_ids
            ;;
        "rm")
            if [ ${#args[@]} -lt 2 ]; then
                echo "Usage: d c rm [number range] (e.g., d c rm 1 2 3 or d c rm 1-3)"
                return
            fi
            # Get current containers
            local output
            output=$(exec_docker_command "ps" "-a" "--format" '{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}')
            local -a lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done <<< "$output"
            local filtered_lines=()
            while IFS= read -r _line; do
                filtered_lines+=("$_line")
            done < <(filter_tabbed_lines 2 "${lines[@]}")
            lines=("${filtered_lines[@]}")
            if [ ${#lines[@]} -lt 1 ]; then
                echo "No containers found"
                return
            fi

            # Parse number ranges
            local all_numbers=()
            for ((i=1; i<${#args[@]}; i++)); do
                local numbers
                numbers=$(parse_number_ranges "${args[$i]}")
                all_numbers+=($numbers)
            done

            # Get container IDs
            local numbers_str="${all_numbers[*]}"
            local container_ids
            container_ids=$(get_container_ids_from_lines "${lines[@]}" "$numbers_str")
            if [ ${#container_ids} -eq 0 ]; then
                echo "No valid container numbers found"
                return
            fi

            # Execute docker rm command
            exec_docker_command "rm" $container_ids
            ;;
        "logs")
            if [ ${#args[@]} -lt 2 ]; then
                echo "Usage: d c logs [container number]"
                return
            fi
            # Get current containers
            local output
            output=$(exec_docker_command "ps" "-a" "--format" '{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}')
            local -a lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done <<< "$output"
            local filtered_lines=()
            while IFS= read -r _line; do
                filtered_lines+=("$_line")
            done < <(filter_tabbed_lines 2 "${lines[@]}")
            lines=("${filtered_lines[@]}")
            if [ ${#lines[@]} -lt 1 ]; then
                echo "No containers found"
                return
            fi

            # Parse number
            local container_num="${args[1]}"
            if ! [[ "$container_num" =~ ^[0-9]+$ ]]; then
                echo "Error parsing container number: $container_num"
                return
            fi

            # Get container ID
            local container_ids
            container_ids=$(get_container_ids_from_lines "${lines[@]}" "$container_num")
            if [ ${#container_ids} -eq 0 ]; then
                echo "No valid container number found"
                return
            fi

            # Execute docker logs command
            exec_docker_command_with_error "logs" "$container_ids"
            ;;
        "exec")
            if [ ${#args[@]} -lt 3 ]; then
                echo "Usage: d c exec [container number] [command]"
                return
            fi
            # Get current containers
            local output
            output=$(exec_docker_command "ps" "-a" "--format" '{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}')
            local -a lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done <<< "$output"
            local filtered_lines=()
            while IFS= read -r _line; do
                filtered_lines+=("$_line")
            done < <(filter_tabbed_lines 2 "${lines[@]}")
            lines=("${filtered_lines[@]}")
            if [ ${#lines[@]} -lt 1 ]; then
                echo "No containers found"
                return
            fi

            # Parse number
            local container_num="${args[1]}"
            if ! [[ "$container_num" =~ ^[0-9]+$ ]]; then
                echo "Error parsing container number: $container_num"
                return
            fi

            # Get container ID
            local container_ids
            container_ids=$(get_container_ids_from_lines "${lines[@]}" "$container_num")
            if [ ${#container_ids} -eq 0 ]; then
                echo "No valid container number found"
                return
            fi

            # Execute docker exec command
            local command="${args[@]:2}"
            exec_docker_command_with_error "exec" "-it" "$container_ids" "sh" "-c" "$command"
            ;;
        *)
            printf "${COLOR_RED}Unknown container command: ${args[0]}${COLOR_RESET}\n"
            echo "Run 'd c' for help"
            ;;
    esac
}

# Volume subcommand function
volume_subcommand() {
    local -a args=("$@")
    
    if [ ${#args[@]} -eq 0 ]; then
        printf "${COLOR_CYAN}Volume commands:${COLOR_RESET}\n"
        printf "  ${COLOR_GREEN}ls${COLOR_RESET}                    - List volumes\n"
        printf "  ${COLOR_GREEN}rm 1 2 3${COLOR_RESET}              - Remove volumes by number\n"
        return
    fi
    
    case "${args[0]}" in
        "ls")
            list_volumes_scm
            ;;
        "rm")
            if [ ${#args[@]} -lt 2 ]; then
                echo "Usage: d v rm [number range] (e.g., d v rm 1 2 3 or d v rm 1-3)"
                return
            fi
            # Get current volumes
            local output
            output=$(exec_docker_command "volume" "ls" "--format" '{{.Driver}}\t{{.Name}}')
            local -a lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done <<< "$output"
            local filtered_lines=()
            while IFS= read -r _line; do
                filtered_lines+=("$_line")
            done < <(filter_tabbed_lines 1 "${lines[@]}")
            lines=("${filtered_lines[@]}")
            if [ ${#lines[@]} -lt 1 ]; then
                echo "No volumes found"
                return
            fi

            # Parse number ranges
            local all_numbers=()
            for ((i=1; i<${#args[@]}; i++)); do
                local numbers
                numbers=$(parse_number_ranges "${args[$i]}")
                all_numbers+=($numbers)
            done

            # Get volume names
            local numbers_str="${all_numbers[*]}"
            local volume_names
            volume_names=$(get_volume_names_from_lines "${lines[@]}" "$numbers_str")
            if [ ${#volume_names} -eq 0 ]; then
                echo "No valid volume numbers found"
                return
            fi

            # Execute docker volume rm command
            exec_docker_command "volume" "rm" $volume_names
            ;;
        *)
            printf "${COLOR_RED}Unknown volume command: ${args[0]}${COLOR_RESET}\n"
            echo "Run 'd v' for help"
            ;;
    esac
}

# Network subcommand function
network_subcommand() {
    local -a args=("$@")
    
    if [ ${#args[@]} -eq 0 ]; then
        printf "${COLOR_CYAN}Network commands:${COLOR_RESET}\n"
        printf "  ${COLOR_GREEN}ls${COLOR_RESET}                    - List networks\n"
        printf "  ${COLOR_GREEN}rm 1 2 3${COLOR_RESET}              - Remove networks by number\n"
        return
    fi
    
    case "${args[0]}" in
        "ls")
            list_networks_scm
            ;;
        "rm")
            if [ ${#args[@]} -lt 2 ]; then
                echo "Usage: d n rm [number range] (e.g., d n rm 1 2 3 or d n rm 1-3)"
                return
            fi
            # Get current networks
            local output
            output=$(exec_docker_command "network" "ls" "--format" '{{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}')
            local -a lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done <<< "$output"
            local filtered_lines=()
            while IFS= read -r _line; do
                filtered_lines+=("$_line")
            done < <(filter_tabbed_lines 3 "${lines[@]}")
            lines=("${filtered_lines[@]}")
            if [ ${#lines[@]} -lt 1 ]; then
                echo "No networks found"
                return
            fi

            # Parse number ranges
            local all_numbers=()
            for ((i=1; i<${#args[@]}; i++)); do
                local numbers
                numbers=$(parse_number_ranges "${args[$i]}")
                all_numbers+=($numbers)
            done

            # Get network IDs
            local numbers_str="${all_numbers[*]}"
            local network_ids
            network_ids=$(get_network_ids_from_lines "${lines[@]}" "$numbers_str")
            if [ ${#network_ids} -eq 0 ]; then
                echo "No valid network numbers found"
                return
            fi

            # Execute docker network rm command
            exec_docker_command "network" "rm" $network_ids
            ;;
        *)
            printf "${COLOR_RED}Unknown network command: ${args[0]}${COLOR_RESET}\n"
            echo "Run 'd n' for help"
            ;;
    esac
}

# Compose subcommand function
compose_subcommand() {
    local -a args=("$@")
    
    if [ ${#args[@]} -eq 0 ]; then
        printf "${COLOR_CYAN}Docker Compose commands:${COLOR_RESET}\n"
        printf "  ${COLOR_GREEN}up${COLOR_RESET}                    - Start services\n"
        printf "  ${COLOR_GREEN}down${COLOR_RESET}                  - Stop and remove services\n"
        printf "  ${COLOR_GREEN}ps${COLOR_RESET}                    - List services\n"
        printf "  ${COLOR_GREEN}logs${COLOR_RESET}                  - View logs for services\n"
        return
    fi
    
    case "${args[0]}" in
        "up")
            exec_docker_command "compose" "up"
            ;;
        "down")
            exec_docker_command "compose" "down"
            ;;
        "ps")
            exec_docker_command "compose" "ps"
            ;;
        "logs")
            exec_docker_command "compose" "logs"
            ;;
        *)
            printf "${COLOR_RED}Unknown compose command: ${args[0]}${COLOR_RESET}\n"
            echo "Run 'd compose' for help"
            ;;
    esac
}

# Main function
main() {
    local -a args=("$@")
    
    if [ ${#args[@]} -eq 0 ]; then
        printf "${COLOR_BLUE}${BOLD}Docker utility - SCM Breeze style shortcuts for Docker commands${COLOR_RESET}\n"
        echo
        printf "${COLOR_YELLOW}Usage: d [command]${COLOR_RESET}\n"
        printf "${COLOR_YELLOW}   or: d c [command]     (for container operations)${COLOR_RESET}\n"
        printf "${COLOR_YELLOW}   or: d v [command]     (for volume operations)${COLOR_RESET}\n"
        printf "${COLOR_YELLOW}   or: d n [command]     (for network operations)${COLOR_RESET}\n"
        echo
        printf "${COLOR_CYAN}General commands:${COLOR_RESET}\n"
        printf "  ${COLOR_GREEN}c${COLOR_RESET}                     - List all containers (SCM Breeze style, alias for 'd ls')\n"
        printf "  ${COLOR_GREEN}cd <number>${COLOR_RESET}           - Get shell (bash or sh) in container by number\n"
        printf "  ${COLOR_GREEN}ps${COLOR_RESET}                    - List running containers (SCM Breeze style)\n"
        printf "  ${COLOR_GREEN}ls${COLOR_RESET}                    - List all containers (SCM Breeze style)\n"
        printf "  ${COLOR_GREEN}i | img${COLOR_RESET}               - List images (SCM Breeze style)\n"
        printf "  ${COLOR_GREEN}v | vol${COLOR_RESET}               - List volumes (SCM Breeze style)\n"
        printf "  ${COLOR_GREEN}n | net${COLOR_RESET}               - List networks (SCM Breeze style)\n"
        printf "  ${COLOR_GREEN}df${COLOR_RESET}                    - Show disk usage\n"
        printf "  ${COLOR_GREEN}prune${COLOR_RESET}                 - Remove unused data\n"
        printf "  ${COLOR_GREEN}info${COLOR_RESET}                  - Show system info\n"
        printf "  ${COLOR_GREEN}version${COLOR_RESET}               - Show version\n"
        printf "  ${COLOR_GREEN}stats${COLOR_RESET}                 - Show resource usage\n"
        echo
        printf "${COLOR_CYAN}Docker Compose commands:${COLOR_RESET}\n"
        printf "  ${COLOR_GREEN}u${COLOR_RESET}                     - Docker Compose up\n"
        printf "  ${COLOR_GREEN}d${COLOR_RESET}                     - Docker Compose down\n"
        printf "  ${COLOR_GREEN}l${COLOR_RESET}                     - Docker Compose logs\n"
        printf "  ${COLOR_GREEN}compose [command]${COLOR_RESET}     - Use Docker Compose directly (up, down, ps, logs)\n"
        echo
        printf "${COLOR_CYAN}Container commands (d c):${COLOR_RESET}\n"
        printf "  ${COLOR_GREEN}ps${COLOR_RESET}                    - List running containers\n"
        printf "  ${COLOR_GREEN}ls${COLOR_RESET}                    - List all containers\n"
        printf "  ${COLOR_GREEN}start 1 2 3${COLOR_RESET}           - Start containers by number\n"
        printf "  ${COLOR_GREEN}stop 1 2 3${COLOR_RESET}            - Stop containers by number\n"
        printf "  ${COLOR_GREEN}restart 1 2 3${COLOR_RESET}         - Restart containers by number\n"
        printf "  ${COLOR_GREEN}rm 1 2 3${COLOR_RESET}              - Remove containers by number\n"
        printf "  ${COLOR_GREEN}logs 1${COLOR_RESET}                - View logs for container by number\n"
        printf "  ${COLOR_GREEN}exec 1 [command]${COLOR_RESET}      - Execute command in container by number\n"
        echo
        printf "${COLOR_CYAN}Image commands:${COLOR_RESET}\n"
        printf "  ${COLOR_GREEN}rm 1 2 3${COLOR_RESET}              - Remove images by number\n"
        echo
        printf "${COLOR_CYAN}Volume commands (d v):${COLOR_RESET}\n"
        printf "  ${COLOR_GREEN}ls${COLOR_RESET}                    - List volumes\n"
        printf "  ${COLOR_GREEN}rm 1 2 3${COLOR_RESET}              - Remove volumes by number\n"
        echo
        printf "${COLOR_CYAN}Network commands (d n):${COLOR_RESET}\n"
        printf "  ${COLOR_GREEN}ls${COLOR_RESET}                    - List networks\n"
        printf "  ${COLOR_GREEN}rm 1 2 3${COLOR_RESET}              - Remove networks by number\n"
        echo
        return
    fi

    # Handle subcommands - first check if we have 'c' for containers, 'v' for volumes, 'n' for networks, 'compose' for compose
    if [ ${#args[@]} -ge 2 ]; then
        case "${args[0]}" in
            "c") # Container operations
                container_subcommand "${args[@]:1}"
                return
                ;;
            "v") # Volume operations
                volume_subcommand "${args[@]:1}"
                return
                ;;
            "n") # Network operations
                network_subcommand "${args[@]:1}"
                return
                ;;
            "compose") # Docker Compose operations
                compose_subcommand "${args[@]:1}"
                return
                ;;
        esac
    fi
    
    # Handle 'd c' as an alias for 'd ls' (list all containers)
    if [ ${#args[@]} -eq 1 ] && [ "${args[0]}" = "c" ]; then
        list_all_containers_scm
        return
    fi
    
    # Handle 'd cd' to get bash shell in container by number
    if [ ${#args[@]} -eq 2 ] && [ "${args[0]}" = "cd" ]; then
        local container_num="${args[1]}"
        if ! [[ "$container_num" =~ ^[0-9]+$ ]]; then
            echo "Error: $container_num is not a valid number"
            return
        fi
        
        # Get current containers
        local output
        output=$(exec_docker_command "ps" "-a" "--format" '{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}')
        local -a lines=()
        while IFS= read -r line; do
            lines+=("$line")
        done <<< "$output"
        local filtered_lines=()
        while IFS= read -r _line; do
            filtered_lines+=("$_line")
        done < <(filter_tabbed_lines 2 "${lines[@]}")
        lines=("${filtered_lines[@]}")
        if [ ${#lines[@]} -lt 1 ]; then
            echo "No containers found"
            return
        fi
        
        # Get container ID
        local container_ids
        container_ids=$(get_container_ids_from_lines "${lines[@]}" "$container_num")
        if [ ${#container_ids} -eq 0 ]; then
            echo "No valid container number found"
            return
        fi
        
        # Execute docker exec bash command, fallback to sh if bash fails
        # First try bash, then fallback to sh
        local shell_options=("bash" "sh")
        local shell_executed=false
        
        for shell in "${shell_options[@]}"; do
            if docker exec -it "$container_ids" "$shell" 2>/dev/null; then
                shell_executed=true
                break  # Success, exit the loop
            fi
            # If this is bash and it failed, try sh next iteration
        done
        
        if [ "$shell_executed" = false ]; then
            echo "Error executing shell in container: both bash and sh failed"
        fi
        return
    fi

    # Handle general Docker commands
    case "${args[0]}" in
        "ps")
            list_running_containers_scm
            ;;
        "ls")
            list_all_containers_scm
            ;;
        "i"|"img"|"images")
            list_images_scm
            ;;
        "v"|"vol"|"volumes")
            list_volumes_scm
            ;;
        "n"|"net"|"networks")
            list_networks_scm
            ;;
        "df")
            exec_docker_command "system" "df"
            ;;
        "prune")
            exec_docker_command "system" "prune" "-f"
            ;;
        "info")
            exec_docker_command "info"
            ;;
        "version")
            exec_docker_command "--version"
            ;;
        "stats")
            exec_docker_command "stats" "--no-stream"
            ;;
        "u") # Docker Compose up
            exec_docker_command "compose" "up"
            ;;
        "d") # Docker Compose down
            exec_docker_command "compose" "down"
            ;;
        "l") # Docker Compose logs
            exec_docker_command "compose" "logs"
            ;;
        "rm") # For images by number
            if [ ${#args[@]} -lt 2 ]; then
                echo "Usage: d rm [number range] (e.g., d rm 1 2 3 or d rm 1-3)"
                return
            fi
            # Get current images
            local output
            output=$(exec_docker_command "images" "--format" '{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}')
            local -a lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done <<< "$output"
            local filtered_lines=()
            while IFS= read -r _line; do
                filtered_lines+=("$_line")
            done < <(filter_tabbed_lines 3 "${lines[@]}")
            lines=("${filtered_lines[@]}")
            if [ ${#lines[@]} -lt 1 ]; then
                echo "No images found"
                return
            fi
            
            # Parse number ranges
            local all_numbers=()
            for ((i=1; i<${#args[@]}; i++)); do
                local numbers
                numbers=$(parse_number_ranges "${args[$i]}")
                all_numbers+=($numbers)
            done
            
            # Get image IDs
            local numbers_str="${all_numbers[*]}"
            local image_ids
            image_ids=$(get_image_ids_from_lines "${lines[@]}" "$numbers_str")
            if [ ${#image_ids} -eq 0 ]; then
                echo "No valid image numbers found"
                return
            fi
            
            # Execute docker rmi command
            exec_docker_command "rmi" $image_ids
            ;;
        *)
            # Stream docker output/errors directly, mirroring Go version
            exec_docker_command_with_error "${args[@]}"
            ;;
    esac
}

# Call main function with all arguments
main "$@"
