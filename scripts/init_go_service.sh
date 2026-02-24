#!/bin/bash

# ==============================================================================
# Go Service Template Initialization Script
# Version: 1.0.0
# Framework: VHV Platform Microservices
# ==============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Template directory
TEMPLATE_DIR="scripts/templates/go-service"

# ==============================================================================
# Functions
# ==============================================================================

print_header() {
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${GREEN}  Go Service Template Initialization${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Validate service name
validate_service_name() {
    local name=$1

    # Check if empty
    if [ -z "$name" ]; then
        print_error "Service name cannot be empty"
        return 1
    fi

    # Check format (lowercase, hyphens only)
    if ! [[ "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        print_error "Service name must be lowercase with hyphens only (e.g., user-service, auth-service)"
        return 1
    fi

    return 0
}

# Convert service name formats
format_service_name() {
    local name=$1
    echo "$name" | tr '[:upper:]' '[:lower:]' | tr '_' '-'
}

format_display_name() {
    local name=$1
    # Convert hyphens to spaces and capitalize words
    echo "$name" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1'
}

# Check if service already exists
check_service_exists() {
    local service_name=$1
    local target_dir="go/apps/$service_name"

    if [ -d "$target_dir" ]; then
        print_error "Service '$service_name' already exists at $target_dir"
        return 1
    fi

    return 0
}

# Create directory structure
create_structure() {
    local service_name=$1
    local target_dir="go/apps/$service_name"

    print_info "Creating directory structure..."

    mkdir -p "$target_dir"/{.github/workflows,bin,cmd,internal/{domain,handler,repository,service,pb,utils},migrations,docs}

    print_success "Directory structure created"
}

# Copy template files
copy_templates() {
    local service_name=$1
    local service_display=$2
    local target_dir="go/apps/$service_name"

    print_info "Copying template files..."

    # Copy all template files (including dotfiles)
    shopt -s dotglob
    cp -r "$TEMPLATE_DIR"/* "$target_dir/"
    shopt -u dotglob

    # Replace placeholders
    find "$target_dir" -type f -exec sed -i "s/{{SERVICE_NAME}}/$service_name/g" {} +
    find "$target_dir" -type f -exec sed -i "s/{{SERVICE_NAME_DISPLAY}}/$service_display/g" {} +

    print_success "Template files copied and customized"
}

# Initialize git
init_git() {
    local service_name=$1
    local target_dir="go/apps/$service_name"
    local git_repo=$2

    print_info "Initializing git repository..."

    cd "$target_dir"
    git init
    git add .
    git commit -m "chore: initialize $service_name from template"

    if [ -n "$git_repo" ]; then
        git remote add origin "$git_repo"
        print_success "Git remote added: $git_repo"

        # Push to remote
        print_info "Pushing to remote repository..."
        if git push --set-upstream origin main 2>&1; then
            print_success "Code pushed to remote successfully"
        else
            print_warning "Failed to push to remote (repo may not exist yet)"
            print_info "You can manually push later: cd $target_dir && git push -u origin main"
        fi
    else
        print_warning "No git repository specified. Add remote later with:"
        print_info "  cd $target_dir && git remote add origin <URL> && git push -u origin main"
    fi

    cd - > /dev/null

    print_success "Git repository initialized"
}

# Initialize go module
init_go_module() {
    local service_name=$1
    local target_dir="go/apps/$service_name"

    print_info "Initializing Go module..."

    cd "$target_dir"
    go mod tidy
    go mod download

    cd - > /dev/null

    print_success "Go module initialized"
}

# Create .env.local
create_env_local() {
    local service_name=$1
    local target_dir="go/apps/$service_name"

    print_info "Creating .env.local..."

    cp "$target_dir/.env.example" "$target_dir/.env.local"

    print_success ".env.local created (edit with your configuration)"
}

# Add to parent go.work
add_to_workspace() {
    local service_name=$1

    if [ -f "go.work" ]; then
        print_info "Adding to go.work..."

        # Add to go.work if not already present
        if ! grep -q "go/apps/$service_name" go.work; then
            go work use "go/apps/$service_name"
            print_success "Added to go.work"
        else
            print_warning "Already in go.work"
        fi
    fi
}

# Print next steps
print_next_steps() {
    local service_name=$1
    local target_dir="go/apps/$service_name"

    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Setup Complete! 🎉${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo ""
    echo "1. Navigate to your service:"
    echo -e "   ${BLUE}cd $target_dir${NC}"
    echo ""
    echo "2. Configure environment:"
    echo -e "   ${BLUE}nano .env.local${NC}"
    echo ""
    echo "3. Define your proto API:"
    echo -e "   ${BLUE}# Create proto file in resource/proto/$service_name/${NC}"
    echo ""
    echo "4. Generate proto code:"
    echo -e "   ${BLUE}make proto${NC}"
    echo ""
    echo "5. Implement your business logic:"
    echo -e "   - Edit ${BLUE}internal/domain/*.go${NC} (models)"
    echo -e "   - Edit ${BLUE}internal/repository/*.go${NC} (data access)"
    echo -e "   - Edit ${BLUE}internal/service/*.go${NC} (business logic)"
    echo -e "   - Edit ${BLUE}internal/handler/*.go${NC} (gRPC handlers)"
    echo ""
    echo "6. Run migrations:"
    echo -e "   ${BLUE}make migrate-up${NC}"
    echo ""
    echo "7. Run your service:"
    echo -e "   ${BLUE}make run${NC}"
    echo ""
    echo "8. Test your service:"
    echo -e "   ${BLUE}make test${NC}"
    echo ""
    echo -e "${YELLOW}Documentation:${NC}"
    echo -e "   - Architecture: ${BLUE}docs/architecture/ARCHITECTURE.md${NC}"
    echo -e "   - Coding Guidelines: ${BLUE}docs/guides/CODING_GUIDELINES.md${NC}"
    echo -e "   - Git Workflow: ${BLUE}docs/guides/GIT_WORKFLOW.md${NC}"
    echo ""
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    print_header

    # Check if template directory exists
    if [ ! -d "$TEMPLATE_DIR" ]; then
        print_error "Template directory not found: $TEMPLATE_DIR"
        exit 1
    fi

    # Get service name
    if [ -z "$1" ]; then
        print_error "Usage: $0 <service-name> [git-repo-url]"
        echo ""
        echo "Example:"
        echo "  $0 user-service"
        echo "  $0 product-service https://github.com/vhvplatform/go-product-service"
        exit 1
    fi

    SERVICE_NAME=$(format_service_name "$1")
    GIT_REPO="$2"

    # Validate service name
    if ! validate_service_name "$SERVICE_NAME"; then
        exit 1
    fi

    SERVICE_DISPLAY=$(format_display_name "$SERVICE_NAME")

    print_info "Service Name: $SERVICE_NAME"
    print_info "Display Name: $SERVICE_DISPLAY"

    if [ -n "$GIT_REPO" ]; then
        print_info "Git Repository: $GIT_REPO"
    fi

    echo ""

    # Confirm
    read -p "Continue? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Cancelled"
        exit 0
    fi

    # Check if service exists
    if ! check_service_exists "$SERVICE_NAME"; then
        exit 1
    fi

    # Execute steps
    create_structure "$SERVICE_NAME"
    copy_templates "$SERVICE_NAME" "$SERVICE_DISPLAY"
    init_git "$SERVICE_NAME" "$GIT_REPO"
    create_env_local "$SERVICE_NAME"
    init_go_module "$SERVICE_NAME"
    add_to_workspace "$SERVICE_NAME"

    # Print next steps
    print_next_steps "$SERVICE_NAME"
}

main "$@"
