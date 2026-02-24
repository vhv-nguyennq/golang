# Media Service - Database Collections Design

**Service Name:** Media Service
**Database:** YugabyteDB
**Schema:** `public`
**Version:** 2.0
**Date:** 2026-01-31
**Last Updated:** 2026-01-31 (Enhanced with additional tables)

---

## Tổng Quan Kiến Trúc

Media Service quản lý cấu trúc logic và metadata của các tệp tin upload. Thiết kế dựa trên:

- **Hierarchical Data Model**: Closure Table cho cấu trúc phân cấp
- **DAG (Directed Acyclic Graph)**: Quản lý dependencies và prerequisites
- **Dynamic Metadata**: JSONB cho thuộc tính mở rộng
- **Blueprint & Versioning**: Hỗ trợ kế thừa và quản lý phiên bản
- **Multi-tenancy**: Isolation hoàn toàn theo tenant_id

## Bảng dữ liệu

| Bảng          | Tên trường       | Kiểu dữ liệu | Null? | Mặc định     | Ràng buộc                                                 | Mô tả                                                                                                         |
| ------------- | ---------------- | ------------ | ----- | ------------ | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| storage_files | YSQL             | Collection   |       |              |                                                           | Quản lý thư viện tài nguyên số (Ảnh, Video, Tài liệu).                                                        |
| storage_files | id               | UUID         | NO    |              | PRIMARY KEY                                               | Định danh duy nhất chuẩn UUID v7 giúp tối ưu sắp xếp theo thời gian và phân tán dữ liệu (sharding).           |
| storage_files | tenant_id        | UUID         | NO    |              | REFERENCES tenants(id) ON DELETE CASCADE                  | Sharding Key. Xác định tệp tin thuộc sở hữu của tổ chức nào để đảm bảo cô lập dữ liệu.                        |
| storage_files | parent_id        | UUID         | YES   | NULL         |                                                           | ID của thư mục chứa tệp tin (nếu hệ thống hỗ trợ tính năng Media Folder).                                     |
| storage_files | file_type        | TEXT         | NO    | FILE         | CHECK (IN ('FOLDER', 'FILE'))                             | Loại dữ liệu thư mục hay tệp tin.                                                                             |
| storage_files | original_name    | TEXT         | NO    |              | CHECK (length(original_name) > 0)                         | Tên gốc của tệp tin khi người dùng tải lên.                                                                   |
| storage_files | storage_path     | TEXT         | NO    |              | UNIQUE(tenant_id, storage_path)                           | Đường dẫn (Key) lưu trữ trên Object Storage (S3/MinIO). Không lưu tên miền tại đây để đảm bảo tính linh hoạt. |
| storage_files | public_url       | TEXT         | YES   | NULL         |                                                           | URL đầy đủ (CDN) nếu tệp tin được công khai. Dùng kiểu TEXT để chứa được các URL có chữ ký bảo mật dài.       |
| storage_files | mime_type        | VARCHAR(100) | NO    |              |                                                           | Loại định dạng tệp tin (VD: image/jpeg, video/mp4, application/pdf).                                          |
| storage_files | file_size        | BIGINT       | NO    | 0            | CHECK (file_size >= 0)                                    | Kích thước tệp tin (bytes) phục vụ việc thống kê dung lượng sử dụng (Metering).                               |
| storage_files | dimensions       | JSONB        | NO    | '{}'         |                                                           | Lưu thông số kỹ thuật như chiều rộng, chiều cao, độ dài video (VD: `{"width": 1920, "height": 1080}`).        |
| storage_files | alt_text         | TEXT         | YES   | NULL         |                                                           | Văn bản thay thế phục vụ SEO và khả năng truy cập (Accessibility).                                            |
| storage_files | caption          | TEXT         | YES   | NULL         |                                                           | Chú thích hiển thị dưới ảnh hoặc tài liệu.                                                                    |
| storage_files | variants         | JSONB        | NO    | '{}'         |                                                           | Lưu thông tin các phiên bản đã được xử lý (Thumbnail, Small, Medium, Optimized).                              |
| storage_files | metadata         | JSONB        | NO    | '{}'         |                                                           | Dữ liệu kỹ thuật mở rộng (EXIF, điểm tập trung ảnh, nhãn AI).                                                 |
| storage_files | storage_provider | VARCHAR(20)  | NO    | 'S3'         | CHECK (IN ('S3', 'R2', 'MINIO', 'CLOUDFLARE'))            | Nhà cung cấp lưu trữ vật lý, hỗ trợ chiến lược đa đám mây (Multi-cloud).                                      |
| storage_files | visibility       | VARCHAR(20)  | NO    | 'PRIVATE'    | CHECK (IN ('PUBLIC', 'PRIVATE', 'INTERNAL'))              | Quyền truy cập tài nguyên: Công khai (CDN) hoặc Riêng tư (Signed URL).                                        |
| storage_files | status           | VARCHAR(20)  | NO    | 'PROCESSING' | CHECK (IN ('UPLOADING', 'PROCESSING', 'READY', 'FAILED')) | Trạng thái xử lý tệp tin (hỗ trợ tác vụ resize ảnh hoặc transcode video).                                     |
| storage_files | uploaded_by      | TEXT         | YES   | NULL         |                                                           | Định danh người dùng thực hiện tải tệp tin lên.                                                               |
| storage_files | created_by       | TEXT         | YES   | NULL         |                                                           | Định danh người dùng tạo bản ghi.                                                                             |
| storage_files | updated_by       | TEXT         | YES   | NULL         |                                                           | Định danh người dùng cập nhật bản ghi lần cuối.                                                               |
| storage_files | created_at       | TIMESTAMPTZ  | NO    | now()        |                                                           | Thời điểm tạo bản ghi theo chuẩn UTC.                                                                         |
| storage_files | updated_at       | TIMESTAMPTZ  | NO    | now()        | CHECK (updated_at >= created_at)                          | Thời điểm cập nhật cuối cùng.                                                                                 |
| storage_files | deleted_at       | TIMESTAMPTZ  | YES   | NULL         |                                                           | Soft Delete. Giữ metadata một thời gian trước khi thực sự xóa tệp vật lý trên Storage.                        |
| storage_files | version          | BIGINT       | NO    | 1            | CHECK (version >= 1)                                      | Cơ chế Optimistic Locking ngăn chặn ghi đè dữ liệu đồng thời.                                                 |

---

## Index Strategy

### Sharding Indexes

- Tất cả bảng multi-tenant: `CREATE INDEX ON table (tenant_id HASH)`
- LSM (Log-Structured Merge) engine cho YugabyteDB distributed

### Performance Indexes

- Materialized Path: `CREATE INDEX ON table (path text_pattern_ops ASC)`
- JSONB search: `CREATE INDEX ON table USING ybgin (metadata)`
- Composite lookups: `CREATE INDEX ON table (tenant_id HASH, status ASC, created_at DESC)`
- Partial indexes: `WHERE deleted_at IS NULL`

### Unique Constraints

- Global unique: email, phone_number
- Tenant-scoped unique: `UNIQUE (tenant_id, code)`
- Composite unique: `UNIQUE (tenant_id, parent_id, name)`

---

## Design Patterns

### Multi-tenancy

- Sharding key: `tenant_id` trên mọi bảng tenant-scoped
- Row-level security: RLS policies filter by tenant_id
- Global tables: users (shared across tenants)
- Tenant-scoped: media_files, articles (isolated per tenant)

### Soft Delete

- `deleted_at TIMESTAMPTZ NULL`
- Indexes: `WHERE deleted_at IS NULL`
- Audit trail preservation
- Possible restore

### Optimistic Locking

- `version BIGINT DEFAULT 1`
- Increment on update
- Prevent concurrent overwrites

### Materialized Path

- `path TEXT` (VD: `/uuid1/uuid2/uuid3/`)
- Query all descendants: `WHERE path LIKE '/parent_id/%'`
- Fast subtree operations

### Metadata Flexibility

- `metadata JSONB DEFAULT '{}'`
- Schema-less extensions
- GIN indexes for search

---

## Security & Compliance

### Encryption

- Password: bcrypt hash
- MFA secret: AES-256 encryption
- API keys: SHA-256 hash

### Audit Trail

- created_at, updated_at, deleted_at
- created_by, uploaded_by tracking
- Immutable log tables (optional)

### Data Residency

- `data_region` field on tenants
- Geo-partitioning support
- GDPR/HIPAA compliance ready

### Access Control

- ACL table for granular permissions
- Role-based access control (RBAC)
- Attribute-based access control (ABAC) via metadata

---
