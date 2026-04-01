# Incus VS Code SSH Manager

An interactive CLI tool to manage your Incus containers and set them up for VS Code Remote-SSH access instantly.

## Quick Setup (Curl)
You can directly run the CLI using this one-liner curl command:
```bash
curl -fsSL https://raw.githubusercontent.com/x7dl8p/incus-manager/refs/heads/main/incus-manager.sh | bash
```

### Options:
1. **Setup a container for VS Code SSH**:
   Pulls a list of your existing Incus containers, starts the selected one if it's not running, installs OpenSSH server, generates/copies SSH keys, and securely writes an entry directly to your `~/.ssh/config` file without causing IP conflicts.

2. **Delete a container**:
   Pulls a list of your existing containers, cleans up the associated VS Code `~/.ssh/config` block, and prompts you to safely force-delete the Incus container.

3. **Exit**:
   Closes the application.
