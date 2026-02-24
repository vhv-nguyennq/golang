#!/bin/bash

# ==============================================================================
# SCRIPT KHỞI TẠO REACT APP/PACKAGE - VERSION 1.0 (ARCHITECT APPROVED)
# Khởi tạo React app hoặc package với cấu trúc chuẩn
# ==============================================================================

INPUT_PATH=$1
GIT_LINK=$2
ACTION_FLAG=$3

# 1. Chuẩn hóa tên & Đường dẫn
TYPE=$(echo "$INPUT_PATH" | cut -d'/' -f1)
RAW_NAME=$(echo "$INPUT_PATH" | cut -d'/' -f2)
APP_NAME=${RAW_NAME#react-}
FULL_PATH="reactjs/$TYPE/$APP_NAME"

# ------------------------------------------------------------------------------
# HÀM DỌN DẸP AN TOÀN (ROBUST CLEANUP)
# ------------------------------------------------------------------------------
execute_rollback() {
    echo ">> Đang dọn dẹp hệ thống cho $APP_NAME..."

    # Sử dụng Git command thay vì sed để tránh lỗi cú pháp file config
    git config -f .gitmodules --remove-section "submodule.$FULL_PATH" 2>/dev/null

    # Xóa khỏi Git Index và Cache
    git rm -f --cached "$FULL_PATH" 2>/dev/null
    rm -rf ".git/modules/$FULL_PATH" 2>/dev/null

    # Xóa thư mục vật lý
    [ -d "$FULL_PATH" ] && rm -rf "$FULL_PATH"

    echo "[OK] Workspace đã được đưa về trạng thái sạch."
}

# ------------------------------------------------------------------------------
# XỬ LÝ ROLLBACK THỦ CÔNG
# ------------------------------------------------------------------------------
if [ "$ACTION_FLAG" == "rollback" ]; then
    read -p ">> Xác nhận xóa sạch $FULL_PATH? (Y/N): " confirm
    [[ "$confirm" == [Yy] ]] && execute_rollback && exit 0 || exit 1
fi

# ------------------------------------------------------------------------------
# QUY TRÌNH KHỞI TẠO (ATOMIC OPERATIONS)
# ------------------------------------------------------------------------------
rollback_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "[ERROR] Lỗi tại dòng $1 (Exit code: $exit_code). Bắt đầu Rollback..."
        execute_rollback
    fi
    exit $exit_code
}
trap 'rollback_on_error $LINENO' ERR

# Kiểm tra an toàn trước khi chạy
if [ -d "$FULL_PATH" ]; then
    echo "[ERROR] Lỗi: Thư mục $FULL_PATH đã tồn tại."
    exit 1
fi

echo ">> [1/4] Tạo cấu trúc React tối giản cho $APP_NAME..."

# Tạo cấu trúc thư mục cơ bản
mkdir -p "$FULL_PATH/.github"

cd "$FULL_PATH" || exit 1

# Tạo bộ 3 file Ignore & Instructions chuẩn
cat <<'EOF' > .gitignore
# Dependencies
node_modules/
.pnp
.pnp.js

# Testing
coverage/

# Production
dist/
build/

# Environment
.env.local
.env.development.local
.env.test.local
.env.production.local

# IDE
.vscode/
.idea/

# Logs
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*

# Misc
.DS_Store
*.log
EOF

cp .gitignore .cursorignore

cat <<'EOF' > .github/copilot-ignore
**/.env*
**/node_modules
**/dist
**/build
EOF

cat <<EOF > .github/copilot-instructions.md
# 🛠️ RULES: $APP_NAME

- **Inheritance:** #file:../../../../.github/copilot-instructions.md
- **Standards:** Use TypeScript strict mode. Follow React hooks best practices.
- **Naming:** Components: PascalCase. Hooks: camelCase with 'use' prefix.
- **i18n:** All user-facing text must use react-i18next.
- **Auth:** Use @shared/auth-sdk for authentication and authorization.
EOF

# Tạo .env.example
cat <<'EOF' > .env.example
# API Configuration
VITE_API_BASE_URL=http://localhost:8080
VITE_API_GATEWAY_URL=http://localhost:8081

# Environment
VITE_APP_ENV=local

# Feature Flags
VITE_ENABLE_DEBUG=true
EOF

# Tạo README.md
cat <<EOF > README.md
# $APP_NAME

React $TYPE - Minimal scaffold for Figma Make import.

## 🎨 Setup

1. **Import code từ Figma Make:**
   - Export design từ Figma Make
   - Copy toàn bộ source code vào thư mục này

2. **Install dependencies:**
   \`\`\`bash
   pnpm install
   \`\`\`

3. **Run development:**
   \`\`\`bash
   pnpm dev
   \`\`\`

## 📁 Structure

Tự do tổ chức theo cách của bạn. Đề xuất:
\`\`\`
src/
├── main.tsx
├── App.tsx
├── components/
├── pages/
└── assets/
\`\`\`

## Standards

See [Coding Guidelines](../../docs/guides/CODING_GUIDELINES.md).
EOF

# 2. Git Operations
echo ">> [2/4] Đẩy mã nguồn lên Remote (Force Push)..."
git init && git checkout -b main
git add . && git commit -m "first message: Init $APP_NAME"
git remote add origin "$GIT_LINK"
git push -u origin main -f

# 3. Submodule Integration
echo ">> [3/4] Tích hợp Submodule..."
cd ../../.. # Quay lại root monorepo
rm -rf "$FULL_PATH" # Xóa thư mục tạm để chuẩn bị add submodule

# Kiểm tra sức khỏe .gitmodules trước khi add
if ! git config -f .gitmodules --list >/dev/null 2>&1; then
    echo ">> Sửa lỗi định dạng .gitmodules..."
    echo -n "" > .gitmodules # Reset nếu file bị hỏng hoàn toàn
fi

git submodule add "$GIT_LINK" "$FULL_PATH"

# 4. Cập nhật pnpm-workspace.yaml
echo ">> [4/4] Cập nhật workspace config..."
if ! grep -q "reactjs/$TYPE/$APP_NAME" pnpm-workspace.yaml 2>/dev/null; then
    echo "  - 'reactjs/$TYPE/$APP_NAME'" >> pnpm-workspace.yaml
fi

echo "[OK] Khởi tạo hoàn tất React $TYPE: $FULL_PATH"
echo ""
echo ">> Next steps:"
echo "   1. cd $FULL_PATH"
echo "   2. Copy source code từ Figma Make vào thư mục này"
echo "   3. Tự do tổ chức cấu trúc theo ý bạn"
