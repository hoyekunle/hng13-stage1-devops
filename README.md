# Deployment Script (deploy.sh)

This repository contains a comprehensive Bash script (`deploy.sh`) designed to automate the deployment of Dockerized applications to a remote server. The script handles everything from cloning the Git repository and preparing the remote environment to deploying Docker containers and configuring Nginx as a reverse proxy.

## Features

- **Parameter Collection**: Prompts the user for necessary deployment parameters (Git URL, PAT, branch, SSH details, application port).
- **Git Operations**: Clones the specified Git repository or pulls the latest changes if it already exists, then switches to the target branch.
- **Docker File Verification**: Ensures that either a `Dockerfile` or `docker-compose.yml` exists in the cloned repository.
- **Remote Environment Preparation**: Establishes an SSH connection, updates system packages, and installs Docker, Docker Compose, and Nginx on the remote server (if not already present).
- **Application Deployment**: Transfers project files to the remote server, builds and runs Docker containers using either `Dockerfile` or `docker-compose.yml`, and validates container health.
- **Nginx Reverse Proxy**: Configures Nginx to act as a reverse proxy, forwarding HTTP traffic to the application's internal container port. Includes a placeholder for SSL readiness.
- **Deployment Validation**: Confirms that Docker, the application container, and Nginx are running and correctly proxying traffic.
- **Logging and Error Handling**: Logs all actions (success/failure) to a timestamped log file and includes robust error handling with `trap` functions and meaningful exit codes.
- **Idempotency and Cleanup**: Designed to be safely re-run without breaking existing setups. It gracefully stops/removes old containers before redeployment. An optional `--cleanup` flag is provided to remove all deployed resources.

## TODO

- [x] Add ssh-keyscan command to deploy.sh to automatically add remote host key before SSH connectivity check
- [x] Test the modified script to ensure SSH check passes

## Usage

### Running the Deployment

To run the deployment script, execute it from your local machine:

```bash
./deploy.sh
```

The script will then prompt you for the required parameters:
- Git Repository URL
- Personal Access Token (PAT)
- Branch name (defaults to `main`)
- Remote server SSH Username
- Remote server IP address
- SSH key path (e.g., `~/.ssh/id_rsa`)
- Application internal container port (e.g., `8000`)

### Cleaning Up Resources

To remove all deployed resources from the remote server, use the `--cleanup` flag:

```bash
./deploy.sh --cleanup
```

This will prompt you for minimal parameters required for cleanup:
- Remote server SSH Username
- Remote server IP address
- SSH key path
- Git Repository URL (to determine the project directory name for cleanup)

## Requirements

- **Local Machine**:
    - Bash shell
    - `git`
    - `ssh` client
    - `scp` client
    - `curl` (for remote validation)
- **Remote Server**:
    - Ubuntu/Debian-based Linux distribution (script uses `apt`)
    - SSH access with the provided username and key
    - `sudo` privileges for the specified user (for package installation and service management)
    - Internet connectivity for package downloads

## Important Notes

- Ensure your SSH key has the correct permissions (`chmod 400 ~/.ssh/id_rsa`).
- The PAT should have sufficient permissions to clone the repository.
- The script assumes a single application container per deployment.
- For production environments, consider more robust SSL certificate management (e.g., using Certbot with a proper domain name).
- The script adds the SSH user to the `docker` group. A re-login to the remote server might be required for this change to take effect for manual `docker` commands, but the script's `remote_execute` function handles this by using `sudo` where necessary.
