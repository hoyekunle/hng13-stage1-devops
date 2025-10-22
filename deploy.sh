#!/bin/bash

# ==============================
#   Automated Docker Deployment
# ==============================
# Author: Hassan Oyekunle
# Date: 2025-10-22
# Description: Deploys a Dockerized app to a remote server (Ubuntu)
# ==============================================

LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
REPO_DIR=""

# --- Logging Utilities ---
log_info()    { echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_FILE"; }
log_success() { echo "$(date +'%Y-%m-%d %H:%M:%S') [SUCCESS] $1" | tee -a "$LOG_FILE"; }
log_error()   { echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] $1" | tee -a "$LOG_FILE"; exit 1; }

trap 'log_error "Unexpected error occurred at line $LINENO."' ERR

# --- Remote Execution ---
remote_execute() {
    local command="$1"
    local allow_failure="${2:-false}"

    log_info "Executing remote command: $command"
    if ! ssh -i "$SSH_KEY_PATH" "$SSH_USERNAME@$SSH_IP" "$command"; then
        if [[ "$allow_failure" == "true" ]]; then
            log_info "Remote command failed (non-fatal): $command"
            return 1
        else
            log_error "Remote command failed: $command"
        fi
    fi
}

# --- Parameter Input ---
collect_parameters() {
    log_info "Collecting deployment parameters..."

    while true; do
        read -rp "Enter Git Repository URL: " GIT_REPO_URL
        [[ "$GIT_REPO_URL" =~ ^(https|git)(://|@).* ]] && break
        log_info "Invalid repository URL format. Try again."
    done

    read -rp "Enter Personal Access Token (PAT): " PAT
    read -rp "Enter Branch name (default: main): " BRANCH_NAME
    BRANCH_NAME=${BRANCH_NAME:-main}

    read -rp "Enter SSH Username: " SSH_USERNAME
    read -rp "Enter SSH IP Address: " SSH_IP
    read -rp "Enter SSH Key Path (e.g., ~/.ssh/id_rsa): " SSH_KEY_PATH
    read -rp "Enter Application Port (e.g., 8000): " APP_PORT

    [[ ! -f "$SSH_KEY_PATH" ]] && log_error "SSH key not found at $SSH_KEY_PATH"
    chmod 600 "$SSH_KEY_PATH"

    log_success "Parameters collected successfully."
}

# --- Git Operations ---
clone_or_pull_repository() {
    log_info "Cloning or pulling Git repository..."
    REPO_NAME=$(basename "$GIT_REPO_URL" .git)
    REPO_DIR="./$REPO_NAME"

    if [[ -d "$REPO_DIR" ]]; then
        cd "$REPO_DIR" || log_error "Cannot enter $REPO_DIR"
        git pull origin "$BRANCH_NAME" || log_error "Failed to pull latest changes"
        cd - || log_error "Failed to return to original directory."
    else
        git clone "https://$PAT@${GIT_REPO_URL#https://}" "$REPO_DIR" || log_error "Git clone failed"
    fi

    cd "$REPO_DIR" || log_error "Cannot enter $REPO_DIR"
    git checkout "$BRANCH_NAME" || log_error "Cannot checkout branch $BRANCH_NAME"
    cd - || log_error "Failed to return to original directory."
    log_success "Repository ready on branch '$BRANCH_NAME'."
}

# --- Verify Docker Files ---
verify_docker_files() {
    log_info "Checking for Dockerfile or docker-compose.yml..."
    [[ -f Dockerfile || -f docker-compose.yml ]] || log_error "No Dockerfile or docker-compose.yml found."
    log_success "Docker configuration verified."
}

# --- Prepare Remote Server ---
prepare_remote_environment() {
    log_info "Preparing remote environment on $SSH_IP..."

    ssh-keyscan -H "$SSH_IP" >> ~/.ssh/known_hosts 2>/dev/null || true

    log_info "Testing SSH connection..."
    ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USERNAME@$SSH_IP" "exit 0" \
        || log_error "SSH connection failed. Check username, key, or firewall."

    log_info "Updating system packages..."
    remote_execute "sudo apt-get update -y && sudo apt-get upgrade -y"

    # --- Docker Installation ---
    log_info "Checking Docker installation..."
    if ! remote_execute "command -v docker > /dev/null 2>&1" true; then
        log_info "Installing Docker..."
        remote_execute "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release"
        remote_execute "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg"
        remote_execute "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list"
        remote_execute "sudo apt-get update -y && sudo apt-get install -y docker-ce docker-ce-cli containerd.io"
        log_success "Docker installed successfully."
    else
        log_info "Docker already installed."
    fi

    # --- Docker Compose ---
    log_info "Checking Docker Compose..."
    if ! remote_execute "command -v docker-compose > /dev/null 2>&1" true; then
        log_info "Installing Docker Compose..."
        remote_execute "sudo curl -L https://github.com/docker/compose/releases/download/1.29.2/docker-compose-\$(uname -s)-\$(uname -m) -o /usr/local/bin/docker-compose"
        remote_execute "sudo chmod +x /usr/local/bin/docker-compose"
        remote_execute "docker-compose --version"
        log_success "Docker Compose installed successfully."
    else
    log_info "Docker Compose already installed."
    fi


    # --- Nginx Installation ---
    log_info "Checking Nginx..."
    if ! remote_execute "command -v nginx > /dev/null 2>&1" true; then
        log_info "Installing Nginx..."
        remote_execute "sudo apt-get install -y nginx"
        log_success "Nginx installed."
    else
        log_info "Nginx already installed."
    fi

    remote_execute "sudo usermod -aG docker $SSH_USERNAME"
    remote_execute "sudo systemctl enable docker && sudo systemctl start docker"
    remote_execute "sudo systemctl enable nginx && sudo systemctl start nginx"
    log_success "Remote environment prepared successfully."
}

# --- Deploy Application ---
deploy_application() {
    log_info "Deploying application..."
    scp -r -i "$SSH_KEY_PATH" "$REPO_DIR" "$SSH_USERNAME@$SSH_IP:/home/$SSH_USERNAME/" \
        || log_error "File transfer failed."

    remote_execute "
        cd /home/$SSH_USERNAME/$REPO_NAME &&
        if [ -f docker-compose.yml ]; then
            docker-compose down --remove-orphans || true
            docker-compose up -d --build
        elif [ -f Dockerfile ]; then
            docker stop $REPO_NAME || true
            docker rm $REPO_NAME || true
            docker build -t $REPO_NAME .
            docker run -d -p $APP_PORT:$APP_PORT --name $REPO_NAME $REPO_NAME
        else
            exit 1
        fi
    "
    log_success "Application deployed successfully."
}

# --- Configure Nginx ---
configure_nginx() {
    log_info "Configuring Nginx reverse proxy..."
    NGINX_CONFIG="
server {
    listen 80;
    server_name $SSH_IP;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
"
    remote_execute "echo \"$NGINX_CONFIG\" | sudo tee /etc/nginx/sites-available/$REPO_NAME"
    remote_execute "sudo ln -sf /etc/nginx/sites-available/$REPO_NAME /etc/nginx/sites-enabled/"
    remote_execute "sudo nginx -t && sudo systemctl reload nginx"
    log_success "Nginx configured successfully."
}

# --- Validate Deployment ---
validate_deployment() {
    log_info "Validating deployment..."
    remote_execute "sudo systemctl is-active docker"
    remote_execute "docker ps --filter name=$REPO_NAME"
    remote_execute "curl -s http://localhost:$APP_PORT"
    log_success "Deployment validated and app is accessible on port $APP_PORT."
}

# --- Cleanup ---
cleanup_resources() {
    log_info "Cleaning up resources on remote host..."
    remote_execute "cd /home/$SSH_USERNAME/$REPO_NAME && docker-compose down --remove-orphans || true"
    remote_execute "docker rm -f $REPO_NAME || true"
    remote_execute "sudo rm -f /etc/nginx/sites-{available,enabled}/$REPO_NAME"
    remote_execute "sudo systemctl reload nginx"
    remote_execute "rm -rf /home/$SSH_USERNAME/$REPO_NAME"
    log_success "Cleanup completed successfully."
}

# --- Main ---
main() {
    if [[ "$1" == "--cleanup" ]]; then
        read -rp "SSH Username: " SSH_USERNAME
        read -rp "SSH IP: " SSH_IP
        read -rp "SSH Key Path: " SSH_KEY_PATH
        read -rp "Git Repo URL: " GIT_REPO_URL
        REPO_NAME=$(basename "$GIT_REPO_URL" .git)
        cleanup_resources
        exit 0
    fi

    log_info "Starting deployment..."
    collect_parameters
    clone_or_pull_repository
    verify_docker_files
    prepare_remote_environment
    deploy_application
    configure_nginx
    validate_deployment
    log_success "🎉 Deployment completed successfully!"
}

main "$@"
