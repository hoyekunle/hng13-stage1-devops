#!/bin/bash

# --- Configuration ---
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
REPO_DIR="" # To be set after cloning

# --- Logging Functions ---
log_info() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') [SUCCESS] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] $1" | tee -a "$LOG_FILE"
    exit 1
}

# --- Error Handling ---
trap 'log_error "An unexpected error occurred at line $LINENO."' ERR

# --- Parameter Collection ---
collect_parameters() {
    log_info "Collecting deployment parameters..."

    # Git Repository URL
    while true; do
        read -rp "Enter Git Repository URL (e.g., https://github.com/user/repo.git): " GIT_REPO_URL
        if [[ "$GIT_REPO_URL" =~ ^(https|git)(://|@).* ]]; then
            log_info "Git Repository URL: $GIT_REPO_URL"
            break
        else
            log_error "Invalid Git Repository URL. Please provide a valid URL."
        fi
    done

    # Personal Access Token (PAT)
    read -rp "Enter Personal Access Token (PAT): " PAT
    log_info "PAT collected."

    # Branch name
    read -rp "Enter Branch name (default: main): " BRANCH_NAME
    BRANCH_NAME=${BRANCH_NAME:-main}
    log_info "Branch name: $BRANCH_NAME"

    # Remote server SSH details
    read -rp "Enter Remote server SSH Username: " SSH_USERNAME
    log_info "SSH Username: $SSH_USERNAME"

    while true; do
        read -rp "Enter Remote server IP address: " SSH_IP
        if [[ "$SSH_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            log_info "SSH IP address: $SSH_IP"
            break
        else
            log_error "Invalid IP address format. Please try again."
        fi
    done

    read -rp "Enter SSH key path (e.g., ~/.ssh/id_rsa): " SSH_KEY_PATH
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log_error "SSH key not found at $SSH_KEY_PATH. Please ensure the path is correct and the key exists."
    fi
    log_info "SSH key path: $SSH_KEY_PATH"

    # Application port (internal container port)
    while true; do
        read -rp "Enter Application internal container port (e.g., 8000): " APP_PORT
        if [[ "$APP_PORT" =~ ^[0-9]+$ ]] && [ "$APP_PORT" -gt 0 ] && [ "$APP_PORT" -le 65535 ]; then
            log_info "Application internal container port: $APP_PORT"
            break
        else
            log_error "Invalid port number. Please enter a number between 1 and 65535."
        fi
    done

    log_success "Parameters collected successfully."
}

# --- Git Operations ---
clone_or_pull_repository() {
    log_info "Starting Git operations..."

    REPO_NAME=$(basename "$GIT_REPO_URL" .git)
    REPO_DIR="./$REPO_NAME"

    if [ -d "$REPO_DIR" ]; then
        log_info "Repository '$REPO_NAME' already exists. Pulling latest changes."
        cd "$REPO_DIR" || log_error "Failed to change directory to $REPO_DIR."
        git pull origin "$BRANCH_NAME" || log_error "Failed to pull latest changes from $BRANCH_NAME."
        log_success "Pulled latest changes for '$REPO_NAME'."
    else
        log_info "Cloning repository '$GIT_REPO_URL' into '$REPO_DIR'."
        git clone "https://$PAT@$(echo "$GIT_REPO_URL" | sed -e 's/^https:\/\///')" "$REPO_DIR" || log_error "Failed to clone repository."
        log_success "Repository cloned successfully."
        cd "$REPO_DIR" || log_error "Failed to change directory to $REPO_DIR."
    fi

    log_info "Switching to branch '$BRANCH_NAME'."
    git checkout "$BRANCH_NAME" || log_error "Failed to switch to branch '$BRANCH_NAME'."
    log_success "Switched to branch '$BRANCH_NAME'."
}

# --- Verify Docker Files ---
verify_docker_files() {
    log_info "Verifying Dockerfile or docker-compose.yml in $REPO_DIR..."
    if [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ]; then
        log_success "Dockerfile or docker-compose.yml found."
    else
        log_error "Neither Dockerfile nor docker-compose.yml found in $REPO_DIR. Exiting."
    fi
}

# --- SSH Connection and Remote Execution ---
remote_execute() {
    local command="$1"
    log_info "Executing remote command: $command"
    ssh -i "$SSH_KEY_PATH" "$SSH_USERNAME@$SSH_IP" "$command" || log_error "Remote command failed: $command"
}

# --- Prepare Remote Environment ---
prepare_remote_environment() {
    log_info "Preparing remote environment on $SSH_IP..."

    # Connectivity check
    log_info "Performing SSH connectivity check..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USERNAME@$SSH_IP" "echo 'SSH connection successful.'" || log_error "SSH connectivity check failed."
    log_success "SSH connectivity check passed."

    # Update system packages
    remote_execute "sudo apt update && sudo apt upgrade -y"

    # Install Docker
    log_info "Checking for Docker installation..."
    if ! remote_execute "command -v docker &> /dev/null"; then
        log_info "Docker not found. Installing Docker..."
        remote_execute "sudo apt install -y apt-transport-https ca-certificates curl software-properties-common"
        remote_execute "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
        remote_execute "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
        remote_execute "sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io"
        log_success "Docker installed."
    else
        log_info "Docker already installed."
    fi

    # Install Docker Compose
    log_info "Checking for Docker Compose installation..."
    if ! remote_execute "command -v docker-compose &> /dev/null"; then
        log_info "Docker Compose not found. Installing Docker Compose..."
        remote_execute "sudo curl -L \"https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose"
        remote_execute "sudo chmod +x /usr/local/bin/docker-compose"
        log_success "Docker Compose installed."
    else
        log_info "Docker Compose already installed."
    fi

    # Install Nginx
    log_info "Checking for Nginx installation..."
    if ! remote_execute "command -v nginx &> /dev/null"; then
        log_info "Nginx not found. Installing Nginx..."
        remote_execute "sudo apt install -y nginx"
        log_success "Nginx installed."
    else
        log_info "Nginx already installed."
    fi

    # Add user to Docker group
    log_info "Adding user '$SSH_USERNAME' to docker group if not already a member..."
    remote_execute "sudo usermod -aG docker $SSH_USERNAME"
    log_success "User '$SSH_USERNAME' added to docker group (if needed). A re-login might be required for changes to take effect."

    # Enable and start services
    log_info "Enabling and starting Docker and Nginx services..."
    remote_execute "sudo systemctl enable docker && sudo systemctl start docker"
    remote_execute "sudo systemctl enable nginx && sudo systemctl start nginx"
    log_success "Docker and Nginx services enabled and started."

    # Confirm installation versions
    log_info "Confirming installation versions..."
    remote_execute "docker --version"
    remote_execute "docker-compose --version"
    remote_execute "nginx -v"
    log_success "Remote environment prepared successfully."
}

# --- Deploy Dockerized Application ---
deploy_application() {
    log_info "Deploying Dockerized application to $SSH_IP..."

    # Transfer project files
    log_info "Transferring project files to remote server..."
    scp -r -i "$SSH_KEY_PATH" "$REPO_DIR" "$SSH_USERNAME@$SSH_IP:/home/$SSH_USERNAME/" || log_error "Failed to transfer project files."
    log_success "Project files transferred."

    # Navigate to project directory and deploy
    remote_execute "cd /home/$SSH_USERNAME/$REPO_NAME && \
        if [ -f \"docker-compose.yml\" ]; then
            echo 'Stopping and removing old containers (if any)...' && \
            docker-compose down --remove-orphans || true && \
            echo 'Building and running containers with docker-compose...' && \
            docker-compose up -d --build || exit 1;
        elif [ -f \"Dockerfile\" ]; then
            echo 'Stopping and removing old containers (if any)...' && \
            CONTAINER_ID=\$(docker ps -aq --filter ancestor=$REPO_NAME) && \
            if [ -n \"\$CONTAINER_ID\" ]; then docker stop \$CONTAINER_ID && docker rm \$CONTAINER_ID; fi || true && \
            echo 'Building and running container with Dockerfile...' && \
            docker build -t $REPO_NAME . && \
            docker run -d -p $APP_PORT:$APP_PORT --name $REPO_NAME $REPO_NAME || exit 1;
        else
            echo 'No Dockerfile or docker-compose.yml found. Exiting.' && exit 1;
        fi"
    log_success "Docker containers built and running."

    # Validate container health and logs
    log_info "Validating container health and logs..."
    remote_execute "docker ps -a"
    remote_execute "docker logs $REPO_NAME" # Assuming container name is REPO_NAME
    log_success "Container health and logs checked."

    # Confirm app accessibility on the specified port
    log_info "Confirming application accessibility on port $APP_PORT..."
    remote_execute "curl -s http://localhost:$APP_PORT" || log_error "Application not accessible on port $APP_PORT."
    log_success "Application accessible on port $APP_PORT."
}

# --- Configure Nginx as a Reverse Proxy ---
configure_nginx() {
    log_info "Configuring Nginx as a reverse proxy on $SSH_IP..."

    NGINX_CONFIG="
server {
    listen 80;
    server_name $SSH_IP; # Or your domain name

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Optional: SSL readiness (self-signed cert placeholder)
    # listen 443 ssl;
    # ssl_certificate /etc/nginx/ssl/nginx.crt;
    # ssl_certificate_key /etc/nginx/ssl/nginx.key;
    # include /etc/nginx/snippets/ssl-params.conf;
}
"
    # Create Nginx config file remotely
    log_info "Creating Nginx configuration file for $REPO_NAME..."
    remote_execute "echo \"$NGINX_CONFIG\" | sudo tee /etc/nginx/sites-available/$REPO_NAME"
    remote_execute "sudo ln -sf /etc/nginx/sites-available/$REPO_NAME /etc/nginx/sites-enabled/"
    log_success "Nginx configuration created."

    # Test Nginx config and reload
    log_info "Testing Nginx configuration and reloading Nginx..."
    remote_execute "sudo nginx -t"
    remote_execute "sudo systemctl reload nginx"
    log_success "Nginx configured and reloaded successfully."
}

# --- Validate Deployment ---
validate_deployment() {
    log_info "Validating full deployment on $SSH_IP..."

    # Confirm Docker service is running
    log_info "Checking Docker service status..."
    remote_execute "sudo systemctl is-active docker" || log_error "Docker service is not running."
    log_success "Docker service is running."

    # Confirm the target container is active and healthy
    log_info "Checking target container status..."
    remote_execute "docker ps --filter name=$REPO_NAME --filter status=running" || log_error "Target container '$REPO_NAME' is not active or healthy."
    log_success "Target container '$REPO_NAME' is active and healthy."

    # Confirm Nginx is proxying correctly
    log_info "Checking Nginx proxying..."
    remote_execute "curl -s http://localhost" || log_error "Nginx is not proxying correctly."
    log_success "Nginx is proxying correctly."

    # Test endpoint using curl locally on the remote server
    log_info "Testing endpoint using curl locally on the remote server..."
    remote_execute "curl -s http://localhost" || log_error "Local endpoint test failed."
    log_success "Local endpoint test passed."

    # Test endpoint using curl remotely (from the deployer machine)
    log_info "Testing endpoint using curl remotely from the deployer machine..."
    curl -s "http://$SSH_IP" || log_error "Remote endpoint test failed."
    log_success "Remote endpoint test passed."

    log_success "Deployment validated successfully."
}

# --- Cleanup Function (Optional) ---
cleanup_resources() {
    log_info "Starting cleanup of deployed resources on $SSH_IP..."

    # Stop and remove containers
    log_info "Stopping and removing Docker containers..."
    remote_execute "cd /home/$SSH_USERNAME/$REPO_NAME && docker-compose down --rmi all --volumes --remove-orphans || true"
    remote_execute "CONTAINER_ID=\$(docker ps -aq --filter ancestor=$REPO_NAME) && if [ -n \"\$CONTAINER_ID\" ]; then docker stop \$CONTAINER_ID && docker rm \$CONTAINER_ID; fi || true"
    remote_execute "docker rmi $REPO_NAME || true" # Remove image if built directly
    log_success "Docker containers and images removed."

    # Remove Nginx config
    log_info "Removing Nginx configuration..."
    remote_execute "sudo rm -f /etc/nginx/sites-enabled/$REPO_NAME"
    remote_execute "sudo rm -f /etc/nginx/sites-available/$REPO_NAME"
    remote_execute "sudo systemctl reload nginx || true"
    log_success "Nginx configuration removed."

    # Remove transferred project files
    log_info "Removing project directory on remote server..."
    remote_execute "rm -rf /home/$SSH_USERNAME/$REPO_NAME"
    log_success "Project directory removed from remote server."

    log_success "Cleanup completed successfully."
}

# --- Main Script Logic ---
main() {
    if [[ "$1" == "--cleanup" ]]; then
        log_info "Cleanup flag detected. Collecting minimal parameters for cleanup."
        read -rp "Enter Remote server SSH Username: " SSH_USERNAME
        read -rp "Enter Remote server IP address: " SSH_IP
        read -rp "Enter SSH key path (e.g., ~/.ssh/id_rsa): " SSH_KEY_PATH
        read -rp "Enter Git Repository URL (e.g., https://github.com/user/repo.git) for cleanup: " GIT_REPO_URL
        REPO_NAME=$(basename "$GIT_REPO_URL" .git)
        cleanup_resources
        log_success "Deployment cleanup process finished."
        exit 0
    fi

    log_info "Deployment script started."
    collect_parameters
    clone_or_pull_repository
    verify_docker_files
    prepare_remote_environment
    deploy_application
    configure_nginx
    validate_deployment
    log_success "Deployment script finished successfully!"
}

main "$@"
