#!/bin/bash

# ==============================================================================
# SCRIPT KHỞI TẠO MICROSERVICE - VERSION 5.0 (ARCHITECT APPROVED)
# Khắc phục lỗi .gitmodules trên Windows & Đảm bảo Clean Architecture
# ==============================================================================

INPUT_PATH=$1
GIT_LINK=$2
ACTION_FLAG=$3
AUTO_CONFIRM=${AUTO_CONFIRM:-0}

# 1. Chuẩn hóa tên & Đường dẫn
TYPE=$(echo "$INPUT_PATH" | cut -d'/' -f1)
RAW_NAME=$(echo "$INPUT_PATH" | cut -d'/' -f2)
SERVICE_NAME=${RAW_NAME#go-}
FULL_PATH="go/$TYPE/$SERVICE_NAME"

# ------------------------------------------------------------------------------
# HÀM DỌN DẸP AN TOÀN (ROBUST CLEANUP)
# ------------------------------------------------------------------------------
execute_rollback() {
    echo "🚨 Đang dọn dẹp hệ thống cho $SERVICE_NAME..."

    # Sử dụng Git command thay vì sed để tránh lỗi cú pháp file config
    git config -f .gitmodules --remove-section "submodule.$FULL_PATH" 2>/dev/null

    # Xóa khỏi Git Index và Cache
    git rm -f --cached "$FULL_PATH" 2>/dev/null
    rm -rf ".git/modules/$FULL_PATH" 2>/dev/null

    # Xóa thư mục vật lý
    [ -d "$FULL_PATH" ] && rm -rf "$FULL_PATH"

    echo "✅ Workspace đã được đưa về trạng thái sạch."
}

# ------------------------------------------------------------------------------
# XỬ LÝ ROLLBACK THỦ CÔNG
# ------------------------------------------------------------------------------
if [ "$ACTION_FLAG" == "rollback" ]; then
    if [ "$AUTO_CONFIRM" = "1" ]; then
        execute_rollback && exit 0
    fi
    read -p "⚠️ Xác nhận xóa sạch $FULL_PATH? (Y/N): " confirm
    [[ "$confirm" == [Yy] ]] && execute_rollback && exit 0 || exit 1
fi

# ------------------------------------------------------------------------------
# QUY TRÌNH KHỞI TẠO (ATOMIC OPERATIONS)
# ------------------------------------------------------------------------------
rollback_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "⚠️ Lỗi tại dòng $1 (Exit code: $exit_code). Bắt đầu Rollback..."
        execute_rollback
    fi
    exit $exit_code
}
trap 'rollback_on_error $LINENO' ERR

# Kiểm tra an toàn trước khi chạy
if [ -d "$FULL_PATH" ]; then
    echo "❌ Lỗi: Thư mục $FULL_PATH đã tồn tại."
    exit 1
fi

echo "🚀 [1/4] Tạo cấu trúc Clean Architecture cho $SERVICE_NAME..."
# Tuân thủ cấu trúc thư mục chuẩn [1, 2]
mkdir -p "$FULL_PATH/cmd/server" "$FULL_PATH/internal/api/grpc/v1" \
         "$FULL_PATH/internal/service" "$FULL_PATH/internal/repository" \
         "$FULL_PATH/internal/model" "$FULL_PATH/api/proto/$SERVICE_NAME/v1" \
         "$FULL_PATH/.github"

cd "$FULL_PATH" || exit 1
go mod init "$SERVICE_NAME"

# Tạo bộ 3 file Ignore & Instructions chuẩn [Conversation History]
cat <<'EOF' > .gitignore
bin/
tmp/
vendor/
.env.local
*.log
EOF
cp .gitignore .cursorignore
echo "**/.env*" > .github/copilot-ignore

cat <<'EOF' > .github/copilot-instructions.md
# 🛠️ RULES: [NAME]
- **Inheritance:** #file:../../../../.github/copilot-instructions.md
- **Standards:** PK is `id` (UUID v7). Use `tenant_id` for isolation [3, 4].
- **Soft Delete:** Mandatory `deleted_at`. No physical `DELETE` [5-7].
EOF
sed -i "s/\[NAME\]/$SERVICE_NAME/g" .github/copilot-instructions.md

# Setup Dev Workflow [8-10]
echo "DB_URL=postgres://dev:pass@shared-dev-yb:5433/core_db" > .env.example

# 2. Git Operations
echo "📦 [2/4] Đẩy mã nguồn lên Remote (Force Push)..."
git init && git checkout -b main
git add . && git commit -m "first message: Init $SERVICE_NAME"
git remote add origin "$GIT_LINK"
# Push and verify remote received the commit. Retry once if needed.
git push -u origin main -f
if [ -z "$(git ls-remote "$GIT_LINK" refs/heads/main)" ]; then
    echo "⚠️ Remote did not report branch 'main'. Retrying push..."
    git push -u origin main -f
fi
if [ -z "$(git ls-remote "$GIT_LINK" refs/heads/main)" ]; then
    echo "❌ Warning: Remote repository may be empty or unreachable. Continuing to add submodule, but submodule may not contain files until remote is populated." >&2
fi

# 3. Submodule Integration
echo "🔗 [3/4] Tích hợp Submodule..."
cd ../../.. # Quay lại root monorepo
rm -rf "$FULL_PATH" # Xóa thư mục tạm để chuẩn bị add submodule

# Kiểm tra sức khỏe .gitmodules trước khi add
if ! git config -f .gitmodules --list >/dev/null 2>&1; then
    echo "🔧 Sửa lỗi định dạng .gitmodules..."
    echo -n "" > .gitmodules # Reset nếu file bị hỏng hoàn toàn
fi

git submodule add "$GIT_LINK" "$FULL_PATH"
# Ensure submodule has a checked-out working tree and points to main
if [ -d "$FULL_PATH" ]; then
    # fetch and try to checkout origin/main into working tree
    git -C "$FULL_PATH" fetch --all --prune || true
    if git -C "$FULL_PATH" show-ref --verify --quiet refs/heads/main; then
        git -C "$FULL_PATH" checkout main || true
    else
        # try to create main from origin/main
        git -C "$FULL_PATH" checkout -B main origin/main 2>/dev/null || true
    fi
    # reset working tree to remote if available
    git -C "$FULL_PATH" reset --hard origin/main 2>/dev/null || true
fi

echo "✅ [4/4] Khởi tạo hoàn tất microservice: $FULL_PATH"
