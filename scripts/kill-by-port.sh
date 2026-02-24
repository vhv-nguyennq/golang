#!/bin/bash
# ==============================================================================
# KILL PROCESS BY PORT - Safe Process Termination
# ==============================================================================
# Usage:
#   ./scripts/kill-by-port.sh <port>
#   ./scripts/kill-by-port.sh 50051
#
# Description:
#   Kills process listening on specific port (Windows compatible)
#   Uses netstat to find PID, then taskkill to terminate
# ==============================================================================

set -e

PORT=$1

if [ -z "$PORT" ]; then
    echo "Error: Port number required"
    echo "Usage: $0 <port>"
    exit 1
fi

# Validate port number
if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid port number: $PORT"
    exit 1
fi

echo "Looking for process using port $PORT..."

# Windows: Use netstat to find PID
# Format: TCP    0.0.0.0:50051    0.0.0.0:0    LISTENING    12345
# We need to match exact port with space or colon before it
PID=$(netstat -ano | grep "LISTENING" | grep ":$PORT " | awk '{print $5}' | head -n 1)

# Debug: Show what we found
# echo "DEBUG: netstat output:"
# netstat -ano | grep "LISTENING" | grep ":$PORT "

if [ -z "$PID" ]; then
    echo "  ℹ No process found listening on port $PORT"
    exit 0
fi

# Validate PID
if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
    echo "  ℹ No valid PID found for port $PORT"
    exit 0
fi

# Get process name for confirmation
PROCESS_NAME=$(tasklist //FI "PID eq $PID" //FO CSV //NH 2>/dev/null | cut -d',' -f1 | tr -d '"' || echo "Unknown")

echo "  Found: $PROCESS_NAME (PID: $PID)"
echo "  Killing process..."

# Kill process
if taskkill //F //PID "$PID" 2>/dev/null; then
    echo "  ✓ Process killed successfully"
else
    echo "  ⚠ Failed to kill process (may require admin privileges)"
    exit 1
fi
