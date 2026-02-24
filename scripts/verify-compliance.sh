#!/bin/bash
# Architecture Compliance Verification Script
# Checks all services for compliance with GLOBAL ARCHITECTURE RULES

set -e

echo "=========================================="
echo "Architecture Compliance Verification"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

VIOLATIONS=0
PASSED=0

# Function to check violations
check_violation() {
    local pattern=$1
    local description=$2
    local exclude_pattern=${3:-""}

    echo -n "Checking: $description... "

    if [ -n "$exclude_pattern" ]; then
        count=$(grep -r "$pattern" go/apps --include="*.go" | grep -v "$exclude_pattern" | wc -l)
    else
        count=$(grep -r "$pattern" go/apps --include="*.go" | wc -l)
    fi

    if [ "$count" -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC} (0 violations)"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC} ($count violations)"
        ((VIOLATIONS++))
        grep -rn "$pattern" go/apps --include="*.go" | grep -v "$exclude_pattern" | head -5
    fi
}

echo "=== Rule 6: Shared Library Discipline ==="
echo ""

# Check direct database connections
check_violation "sql\.Open" "No direct sql.Open() calls" ""
check_violation "mongo\.Connect" "No direct mongo.Connect() calls" ""
check_violation "github\.com/google/uuid" "No github.com/google/uuid imports" "hash_password.go"

echo ""
echo "=== Rule 5: Sonar Compliance ==="
echo ""

# Check panic statements (exclude main.go startup panics)
check_violation "^\s*panic(" "No panic() statements" "cmd/main.go"

# Check fmt.Printf (exclude CLI tools)
check_violation "fmt\.Printf\|fmt\.Println" "No fmt.Printf/Println" "hash_password.go"

echo ""
echo "=== Build Status ==="
echo ""

# Check service builds
for service in core authentication gateway authorization; do
    echo -n "Building $service... "

    if cd "go/apps/$service" && go build -o bin/${service}.exe ./cmd/main.go 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}"
        ((VIOLATIONS++))
    fi
    cd - > /dev/null
done

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo -e "Passed:     ${GREEN}$PASSED${NC}"
echo -e "Violations: ${RED}$VIOLATIONS${NC}"

if [ $VIOLATIONS -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ ALL CHECKS PASSED - 100% COMPLIANT${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}✗ COMPLIANCE ISSUES DETECTED${NC}"
    exit 1
fi
