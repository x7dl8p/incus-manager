#!/bin/bash

# Fetch all available Incus container names
get_containers() {
    incus list --format csv -c n
}

function select_container() {
    local prompt_msg="$1"
    local containers=($(get_containers))

    if [ ${#containers[@]} -eq 0 ]; then
        echo "No Incus containers found."
        return 1
    fi

    echo "$prompt_msg"
    for i in "${!containers[@]}"; do
        echo "$((i+1))) ${containers[$i]}"
    done
    echo "c) Cancel"

    read -p "Select a container: " selection

    if [[ "$selection" == "c" || "$selection" == "C" ]]; then
        return 1
    fi

    # Check if input is a valid number within array bounds
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#containers[@]} ]; then
        SELECTED_CONTAINER="${containers[$((selection-1))]}"
        return 0
    else
        echo "Invalid selection."
        return 1
    fi
}

function remove_ssh_config() {
    local target=$1
    if grep -q "^Host $target$" ~/.ssh/config 2>/dev/null; then
        echo "Removing SSH config entry for $target..."
        awk -v target="$target" '
            /^Host / {
                if ($2 == target) { skip=1 } else { skip=0 }
            }
            !skip { print $0 }
        ' ~/.ssh/config > ~/.ssh/config.tmp
        mv ~/.ssh/config.tmp ~/.ssh/config
        echo "SSH config removed successfully."
    else
        echo "No SSH config entry found for $target."
    fi
}

function setup_container() {
    if ! select_container "Select a container to Setup for VS Code SSH:"; then
        return
    fi

    local container_name="$SELECTED_CONTAINER"

    echo "Checking if container '$container_name' exists..."
    if ! incus info "$container_name" &>/dev/null; then
        echo "Error: Container '$container_name' does not exist."
        return 1
    fi

    echo "Starting container '$container_name' (if not already running)..."
    incus start "$container_name" 2>/dev/null

    echo "Waiting for container to get an IPv4 address..."
    local ip_address=""
    for i in {1..30}; do
        ip_address=$(incus list "$container_name" -c 4 --format csv | awk '{print $1}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
        if [ -n "$ip_address" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$ip_address" ]; then
        echo "Error: Could not get IPv4 address for container '$container_name'."
        return 1
    fi
    echo "Container IP: $ip_address"

    echo "Installing openssh-server in container..."
    incus exec "$container_name" -- apt-get update
    incus exec "$container_name" -- apt-get install -y openssh-server
    incus exec "$container_name" -- systemctl enable --now ssh

    echo "Setting up SSH keys..."
    incus exec "$container_name" -- mkdir -p /root/.ssh
    incus exec "$container_name" -- chmod 700 /root/.ssh

    if [ ! -f ~/.ssh/id_rsa ]; then
        echo "Generating local SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    fi

    echo "Copying public key to container..."
    cat ~/.ssh/id_rsa.pub | incus exec "$container_name" -- sh -c 'cat >> /root/.ssh/authorized_keys'
    incus exec "$container_name" -- chmod 600 /root/.ssh/authorized_keys

    echo "Adding SSH config entry for VSCode..."
    mkdir -p ~/.ssh

    # Remove old entry if exists to prevent conflicts
    remove_ssh_config "$container_name"

    # Append the new configuration
    echo -e "\nHost $container_name\n  HostName $ip_address\n  User root\n  IdentityFile ~/.ssh/id_rsa\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n" >> ~/.ssh/config
    chmod 600 ~/.ssh/config

    echo "=========================================================="
    echo "Setup Complete! You can now connect in VS Code Remote-SSH to: $container_name"
    echo "=========================================================="
    read -p "Press Enter to continue..."
}

function delete_container() {
    if ! select_container "Select a container to Delete:"; then
        return
    fi

    local container_name="$SELECTED_CONTAINER"

    # 1. Ask if user wants to delete the actual container
    read -p "Do you want to permanently delete the Incus container '$container_name'? (y/N): " confirm_delete

    # 2. Remove SSH Configuration
    remove_ssh_config "$container_name"

    if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
        echo "Force deleting container '$container_name'..."
        if incus info "$container_name" &>/dev/null; then
            incus delete "$container_name" --force
            echo "Container '$container_name' has been deleted."
        else
            echo "Container '$container_name' does not exist in Incus, skipping deletion."
        fi
    else
        echo "Container deletion skipped."
    fi
    echo "=========================================================="
    read -p "Press Enter to continue..."
}

function show_menu() {
    clear
    echo "========================================"
    echo "       Incus Container Manager          "
    echo "========================================"
    echo "1) Setup a container for VS Code SSH"
    echo "2) Delete a container (and SSH config)"
    echo "3) Exit"
    echo "========================================"
    read -p "Choose an option (1/2/3): " choice
    return $choice
}

while true; do
    show_menu
    choice=$?

    case $choice in
        1)
            setup_container
            ;;
        2)
            delete_container
            ;;
        3)
            echo "Exiting."
            exit 0
            ;;
        *)
            echo "Invalid option. Please choose 1, 2, or 3."
            sleep 2
            ;;
    esac
done