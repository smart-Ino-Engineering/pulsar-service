#!/bin/bash

set -e  # Exit on any error

echo "=== Apache Pulsar Service Startup Script ==="
echo "Current directory: $(pwd)"
echo "Date: $(date)"
echo ""

# Function to get host IP address (private/internal)
get_host_ip() {
    local ip=""
    
    # Try to get hostname IP first (works on most systems)
    if command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    # If hostname failed, try ip command (Linux)
    if [[ -z "$ip" ]] && command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -n1)
    fi
    
    # If still no IP, try ifconfig (macOS/Linux)
    if [[ -z "$ip" ]] && command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig | grep -E "inet ([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{print $2}' | head -n1)
    fi
    
    # If still no IP, try ipconfig (Windows)
    if [[ -z "$ip" ]] && command -v ipconfig >/dev/null 2>&1; then
        ip=$(ipconfig | grep -E "IPv4.*: ([0-9]{1,3}\.){3}[0-9]{1,3}" | head -n1 | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
    fi
    
    # Fallback to shared.safaripro.net if no IP found
    if [[ -z "$ip" ]]; then
        ip="shared.safaripro.net"
        echo "Warning: Could not detect IP address, using shared.safaripro.net"
    fi
    
    echo "$ip"
}

# Function to get public IP address
get_public_ip() {
    local public_ip=""
    
    echo "Detecting public IP address..."
    # Try multiple public IP services with longer timeout
    public_ip=$(curl -s --connect-timeout 10 --max-time 15 ifconfig.me 2>/dev/null) || 
    public_ip=$(curl -s --connect-timeout 10 --max-time 15 ipinfo.io/ip 2>/dev/null) || 
    public_ip=$(curl -s --connect-timeout 10 --max-time 15 api.ipify.org 2>/dev/null) ||
    public_ip=$(curl -s --connect-timeout 10 --max-time 15 icanhazip.com 2>/dev/null)
    
    # Remove any whitespace
    public_ip=$(echo "$public_ip" | tr -d '[:space:]')
    
    echo "$public_ip"
}

# Function to create directory if it doesn't exist with proper permissions
create_directory() {
    local dir_path="$1"
    
    if [ ! -d "$dir_path" ]; then
        echo "Creating directory: $dir_path"
        mkdir -p "$dir_path"
        echo "✓ Directory created: $dir_path"
    else
        echo "✓ Directory already exists: $dir_path"
    fi
    
    # Create specific subdirectories for ZooKeeper and BookKeeper
    if [[ "$dir_path" == "zookeeper" ]]; then
        mkdir -p "$dir_path/version-2"
        echo "✓ Created ZooKeeper version-2 subdirectory"
    fi
    
    # Set comprehensive permissions for all users (777) to avoid permission issues
    if command -v chmod >/dev/null 2>&1; then
        chmod -R 777 "$dir_path" 2>/dev/null || {
            echo "Warning: Could not set permissions for $dir_path"
        }
        echo "✓ Set permissions (777) for $dir_path"
    fi
    
    # Try to set ownership with various common user IDs
    if command -v chown >/dev/null 2>&1; then
        # Try different user IDs that Pulsar containers might use
        chown -R 10000:10000 "$dir_path" 2>/dev/null || \
        chown -R 1000:1000 "$dir_path" 2>/dev/null || \
        chown -R 999:999 "$dir_path" 2>/dev/null || \
        chown -R $(id -u):$(id -g) "$dir_path" 2>/dev/null || {
            echo "Warning: Could not set ownership for $dir_path (this might be normal on Windows)"
        }
    fi
}

echo "1. Creating required data directories with proper permissions..."

# Create directories with comprehensive permissions
create_directory "data"
create_directory "data/zookeeper"
create_directory "data/bookkeeper"
create_directory "logs"

echo ""
echo "2. Detecting and configuring IP addresses..."

# Get both private and public IPs
PRIVATE_IP=$(get_host_ip)
echo "Detected Private IP: $PRIVATE_IP"

PUBLIC_IP=$(get_public_ip)
if [ -n "$PUBLIC_IP" ] && [[ "$PUBLIC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "Detected Public IP: $PUBLIC_IP"
else
    echo "Could not detect Public IP (using private IP as fallback)"
    PUBLIC_IP=""
fi

# Check existing .env file for manual configuration
EXISTING_BROKER_IP=""
EXISTING_USE_PUBLIC_IP=""
if [ -f ".env" ]; then
    EXISTING_BROKER_IP=$(grep "^PULSAR_BROKER_IP=" .env 2>/dev/null | cut -d'=' -f2)
    EXISTING_USE_PUBLIC_IP=$(grep "^USE_PUBLIC_IP=" .env 2>/dev/null | cut -d'=' -f2)
    
    # Check if there's a manually configured IP that's different from detected ones
    if [ -n "$EXISTING_BROKER_IP" ] && [ "$EXISTING_BROKER_IP" != "$PRIVATE_IP" ] && [ "$EXISTING_BROKER_IP" != "$PUBLIC_IP" ]; then
        echo "Found manually configured IP in .env: $EXISTING_BROKER_IP"
        echo "Do you want to keep this manual configuration? (y/n)"
        read -p "Enter choice [y]: " keep_manual
        keep_manual=${keep_manual:-y}
        
        if [[ "$keep_manual" =~ ^[Yy]$ ]]; then
            SELECTED_IP="$EXISTING_BROKER_IP"
            USE_PUBLIC_IP="$EXISTING_USE_PUBLIC_IP"
            echo "✓ Using manually configured IP: $SELECTED_IP"
        else
            EXISTING_BROKER_IP=""
        fi
    fi
fi

# If no manual configuration or user chose not to keep it, determine IP automatically
if [ -z "$EXISTING_BROKER_IP" ] || [[ ! "$keep_manual" =~ ^[Yy]$ ]]; then
    # Default to public IP if available, otherwise use private IP
    if [ -n "$PUBLIC_IP" ]; then
        SELECTED_IP="$PUBLIC_IP"
        USE_PUBLIC_IP="true"
        echo "✓ Using Public IP for external access: $SELECTED_IP"
    else
        SELECTED_IP="$PRIVATE_IP"
        USE_PUBLIC_IP="false"
        echo "✓ Using Private IP for local access: $SELECTED_IP"
    fi
fi

echo ""
echo "💡 IP Configuration Summary:"
echo "   - Selected IP: $SELECTED_IP"
echo "   - Private IP: $PRIVATE_IP"
if [ -n "$PUBLIC_IP" ]; then
    echo "   - Public IP: $PUBLIC_IP"
    echo "   - Public IP access requires firewall configuration for ports: 6650, 8080, 9527"
fi
echo "   - Use Public IP: $USE_PUBLIC_IP"

# Create or update .env file with proper permissions
echo "PULSAR_BROKER_IP=$BROKER_IP" > .env
echo "PULSAR_CLUSTER_NAME=$CLUSTER_NAME" >> .env
echo "USE_PUBLIC_IP=$USE_PUBLIC_IP_CONFIG" >> .env
echo "PULSAR_MANAGER_PASSWORD=$MANAGER_PASSWORD" >> .env
echo "# Pulsar Configuration" >> .env
echo "# PULSAR_BROKER_IP: IP address that clients will use to connect" >> .env
echo "# Default fallback: shared.safaripro.net" >> .env
echo "# USE_PUBLIC_IP: Set to 'true' for external access, 'false' for local" >> .env
echo "# Public IP requires firewall configuration for ports 6650, 8080, 9527" >> .env

# Set proper permissions for .env file
chmod 644 .env 2>/dev/null || true

echo "✓ Updated .env file with PULSAR_BROKER_IP=$BROKER_IP"

echo ""
echo "3. Loading configuration from .env file or setting defaults..."

# Load existing .env file if it exists
if [ -f ".env" ]; then
    echo "✓ Loading existing .env file"
    set -a  # automatically export all variables
    source .env
    set +a  # stop automatically exporting
else
    echo "✓ No .env file found, will create with detected values"
fi

# Use existing values from .env or detected values, with shared.safaripro.net as ultimate fallback
BROKER_IP="${PULSAR_BROKER_IP:-${SELECTED_IP:-shared.safaripro.net}}"
CLUSTER_NAME="${PULSAR_CLUSTER_NAME:-cluster-a}"
USE_PUBLIC_IP_CONFIG="${USE_PUBLIC_IP:-$USE_PUBLIC_IP}"
MANAGER_PASSWORD="${PULSAR_MANAGER_PASSWORD:-admin123}"

echo "Configuration Summary:"
echo "   - Broker IP: $BROKER_IP"
echo "   - Cluster Name: $CLUSTER_NAME"
echo "   - Use Public IP: $USE_PUBLIC_IP_CONFIG"
echo "   - Manager Password: $MANAGER_PASSWORD"

echo ""
echo "4. Checking Docker and Docker Compose..."

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Error: Docker is not running or not installed."
    echo "Please make sure Docker Desktop is running and try again."
    exit 1
fi
echo "✓ Docker is running"

# Check if Docker Compose is available
if ! docker compose version >/dev/null 2>&1; then
    if ! docker-compose --version >/dev/null 2>&1; then
        echo "❌ Error: Docker Compose is not available."
        exit 1
    else
        DOCKER_COMPOSE_CMD="docker-compose"
    fi
else
    DOCKER_COMPOSE_CMD="docker compose"
fi

echo "✓ Docker Compose is available"

# Export environment variables for docker compose
set -a  # automatically export all variables
source .env
set +a  # stop automatically exporting

echo ""
echo "5. Cleaning up any existing containers..."
$DOCKER_COMPOSE_CMD down --remove-orphans --volumes 2>/dev/null || true

echo ""
echo "6. Pulling latest images..."
$DOCKER_COMPOSE_CMD pull

echo ""
echo "7. Starting Apache Pulsar services..."
echo "This may take a few minutes for the first startup..."

# Start services with proper logging
$DOCKER_COMPOSE_CMD up -d

echo ""
echo "8. Waiting for services to be healthy..."

# Function to check service health
check_service_health() {
    local service_name="$1"
    local max_attempts=60  # 5 minutes max wait time
    local attempt=1
    
    echo -n "Checking $service_name health"
    
    while [ $attempt -le $max_attempts ]; do
        if docker ps --filter "name=$service_name" --filter "health=healthy" --format "{{.Names}}" | grep -q "$service_name"; then
            echo " ✓"
            return 0
        elif docker ps --filter "name=$service_name" --filter "health=unhealthy" --format "{{.Names}}" | grep -q "$service_name"; then
            echo " ❌ (unhealthy)"
            return 1
        fi
        
        echo -n "."
        sleep 5
        ((attempt++))
    done
    
    echo " ⏰ (timeout)"
    return 1
}

# Check ZooKeeper health first
if check_service_health "zookeeper"; then
    echo "ZooKeeper is healthy"
else
    echo "❌ ZooKeeper failed to start properly"
    echo "Checking ZooKeeper logs:"
    docker logs zookeeper --tail 20
    exit 1
fi

# Wait a bit more for other services
sleep 10

echo ""
echo "9. Service Status:"
echo "===================="
$DOCKER_COMPOSE_CMD ps

echo ""
echo "10. Service URLs:"
echo "===================="
echo "Pulsar Broker:          http://$BROKER_IP:8080"
echo "Pulsar Admin REST API:  http://$BROKER_IP:8080/admin/v2"
echo "Pulsar Manager:         http://$BROKER_IP:9527"
echo "Pulsar Service URL:     pulsar://$BROKER_IP:6650"
echo ""
echo "Default Pulsar Manager credentials:"
echo "Username: admin"
echo "Password: admin123"

echo ""
echo "🎉 Apache Pulsar services started successfully!"
echo ""
echo "Configuration Details:"
echo "======================"
echo "Broker IP: $BROKER_IP"
echo "Cluster Name: $CLUSTER_NAME"
echo "IP Type: $([ "$USE_PUBLIC_IP_CONFIG" = "true" ] && echo "Public" || echo "Private")"
echo "Data Directory Permissions: 777 (full access)"
echo "Fallback IP: shared.safaripro.net"
echo ""
echo "Management Commands:"
echo "==================="
echo "Stop services:     $DOCKER_COMPOSE_CMD down"
echo "View logs:         docker logs <service-name> -f"
echo "Check status:      $DOCKER_COMPOSE_CMD ps"
echo "Restart services:  bash run-service.sh"
echo ""
echo "To manually configure IP, edit .env file and set:"
echo "PULSAR_BROKER_IP=<your-desired-ip>  # Default: shared.safaripro.net"
echo "PULSAR_CLUSTER_NAME=<cluster-name>  # Default: cluster-a"
echo "USE_PUBLIC_IP=true|false"
echo "PULSAR_MANAGER_PASSWORD=<password>  # Default: admin123"
