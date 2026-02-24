#!/bin/bash
# =============================================================================
# Environment Setup Script
# Tự động tạo .env.local cho tất cả services từ shared credentials
# =============================================================================

set -e

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CREDENTIALS_FILE="${1:-$WORKSPACE_ROOT/.env.credentials}"

echo -e "${COLOR_GREEN}=== Environment Setup Tool ===${COLOR_RESET}"
echo ""

# Check if credentials file exists
if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo -e "${COLOR_RED}[ERROR] Credentials file not found: $CREDENTIALS_FILE${COLOR_RESET}"
    echo ""
    echo "Vui lòng:"
    echo "  1. Liên hệ Tech Lead để lấy file 'shared-credentials.env'"
    echo "  2. Copy file đó vào workspace root và đổi tên thành '.env.credentials'"
    echo "  3. Chạy lại: ./scripts/setup-env.sh"
    echo ""
    echo "Hoặc chỉ định đường dẫn: ./scripts/setup-env.sh /path/to/credentials.env"
    exit 1
fi

echo -e "${COLOR_GREEN}✓ Found credentials file: $CREDENTIALS_FILE${COLOR_RESET}"
echo ""

# Source credentials
source "$CREDENTIALS_FILE"

# Required variables check
REQUIRED_VARS=(
    "YUGABYTE_PASSWORD"
    "MONGODB_PASSWORD"
    "REDIS_PASSWORD"
    "CLICKHOUSE_PASSWORD"
    "JWT_SECRET"
    "INTERNAL_JWT_SECRET"
)

echo "Validating credentials..."
MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${COLOR_RED}[ERROR] Missing required variables in credentials file:${COLOR_RESET}"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    exit 1
fi

echo -e "${COLOR_GREEN}✓ All required credentials present${COLOR_RESET}"
echo ""

# Function to setup service
setup_service() {
    local service_path=$1
    local service_name=$(basename "$service_path")

    if [ ! -f "$service_path/.env.example" ]; then
        echo -e "${COLOR_YELLOW}⚠ Skipping $service_name (no .env.example found)${COLOR_RESET}"
        return
    fi

    echo -e "Processing ${COLOR_GREEN}$service_name${COLOR_RESET}..."

    # Copy example to local
    cp "$service_path/.env.example" "$service_path/.env.local"

    # Replace placeholders
    sed -i "s|your_yugabyte_password_here|$YUGABYTE_PASSWORD|g" "$service_path/.env.local"
    sed -i "s|your_password@192.168.1.207:27017|$MONGODB_PASSWORD@192.168.1.207:27017|g" "$service_path/.env.local"
    sed -i "s|your_redis_password_here|$REDIS_PASSWORD|g" "$service_path/.env.local"
    sed -i "s|your_clickhouse_password_here|$CLICKHOUSE_PASSWORD|g" "$service_path/.env.local"
    sed -i "s|generate_random_256bit_key_see_docs|$JWT_SECRET|g" "$service_path/.env.local"
    sed -i "s|generate_different_random_key_see_docs|$INTERNAL_JWT_SECRET|g" "$service_path/.env.local"

    # Replace RabbitMQ if present
    if [ ! -z "$RABBITMQ_PASSWORD" ]; then
        sed -i "s|your_password@192.168.1.207:5672|$RABBITMQ_PASSWORD@192.168.1.207:5672|g" "$service_path/.env.local"
    fi

    # Construct consolidated YUGABYTE_URL from credentials and legacy vars (if templates expect it)
    if [ -n "$YUGABYTE_HOST" ] || [ -n "$YUGABYTE_URL" ]; then
        # Prefer an explicit YUGABYTE_URL from credentials; otherwise build from parts
        if [ -n "$YUGABYTE_URL" ]; then
            YUGABYTE_URL_CONSTRUCT="$YUGABYTE_URL"
        else
            # Fallback to component vars; assume sslmode if provided
            YUGABYTE_URL_CONSTRUCT="postgresql://${YUGABYTE_USER}:${YUGABYTE_PASSWORD}@${YUGABYTE_HOST}:${YUGABYTE_PORT}/${YUGABYTE_DATABASE}?sslmode=${YUGABYTE_SSLMODE}"
        fi
        # Replace or append YUGABYTE_URL in .env.local
        if grep -q "^YUGABYTE_URL=" "$service_path/.env.local"; then
            sed -i "s|^YUGABYTE_URL=.*|YUGABYTE_URL=${YUGABYTE_URL_CONSTRUCT}|g" "$service_path/.env.local"
        else
            echo "YUGABYTE_URL=${YUGABYTE_URL_CONSTRUCT}" >> "$service_path/.env.local"
        fi
    fi

    echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} Created $service_path/.env.local"
}

# Setup all Go services
echo "=== Setting up Go Services ==="
for service_dir in "$WORKSPACE_ROOT"/go/apps/*; do
    if [ -d "$service_dir" ]; then
        setup_service "$service_dir"
    fi
done

echo ""
echo -e "${COLOR_GREEN}=== Setup Complete! ===${COLOR_RESET}"
echo ""
echo "Next steps:"
echo "  1. Verify .env.local files: ls -la go/apps/*/.env.local"
echo "  2. Test connection: cd go/apps/authentication && go run cmd/main.go"
echo "  3. Start services: make run"
echo ""
echo -e "${COLOR_YELLOW}⚠ Remember: NEVER commit .env.local files!${COLOR_RESET}"
