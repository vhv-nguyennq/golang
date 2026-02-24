# Workspace template

Mẫu workspace dùng để tạo workspace mới (poly-repo với submodules). Không chứa script mới – chỉ cấu hình và cấu trúc.

## Submodules có sẵn trong template

| Path | Mô tả |
|------|--------|
| `go/apps/gateway` | API Gateway (Go) |
| `go/packages/shared` | Thư viện dùng chung Go |
| `react/packages/authentication` | Package auth React |
| `docs/dev-manual` | Tài liệu hướng dẫn dev |
| `docs/architecture` | Tài liệu kiến trúc |
| `templates` | Template Go/React cho repo mới |
| `resource/i18n` | Nguồn i18n |

## Cách dùng

### 1. Tạo repo manifest cho workspace mới

- Tạo repo trống (vd. `https://git.vhv.vn/workspace/my-workspace`).
- Clone repo đó về máy.

### 2. Copy nội dung template vào repo manifest

Từ thư mục gốc repo vừa clone:

```bash
# Copy toàn bộ file từ templates/workspace (trong repo chứa template này) vào thư mục hiện tại
cp path/to/templates/workspace/workspace.yaml .
cp path/to/templates/workspace/.gitmodules .
cp path/to/templates/workspace/.gitignore .
cp path/to/templates/workspace/go.work .
cp path/to/templates/workspace/pnpm-workspace.yaml .
cp path/to/templates/workspace/package.json .
```

Hoặc copy cả thư mục `templates/workspace` rồi di chuyển các file lên root.

### 3. (Tùy chọn) Đổi tên workspace

Trong `workspace.yaml` sửa `workspace.name` (thay `cms` bằng tên workspace của bạn).

### 4. Khởi tạo submodules

```bash
git submodule update --init --recursive
```

Hoặc nếu dùng devctl (sau khi đã có workspace.yaml và repo manifest):

```bash
devctl sync
```

### 5. Commit và push

```bash
git add workspace.yaml .gitmodules .gitignore go.work pnpm-workspace.yaml package.json
git commit -m "chore: init workspace from templates/workspace"
git push
```

## Cấu trúc thư mục sau khi init

```
<workspace-root>/
├── workspace.yaml
├── .gitmodules
├── .gitignore
├── go.work
├── pnpm-workspace.yaml
├── package.json
├── go/
│   ├── apps/
│   │   └── gateway/     # submodule
│   └── packages/
│       └── shared/      # submodule
├── react/
│   └── packages/
│       └── authentication/  # submodule
├── docs/
│   ├── dev-manual/      # submodule
│   └── architecture/    # submodule
├── templates/           # submodule
└── resource/
    └── i18n/            # submodule
```

## Lưu ý

- URL trong `workspace.yaml` và `.gitmodules` mặc định dùng `https://git.vhv.vn`. Nếu workspace mới dùng Git server khác, thay toàn bộ base URL trong hai file.
- Thêm app/service mới bằng `devctl create go <name>` hoặc `devctl create react <name>`, rồi chạy `devctl sync`.
