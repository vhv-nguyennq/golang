#!/bin/bash
# ==============================================================================
# PROTO GENERATION V2 - CENTRALIZED PROTO DIRECTORY (Directory Scan Mode)
# ==============================================================================
# Usage:
#   ./scripts/generate-proto-v2.sh <service_key>     # Generate for one service
#   ./scripts/generate-proto-v2.sh --gateway-only    # Generate ALL protos for gateway only
#   ./scripts/generate-proto-v2.sh --all             # Generate ALL protos for gateway + all services
#
# Config file: resource/config/grpc_services.yaml
# Proto files location: resource/proto/{service}/**/*.proto
# Generated files:
#   - Gateway: go/apps/gateway/internal/pb/{service}/v{X}/
#   - Service: go/apps/{service}/internal/pb/v{X}/
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$ROOT_DIR/resource/config/grpc_services.yaml"
PROTO_ROOT="$ROOT_DIR/resource/proto"
GATEWAY_PB_DIR="$ROOT_DIR/go/apps/gateway/internal/pb"

# Declare associative arrays for service configuration
declare -A APP_PATHS
declare -A PROTO_DIRS
ALL_SERVICES=""

load_services_from_yaml() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Config file not found: $CONFIG_FILE"
        echo "Expected: $CONFIG_FILE"
        exit 1
    fi

    ALL_SERVICES=""
    local current_key=""

    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r')
        line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

        if [[ $line == *"service_key:"* ]]; then
            current_key=$(echo "$line" | sed 's/.*service_key:[[:space:]]*//' | sed 's/#.*//')
            current_key=$(echo "$current_key" | sed 's/[[:space:]]*$//')
            ALL_SERVICES="$ALL_SERVICES $current_key"
        fi

        if [[ $line == "app_path:"* ]] && [ -n "$current_key" ]; then
            local app_path=$(echo "$line" | sed 's/app_path:[[:space:]]*//' | sed 's/#.*//' | sed 's/[[:space:]]*$//')
            APP_PATHS["$current_key"]="$app_path"
        fi

        if [[ $line == "proto_dir:"* ]] && [ -n "$current_key" ]; then
            local proto_dir=$(echo "$line" | sed 's/proto_dir:[[:space:]]*//' | sed 's/#.*//' | sed 's/[[:space:]]*$//')
            PROTO_DIRS["$current_key"]="$proto_dir"
        fi
    done < "$CONFIG_FILE"

    ALL_SERVICES=$(echo "$ALL_SERVICES" | sed 's/^[[:space:]]*//')
}

usage() {
    echo "Usage:"
    echo "  $0 <service_key>      Generate for one service + gateway"
    echo "  $0 --gateway-only     Generate ALL protos for gateway only"
    echo "  $0 --all              Generate ALL protos for gateway + services"
    echo ""
    echo "Available services: $ALL_SERVICES"
}

check_protoc() {
    # Ensure Go bin is on PATH so protoc plugins are discoverable
    if command -v go >/dev/null 2>&1; then
        export PATH="$PATH:$(go env GOPATH)/bin"
    fi

    if ! command -v protoc >/dev/null 2>&1; then
        echo "Error: protoc not found. Please install Protocol Buffers compiler."
        exit 1
    fi

    local missing=()
    for plugin in protoc-gen-go protoc-gen-go-grpc protoc-gen-grpc-gateway; do
        if ! command -v "$plugin" >/dev/null 2>&1; then
            missing+=("$plugin")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "⚠ Warning: missing protoc plugins: ${missing[*]}"
        echo "Installing missing plugins..."

        go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
        go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
        go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@latest

        # Refresh PATH to include newly installed plugins
        GOPATH=$(go env GOPATH)
        export PATH="$GOPATH/bin:$PATH"

        # Verify plugins are now available by checking file existence
        local still_missing=()
        for plugin in protoc-gen-go protoc-gen-go-grpc protoc-gen-grpc-gateway; do
            # Check if the plugin exists in GOPATH/bin (with .exe for Windows)
            if [ ! -f "$GOPATH/bin/$plugin" ] && [ ! -f "$GOPATH/bin/$plugin.exe" ]; then
                still_missing+=("$plugin")
            fi
        done

        if [ ${#still_missing[@]} -gt 0 ]; then
            echo "Error: failed to install plugins: ${still_missing[*]}"
            exit 1
        fi

        echo "✓ All protoc plugins installed successfully"
    fi
}

generate_gateway() {
    local svc=$1
    local proto_dir=${PROTO_DIRS[$svc]:-$svc}

    # Skip if proto_dir is empty (like gateway)
    if [ -z "$proto_dir" ] || [ "$proto_dir" = '""' ]; then
        echo "  ⚠ Skipped $svc (no proto_dir configured)"
        return 0
    fi

    local proto_path="$PROTO_ROOT/$proto_dir"

    if [ ! -d "$proto_path" ]; then
        echo "  ⚠ Skipped $svc (proto dir not found: $proto_path)"
        return 0
    fi

    local proto_files
    proto_files=$(find "$proto_path" -name "*.proto" 2>/dev/null)
    if [ -z "$proto_files" ]; then
        echo "  ⚠ Skipped $svc (no .proto files found)"
        return
    fi

    mkdir -p "$GATEWAY_PB_DIR"
    local count=0
    local failed=0
    while IFS= read -r proto_file; do
        local rel_path="${proto_file#$PROTO_ROOT/}"
        echo "    Compiling: $rel_path" >&2
        if protoc \
            --go_out="$GATEWAY_PB_DIR" \
            --go_opt=paths=source_relative \
            --go-grpc_out="$GATEWAY_PB_DIR" \
            --go-grpc_opt=paths=source_relative \
            --grpc-gateway_out="$GATEWAY_PB_DIR" \
            --grpc-gateway_opt=paths=source_relative \
            --grpc-gateway_opt=generate_unbound_methods=true \
            -I"$PROTO_ROOT" \
            "$rel_path"; then
            ((count++))
        else
            echo "  ✗ Failed to generate gateway for: $rel_path" >&2
            failed=$((failed + 1))
        fi
    done <<< "$proto_files"

    if [ $failed -gt 0 ]; then
        echo "  ✗ Gateway: $svc ($count succeeded, $failed failed)"
        return 1
    fi

    echo "  ✓ Gateway: $svc ($count file(s))"
}

generate_service() {
    local svc=$1
    local app_path=${APP_PATHS[$svc]}
    local proto_dir=${PROTO_DIRS[$svc]:-$svc}

    # Skip if proto_dir is empty (like gateway)
    if [ -z "$proto_dir" ] || [ "$proto_dir" = '""' ]; then
        echo "  ⚠ Skipped $svc service (no proto_dir configured)"
        return 0
    fi

    if [ -z "$app_path" ] || [ ! -d "$ROOT_DIR/$app_path" ]; then
        echo "  ⚠ Skipped $svc service (app not found)"
        return 0
    fi

    local proto_path="$PROTO_ROOT/$proto_dir"
    if [ ! -d "$proto_path" ]; then
        echo "  ⚠ Skipped $svc service (proto dir not found: $proto_path)"
        return
    fi

    local proto_files
    proto_files=$(find "$proto_path" -name "*.proto" 2>/dev/null)
    if [ -z "$proto_files" ]; then
        echo "  ⚠ Skipped $svc service (no .proto files found)"
        return
    fi

    local service_pb_dir="$ROOT_DIR/$app_path/internal/pb"
    mkdir -p "$service_pb_dir"

    local count=0
    local failed=0
    while IFS= read -r proto_file; do
        local rel_path="${proto_file#$PROTO_ROOT/}"
        echo "    Compiling: $rel_path" >&2
        if protoc \
            --go_out="$service_pb_dir" \
            --go_opt=paths=source_relative \
            --go-grpc_out="$service_pb_dir" \
            --go-grpc_opt=paths=source_relative \
            -I"$PROTO_ROOT" \
            "$rel_path"; then
            ((count++))
        else
            echo "  ✗ Failed to generate service for: $rel_path" >&2
            failed=$((failed + 1))
        fi
    done <<< "$proto_files"

    if [ -d "$service_pb_dir/$proto_dir" ]; then
        for version_dir in "$service_pb_dir/$proto_dir"/v*; do
            if [ -d "$version_dir" ]; then
                local version=$(basename "$version_dir")
                mkdir -p "$service_pb_dir/$version"
                mv "$version_dir/"* "$service_pb_dir/$version/" 2>/dev/null || true
            fi
        done
        rm -rf "$service_pb_dir/$proto_dir"
    fi

    if [ $failed -gt 0 ]; then
        echo "  ✗ Service: $app_path/internal/pb ($count succeeded, $failed failed)"
        return 1
    fi

    echo "  ✓ Service: $app_path/internal/pb ($count file(s))"
}

generate_all_gateway() {
    check_protoc
    echo "=========================================="
    echo "Generating ALL protos for Gateway"
    echo "=========================================="
    local total_failed=0
    for svc in $ALL_SERVICES; do
        if ! generate_gateway "$svc"; then
            total_failed=$((total_failed + 1))
        fi
    done
    echo "=========================================="
    if [ $total_failed -gt 0 ]; then
        echo "⚠ Gateway proto generation completed with $total_failed error(s)"
        return 1
    fi
    echo "✓ Gateway proto generation complete"
    echo "=========================================="
}

generate_all_services() {
    check_protoc
    echo "=========================================="
    echo "Generating ALL protos (Gateway + Services)"
    echo "=========================================="
    echo "[Gateway]"
    local gw_failed=0
    for svc in $ALL_SERVICES; do
        if ! generate_gateway "$svc"; then
            gw_failed=$((gw_failed + 1))
        fi
    done
    echo ""
    echo "[Services]"
    local svc_failed=0
    for svc in $ALL_SERVICES; do
        if ! generate_service "$svc"; then
            svc_failed=$((svc_failed + 1))
        fi
    done
    echo "=========================================="
    local total_failed=$((gw_failed + svc_failed))
    if [ $total_failed -gt 0 ]; then
        echo "⚠ Proto generation completed with $total_failed error(s)"
        return 1
    fi
    echo "✓ All proto generation complete"
    echo "=========================================="
}

load_services_from_yaml

if [ "$#" -eq 0 ]; then
    usage
    exit 1
fi

case "$1" in
    --gateway-only)
        generate_all_gateway
        exit 0
        ;;
    --all)
        generate_all_services
        exit 0
        ;;
    *)
        SERVICE_KEY=$1
        APP_PATH=${APP_PATHS[$SERVICE_KEY]:-}
        PROTO_DIR=${PROTO_DIRS[$SERVICE_KEY]:-$SERVICE_KEY}
        PROTO_PATH="$PROTO_ROOT/$PROTO_DIR"

        if [ -z "$APP_PATH" ]; then
            echo "Error: Unknown service key '$SERVICE_KEY'"
            usage
            exit 1
        fi

        if [ ! -d "$ROOT_DIR/$APP_PATH" ]; then
            echo "Error: App path not found for '$SERVICE_KEY': $ROOT_DIR/$APP_PATH"
            echo "Please update resource/config/grpc_services.yaml so app_path points to an existing service directory."
            exit 1
        fi

        if [ ! -d "$PROTO_PATH" ]; then
            echo "Error: Proto directory not found: $PROTO_PATH"
            exit 1
        fi

        PROTO_FILES=$(find "$PROTO_PATH" -name "*.proto" 2>/dev/null)
        if [ -z "$PROTO_FILES" ]; then
            echo "Error: No .proto files found in $PROTO_PATH"
            exit 1
        fi

        check_protoc
        echo "=========================================="
        echo "Proto Generation V2 (Directory Scan Mode)"
        echo "=========================================="
        echo "Service: $SERVICE_KEY"
        echo "Proto root: $PROTO_ROOT"
        echo "Proto directory: $PROTO_DIR"
        echo ""
        echo "Found proto files:"
        while IFS= read -r proto_file; do
            echo "  - ${proto_file#$PROTO_ROOT/}"
        done <<< "$PROTO_FILES"
        echo ""

        echo "[Step 1] Generating gateway pb files..."
        if ! generate_gateway "$SERVICE_KEY"; then
            echo "Error: Gateway generation failed"
            exit 1
        fi
        echo ""
        echo "[Step 2] Generating service pb files..."
        if ! generate_service "$SERVICE_KEY"; then
            echo "Error: Service generation failed"
            exit 1
        fi

        echo ""
        echo "=========================================="
        echo "✓ Proto generation complete for $SERVICE_KEY"
        echo "=========================================="
        echo "Import paths:"
        echo "  Gateway: gateway/internal/pb/$PROTO_DIR/"
        echo "  Service: $SERVICE_KEY/internal/pb/"
        ;;
 esac
