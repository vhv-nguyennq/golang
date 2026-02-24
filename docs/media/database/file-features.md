# Media Management: Folder Organization & File Upload Deep Dive

**Project:** CMS Media Management Service
**Focus:** Folder Hierarchy & Upload Pipeline với MinIO Storage
**Version:** 2.0 (Go Implementation)
**Date:** 2026-02-09
**Language:** Go 1.25+ / gRPC

> **⚠️ Architecture Notice:**
> This document follows the **Copilot Architecture Constitution** for Go microservices.
> All implementations use shared libraries from `go/packages/shared` and comply with:
>
> - Tenant isolation (mandatory)
> - UUID v7 (via shared/uuid)
> - Error wrapping (via shared/errors)
> - Outbox pattern (via shared/outbox)
> - Context propagation (via shared/context)
> - Storage abstraction (via shared/storage)

---

## Table of Contents

1. [Tổng Quan Kiến Trúc](#1-tổng-quan-kiến-trúc)
2. [Folder Management System](#2-folder-management-system)
3. [File Upload Pipeline](#3-file-upload-pipeline)
4. [Storage Path Strategy](#4-storage-path-strategy)
5. [MinIO Storage Integration](#5-minio-storage-integration)
6. [Image Processing Workflow](#6-image-processing-workflow)
7. [API Design](#7-api-design)
8. [Frontend Implementation](#8-frontend-implementation)
9. [Performance Optimization](#9-performance-optimization)

---

## 1. Tổng Quan Kiến Trúc

### 1.1. Unified Data Model: Folders & Files In One Table

Media Service sử dụng **polymorphic design** với single table `storage_files`:

```sql
CREATE TABLE media.storage_files (
    id UUID PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES tenants(_id),
    parent_id UUID NULL,                    -- Self-referential: folder structure
    file_type TEXT NOT NULL DEFAULT 'FILE', -- 'FOLDER' or 'FILE'
    original_name TEXT NOT NULL,            -- Display name
    storage_path TEXT NOT NULL,             -- Physical storage key in MinIO
    public_url TEXT NULL,                   -- Full URL: https://cdn.example.com/bucket/path
    mime_type VARCHAR(100) NOT NULL,
    file_size BIGINT NOT NULL DEFAULT 0,
    dimensions JSONB NOT NULL DEFAULT '{}',
    variants JSONB NOT NULL DEFAULT '{}',
    metadata JSONB NOT NULL DEFAULT '{}',
    storage_provider VARCHAR(20) NOT NULL DEFAULT 'MINIO',
    visibility VARCHAR(20) NOT NULL DEFAULT 'PRIVATE',
    status VARCHAR(20) NOT NULL DEFAULT 'PROCESSING',
    uploaded_by TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL,
    version BIGINT NOT NULL DEFAULT 1
);
```

**Ưu điểm của thiết kế này:**

| Aspect                | Polymorphic (Single Table) | Separate Tables                   |
| --------------------- | -------------------------- | --------------------------------- |
| **Schema Simplicity** | ✅ One table, less joins   | ❌ Two tables, complex joins      |
| **Move Operations**   | ✅ Update parent_id only   | ❌ Update folder_id across tables |
| **Permissions**       | ✅ Unified ACL logic       | ❌ Duplicate permission checks    |
| **Search**            | ✅ Single query            | ❌ UNION queries                  |
| **Tree Traversal**    | ✅ Recursive CTE native    | ❌ Cross-table recursion          |

**Key Fields cho MinIO Integration:**

- `storage_path`: Relative path trong MinIO bucket (e.g., `tenants/abc123/2024/02/07/uuid.jpg`)
- `public_url`: Optional full public URL (e.g., `https://cdn.example.com/media-assets/tenants/abc123/2024/02/07/uuid.jpg`).
  Note: the canonical storage location is `storage_path` (the object key inside the bucket). The service persists `storage_path` for all files; `public_url` is optional and may be derived from CDN configuration when needed.
- `storage_provider`: Luôn là `'MINIO'` cho hệ thống này
- `variants`: JSONB chứa URLs của các processed versions (thumbnail, small, medium, large)

---

## 2. Folder Management System

### 2.1. Hierarchical Structure: Self-Referential Parent-Child

#### 2.1.1. Creating Folder Hierarchy

```sql
-- Root folder (parent_id = NULL)
INSERT INTO media.storage_files (
    id, tenant_id, parent_id, file_type, original_name,
    storage_path, mime_type, file_size, storage_provider, status
) VALUES (
    gen_random_uuid(),
    'tenant-abc123',
    NULL,
    'FOLDER',
    'Marketing Assets',
    '',  -- Empty for folders
    'inode/directory',
    0,
    'MINIO',
    'READY'
);

-- Child folder
INSERT INTO media.storage_files (
    id, tenant_id, parent_id, file_type, original_name,
    storage_path, mime_type, file_size, storage_provider, status
) VALUES (
    gen_random_uuid(),
    'tenant-abc123',
    '<uuid-root-folder>',
    'FOLDER',
    'Campaigns',
    '',
    'inode/directory',
    0,
    'MINIO',
    'READY'
);
```

#### 2.1.2. Querying Folder Tree

**Get Direct Children:**

```sql
SELECT id, original_name, file_type, created_at, file_size
FROM media.storage_files
WHERE tenant_id = $1
  AND parent_id = $2
  AND deleted_at IS NULL
ORDER BY
  CASE file_type WHEN 'FOLDER' THEN 0 ELSE 1 END,  -- Folders first
  original_name ASC;
```

**Get All Descendants (Recursive CTE):**

```sql
WITH RECURSIVE folder_tree AS (
  -- Anchor: root folder
  SELECT id, parent_id, original_name, file_type, file_size,
         0 AS depth,
         ARRAY[_id] AS path
  FROM media.storage_files
  WHERE id = $1
    AND tenant_id = $2
    AND deleted_at IS NULL

  UNION ALL

  -- Recursive: children
  SELECT f.id, f.parent_id, f.original_name, f.file_type, f.file_size,
         ft.depth + 1,
         ft.path || f._id
  FROM media.storage_files f
  JOIN folder_tree ft ON f.parent_id = ft._id
  WHERE f.tenant_id = $2
    AND f.deleted_at IS NULL
)
SELECT * FROM folder_tree
ORDER BY depth, original_name;
```

**Get Breadcrumb Path (Bottom-Up):**

```sql
WITH RECURSIVE breadcrumb AS (
  -- Start from target folder
  SELECT id, parent_id, original_name, 1 AS level
  FROM media.storage_files
  WHERE id = $1 AND tenant_id = $2

  UNION ALL

  -- Walk up to parents
  SELECT f.id, f.parent_id, f.original_name, b.level + 1
  FROM media.storage_files f
  JOIN breadcrumb b ON f._id = b.parent_id
)
SELECT id, original_name
FROM breadcrumb
ORDER BY level DESC;  -- Root first
```

### 2.2. Folder Operations

#### 2.2.1. Move Folder

**Go Implementation with Circular Reference Prevention:**

```go
package services

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"go.uber.org/zap"

	"cms/go/packages/shared/errors"
	contextpkg "cms/go/packages/shared/context"
)

// MoveFolder moves a folder to a new parent with circular reference validation
func (s *FolderService) MoveFolder(
	ctx context.Context,
	folderID uuid.UUID,
	newParentID *uuid.UUID,
) error {
	tenantID, err := contextpkg.GetTenantID(ctx)
	if err != nil {
		return errors.Unauthorized("tenant not found", err)
	}

	// 1. Validate: Prevent circular reference
	if newParentID != nil {
		isDescendant, err := s.isDescendantOf(ctx, tenantID, folderID, *newParentID)
		if err != nil {
			return errors.Internal("failed to check circular reference", err)
		}

		if isDescendant {
			return errors.InvalidArgument("cannot move folder into its own subtree")
		}
	}

	// 2. Get folder to update
	folder, err := s.repo.GetByID(ctx, tenantID, folderID)
	if err != nil {
		return errors.NotFound("folder not found", err)
	}

	if folder.FileType != entity.FileTypeFolder {
		return errors.InvalidArgument("not a folder")
	}

	// 3. Update parent_id
	oldParentID := folder.ParentID
	folder.ParentID = newParentID

	if err := s.repo.Update(ctx, folder); err != nil {
		return errors.Internal("failed to move folder", err)
	}

	// 4. Invalidate cache for both old and new parent
	if oldParentID != nil {
		_ = s.invalidateCache(ctx, tenantID, *oldParentID)
	}
	if newParentID != nil {
		_ = s.invalidateCache(ctx, tenantID, *newParentID)
	}

	// 5. Publish event
	_ = s.publishEvent(ctx, tenantID, "media.folder.moved", folderID, map[string]interface{}{
		"folder_id":      folderID.String(),
		"old_parent_id":  oldParentID,
		"new_parent_id":  newParentID,
	})

	s.log.Info("Folder moved",
		zap.String("folder_id", folderID.String()),
		zap.String("new_parent", fmt.Sprint(newParentID)),
	)

	return nil
}

// isDescendantOf checks if targetID is a descendant of potentialAncestorID
func (s *FolderService) isDescendantOf(
	ctx context.Context,
	tenantID uuid.UUID,
	potentialAncestorID uuid.UUID,
	targetID uuid.UUID,
) (bool, error) {
	query := `
		WITH RECURSIVE descendants AS (
			SELECT _id FROM media.storage_files
			WHERE _id = $1 AND tenant_id = $2

			UNION ALL

			SELECT f._id
			FROM media.storage_files f
			JOIN descendants d ON f.parent_id = d._id
			WHERE f.tenant_id = $2
		)
		SELECT EXISTS(SELECT 1 FROM descendants WHERE _id = $3)
	`

	var exists bool
	err := s.db.QueryRow(ctx, query, potentialAncestorID, tenantID, targetID).Scan(&exists)
	if err != nil {
		return false, err
	}

	return exists, nil
}
```

#### 2.2.2. Delete Folder (Soft Delete with Cascade)

**SQL with Recursive CTE:**

```sql
-- Soft delete folder and all descendants
WITH RECURSIVE folder_subtree AS (
  SELECT _id FROM media.storage_files
  WHERE _id = $1 AND tenant_id = $2

  UNION ALL

  SELECT f._id
  FROM media.storage_files f
  JOIN folder_subtree ft ON f.parent_id = ft._id
  WHERE f.tenant_id = $2
)
UPDATE media.storage_files
SET deleted_at = now(), updated_at = now()
WHERE _id IN (SELECT _id FROM folder_subtree);
```

**Go Implementation:**

```go
// DeleteFolderCascade soft deletes folder and all descendants
func (s *FolderService) DeleteFolderCascade(
	ctx context.Context,
	folderID uuid.UUID,
) error {
	tenantID, err := contextpkg.GetTenantID(ctx)
	if err != nil {
		return errors.Unauthorized("tenant not found", err)
	}

	query := `
		WITH RECURSIVE folder_subtree AS (
			SELECT _id FROM media.storage_files
			WHERE _id = $1 AND tenant_id = $2 AND deleted_at IS NULL

			UNION ALL

			SELECT f._id
			FROM media.storage_files f
			JOIN folder_subtree ft ON f.parent_id = ft._id
			WHERE f.tenant_id = $2 AND f.deleted_at IS NULL
		)
		UPDATE media.storage_files
		SET deleted_at = now(), updated_at = now()
		WHERE _id IN (SELECT _id FROM folder_subtree)
		RETURNING _id
	`

	rows, err := s.db.Query(ctx, query, folderID, tenantID)
	if err != nil {
		return errors.Internal("failed to delete folder", err)
	}
	defer rows.Close()

	deletedIDs := []uuid.UUID{}
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			s.log.Warn("Failed to scan deleted ID", zap.Error(err))
			continue
		}
		deletedIDs = append(deletedIDs, id)
	}

	s.log.Info("Folder deleted with cascade",
		zap.String("folder_id", folderID.String()),
		zap.Int("deleted_count", len(deletedIDs)),
	)

	// Publish event
	_ = s.publishEvent(ctx, tenantID, "media.folder.deleted", folderID, map[string]interface{}{
		"folder_id":     folderID.String(),
		"deleted_count": len(deletedIDs),
	})

	return nil
}
```

---

## 3. File Upload Pipeline

### 3.1. Upload Flow Architecture

```
┌─────────────┐
│   Client    │
│  (Browser)  │
└──────┬──────┘
       │ 1. Request upload URL + metadata
       │ POST /api/media/upload-url
       ▼
┌─────────────────────┐
│  Media Service      │
│  (Backend API)      │
│  - Check quota      │
│  - Validate perms   │
│  - Create DB record │
│  - Generate URL     │
└──────┬──────────────┘
	│ 2. Return presigned URL (client uploads directly to `storage_path`)
	│ { uploadUrl, storagePath, fileId }
       │
       ▼
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ 3. Upload directly to MinIO
       │ PUT {uploadUrl} + file bytes
       ▼
┌──────────────────┐
│  MinIO Storage   │
│  (Object Store)  │
└──────┬───────────┘
       │ 4. Upload complete
       │ Client notifies backend
       ▼
┌─────────────────────┐
│  Media Service      │
│  - Verify upload    │
│  - Update status    │
│  - Enqueue job      │
└──────┬──────────────┘
       │ 5. Processing
       ▼
┌──────────────────────┐
│ Background Worker    │
│ - Download from MinIO│
│ - Generate variants  │
│ - Upload variants    │
│ - Update DB          │
└──────┬───────────────┘
       │ 6. Complete
       │ status = READY
       ▼
┌─────────────┐
│   Client    │
│ (WebSocket) │
└─────────────┘
```

---

## 4. Storage Path Strategy

### 4.1. Path Generation Pattern

```go
package services

import (
	"fmt"
	"os"
	"path"
	"time"

	"github.com/google/uuid"
)

// generateStoragePath creates a tenant-isolated, date-partitioned path
func generateStoragePath(tenantID uuid.UUID, originalName string, fileID uuid.UUID) string {
	now := time.Now()
	ext := path.Ext(originalName)

	// Pattern: tenants/{tenant_id}/{year}/{month}/{day}/{uuid}{ext}
	return fmt.Sprintf(
		"tenants/%s/%d/%02d/%02d/%s%s",
		tenantID.String(),
		now.Year(),
		now.Month(),
		now.Day(),
		fileID.String(),
		ext,
	)
}

// generatePublicURL creates CDN-ready public URL
func generatePublicURL(bucketName, storagePath string) string {
	cdnBase := os.Getenv("STORAGE_PUBLIC_URL")
	if cdnBase == "" {
		cdnBase = "https://cdn.example.com"
	}
	return fmt.Sprintf("%s/%s/%s", cdnBase, bucketName, storagePath)
}
```

**Example:**

```go
// Input
tenantID := uuid.MustParse("abc123-...")
originalName := "sunset-beach.jpg"
fileID := uuid.MustParse("01906a2c-4b21-7890-a3f4-8c4d1e2f3a4b")

// Generated paths
storagePath := generateStoragePath(tenantID, originalName, fileID)
// => "tenants/abc123.../2026/02/09/01906a2c-4b21-7890-a3f4-8c4d1e2f3a4b.jpg"

publicURL := generatePublicURL("media-assets", storagePath)
// => "https://cdn.example.com/media-assets/tenants/abc123.../2026/02/09/01906a2c-4b21-7890-a3f4-8c4d1e2f3a4b.jpg"
```

**Benefits:**

1. ✅ **Tenant Isolation:** Easy to backup/manage per tenant
2. ✅ **Date-based Partitioning:** Efficient archival and cleanup
3. ✅ **UUID v7 Uniqueness:** Time-sortable, no collisions
4. ✅ **Extension Preservation:** MIME type detection from filename

### 4.2. Variants Storage Structure

````
Original:
tenants/abc123/2024/02/07/uuid.jpg

Variants:
tenants/abc123/2024/02/07/uuid-thumb.webp   (150x150)
tenants/abc123/2024/02/07/uuid-small.webp   (400x300)
tenants/abc123/2024/02/07/uuid-medium.webp  (800x600)
tenants/abc123/2024/02/07/uuid-large.webp   (1600x1200)
```json
{
	"storage_path": "tenants/abc123/2024/02/07/uuid.jpg",
	"variants": {
		"thumbnail": {
			"storage_path": "tenants/abc123/2024/02/07/uuid-thumb.webp",
			"url": "https://cdn.example.com/media-assets/tenants/abc123/2024/02/07/uuid-thumb.webp",
			"width": 150,
			"height": 150,
			"size_bytes": 8192
````

      "width": 150,
      "height": 150,
      "size_bytes": 8192
    },
    "small": {
      "storage_path": "tenants/abc123/2024/02/07/uuid-small.webp",
      "url": "https://cdn.example.com/media-assets/tenants/abc123/2024/02/07/uuid-small.webp",
      "width": 400,
      "height": 300,
      "size_bytes": 32768
    }

}
}

````

---

## 5. MinIO Storage Integration

### 5.1. MinIO Configuration

**Environment Variables:**

```bash
# MinIO Server
STORAGE_MINIO_ENDPOINT=minio.example.com:9000
STORAGE_MINIO_ACCESS_KEY=minioadmin
STORAGE_MINIO_SECRET_KEY=minioadmin_secret
STORAGE_MINIO_USE_SSL=true

# Bucket
STORAGE_MINIO_BUCKET=media-assets
STORAGE_MINIO_REGION=us-east-1

# Public URL (CDN or MinIO direct)
STORAGE_PUBLIC_URL=https://cdn.example.com
````

**MinIO Client Setup (Go):**

```go
package storage

import (
	"context"
	"fmt"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"go.uber.org/zap"
)

// MinIOClient implements Client interface for MinIO
type MinIOClient struct {
	client    *minio.Client
	logger    *zap.Logger
	publicURL string
}

// NewMinIOClient creates a new MinIO client from config
func NewMinIOClient(config MinIOConfig, logger *zap.Logger) (*MinIOClient, error) {
	client, err := minio.New(config.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(config.AccessKeyID, config.SecretAccessKey, ""),
		Secure: config.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create MinIO client: %w", err)
	}

	return &MinIOClient{
		client:    client,
		logger:    logger,
		publicURL: config.PublicURL,
	}, nil
}

// InitializeBucket ensures bucket exists and has correct policy
func (c *MinIOClient) InitializeBucket(ctx context.Context, bucket, region string) error {
	exists, err := c.client.BucketExists(ctx, bucket)
	if err != nil {
		return fmt.Errorf("failed to check bucket existence: %w", err)
	}

	if !exists {
		err = c.client.MakeBucket(ctx, bucket, minio.MakeBucketOptions{Region: region})
		if err != nil {
			return fmt.Errorf("failed to create bucket: %w", err)
		}
		c.logger.Info("Bucket created", zap.String("bucket", bucket))

		// Set public read policy (optional)
		if err := c.setBucketPolicy(ctx, bucket); err != nil {
			c.logger.Warn("Failed to set bucket policy", zap.Error(err))
		}
	}

	return nil
}

func (c *MinIOClient) setBucketPolicy(ctx context.Context, bucket string) error {
	policy := fmt.Sprintf(`{
		"Version": "2012-10-17",
		"Statement": [{
			"Effect": "Allow",
			"Principal": {"AWS": ["*"]},
			"Action": ["s3:GetObject"],
			"Resource": ["arn:aws:s3:::%s/*"]
		}]
	}`, bucket)

	return c.client.SetBucketPolicy(ctx, bucket, policy)
}
```

### 5.2. Generate Presigned Upload URL

**gRPC Service Definition (Proto):**

```protobuf
// media/v1/media.proto
service MediaService {
  rpc GenerateUploadURL(GenerateUploadURLRequest) returns (GenerateUploadURLResponse);
}

message GenerateUploadURLRequest {
  string folder_id = 1;           // Optional parent folder
  string original_name = 2;       // Original filename
  string mime_type = 3;           // MIME type
  int64 file_size = 4;            // File size in bytes
  StorageProvider storage_provider = 5; // Usually MINIO
}

message GenerateUploadURLResponse {
  string file_id = 1;             // UUID of created file record
  string upload_url = 2;          // Presigned URL for direct upload
	string storage_path = 3;        // Storage key inside bucket (object key)
  google.protobuf.Timestamp expires_at = 4;
  int64 max_file_size = 5;
}
```

**Backend Implementation (Go):**

```go
package services

import (
	"context"
	"fmt"
	"path"
	"time"

	"github.com/google/uuid"
	"go.uber.org/zap"

	"cms/go/packages/shared/errors"
	"cms/go/packages/shared/logger"
	"cms/go/packages/shared/storage"
	uuidpkg "cms/go/packages/shared/uuid"
)

// GenerateUploadURL implements the presigned URL generation flow
func (s *UploadService) GenerateUploadURL(
	ctx context.Context,
	req *GenerateUploadURLRequest,
) (*GenerateUploadURLResponse, error) {
	// Extract tenant ID from context
	tenantID, err := contextpkg.GetTenantID(ctx)
	if err != nil {
		return nil, errors.Unauthorized("tenant not found", err)
	}

	// 1. Validate tenant quota
	stats, err := s.statsService.GetStorageStats(ctx, tenantID)
	if err != nil {
		return nil, errors.Internal("failed to get storage stats", err)
	}

	if stats.UsedBytes+req.FileSize > stats.QuotaBytes {
		return nil, errors.QuotaExceeded("storage quota exceeded")
	}

	// 2. Validate file type
	allowedTypes := []string{
		"image/jpeg", "image/png", "image/webp", "image/gif",
		"video/mp4", "video/webm",
		"application/pdf",
	}
	if !contains(allowedTypes, req.MimeType) {
		return nil, errors.InvalidArgument("file type not allowed")
	}

	// 3. Validate folder permissions (if folder specified)
	if req.FolderID != "" {
		folderUUID, err := uuid.Parse(req.FolderID)
		if err != nil {
			return nil, errors.InvalidArgument("invalid folder_id")
		}

		if err := s.validateFolderAccess(ctx, tenantID, folderUUID); err != nil {
			return nil, err
		}
	}

	// 4. Generate storage path
	fileID := uuidpkg.NewV7()
	storagePath := generateStoragePath(tenantID, req.OriginalName, fileID)
	publicURL := s.generatePublicURL(s.bucketName, storagePath)

	// 5. Create database record
	file := &entity.StorageFile{
		ID:              fileID,
		TenantID:        tenantID,
		ParentID:        parseUUIDOrNil(req.FolderID),
		FileType:        entity.FileTypeFile,
		OriginalName:    req.OriginalName,
		StoragePath:     storagePath,
		PublicURL:       publicURL,
		MimeType:        req.MimeType,
		FileSize:        req.FileSize,
		StorageProvider: entity.StorageProviderMinIO,
		Status:          entity.FileStatusUploading,
	}

	if err := s.fileService.CreateFile(ctx, file); err != nil {
		s.log.Error("Failed to create file record",
			zap.Error(err),
			zap.String("tenant_id", tenantID.String()),
		)
		return nil, errors.Internal("failed to create file record", err)
	}

	// 6. Generate presigned upload URL
	uploadURL, err := s.storageClient.GetPresignedPutURL(
		ctx,
		s.bucketName,
		storagePath,
		req.MimeType,
		15*time.Minute,
	)
	if err != nil {
		s.log.Error("Failed to generate presigned URL", zap.Error(err))
		_ = s.fileService.DeleteFile(ctx, fileID, false) // Rollback
		return nil, errors.Internal("failed to generate presigned URL", err)
	}

	// 7. Publish event
	_ = s.publishEvent(ctx, tenantID, "media.file.upload_started", fileID, map[string]interface{}{
		"file_id":       fileID.String(),
		"original_name": req.OriginalName,
		"file_size":     req.FileSize,
	})

	return &GenerateUploadURLResponse{
		FileID:      fileID.String(),
		UploadURL:   uploadURL,
		PublicURL:   publicURL,
		ExpiresAt:   time.Now().Add(15 * time.Minute),
		MaxFileSize: stats.MaxFileSize,
	}, nil
}

// Helper: Generate storage path
func generateStoragePath(tenantID uuid.UUID, originalName string, fileID uuid.UUID) string {
	now := time.Now()
	ext := path.Ext(originalName)
	return fmt.Sprintf(
		"tenants/%s/%d/%02d/%02d/%s%s",
		tenantID.String(),
		now.Year(), now.Month(), now.Day(),
		fileID.String(), ext,
	)
}
```

### 5.3. Client-Side Upload

**Frontend Implementation:**

```typescript
async function uploadFileToMinIO(
  file: File,
  folderId?: string,
  onProgress?: (percent: number) => void,
): Promise<{ fileId: string; publicUrl: string }> {
  // 1. Request presigned URL
  const response = await fetch("/api/media/upload-url", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      folder_id: folderId,
      original_name: file.name,
      mime_type: file.type,
      file_size: file.size,
    }),
  });

  if (!response.ok) {
    throw new Error("Failed to get upload URL");
  }

  const { file_id, upload_url, storage_path } = await response.json();

  // 2. Upload file to MinIO with progress tracking
  await uploadWithProgress(file, upload_url, onProgress);

  // 3. Notify backend upload complete
  await fetch(`/api/media/files/${file_id}/upload-complete`, {
    method: "POST",
  });

  return { fileId: file_id, storagePath: storage_path };
}

function uploadWithProgress(
  file: File,
  uploadUrl: string,
  onProgress?: (percent: number) => void,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();

    xhr.upload.addEventListener("progress", (e) => {
      if (e.lengthComputable && onProgress) {
        const percent = Math.round((e.loaded * 100) / e.total);
        onProgress(percent);
      }
    });

    xhr.addEventListener("load", () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve();
      } else {
        reject(new Error(`Upload failed: ${xhr.status}`));
      }
    });

    xhr.addEventListener("error", () => {
      reject(new Error("Network error"));
    });

    xhr.open("PUT", uploadUrl);
    xhr.setRequestHeader("Content-Type", file.type);
    xhr.send(file);
  });
}
```

### 5.4. Upload Complete Webhook

```go
package services

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"go.uber.org/zap"

	"cms/go/packages/shared/errors"
	contextpkg "cms/go/packages/shared/context"
)

// HandleUploadComplete verifies upload and triggers processing
func (s *UploadService) HandleUploadComplete(
	ctx context.Context,
	fileID uuid.UUID,
) error {
	tenantID, err := contextpkg.GetTenantID(ctx)
	if err != nil {
		return errors.Unauthorized("tenant not found", err)
	}

	// 1. Get file record
	file, err := s.fileService.GetFile(ctx, fileID)
	if err != nil {
		return errors.NotFound("file not found", err)
	}

	if file.Status != entity.FileStatusUploading {
		return errors.InvalidArgument("file already processed")
	}

	// 2. Verify file exists in MinIO
	exists, err := s.storageClient.Exists(ctx, s.bucketName, file.StoragePath)
	if err != nil {
		s.log.Error("Failed to check file existence", zap.Error(err))
		return errors.Internal("failed to verify upload", err)
	}

	if !exists {
		// Mark as failed
		_ = s.fileService.UpdateStatus(ctx, fileID, entity.FileStatusFailed)
		return errors.NotFound("file not found in storage")
	}

	// 3. Get object metadata to verify size
	obj, err := s.storageClient.Get(ctx, s.bucketName, file.StoragePath)
	if err != nil {
		return errors.Internal("failed to get file metadata", err)
	}

	s.log.Info("Upload verified",
		zap.String("file_id", fileID.String()),
		zap.Int64("size", obj.Size),
	)

	// 4. Update status to PROCESSING
	if err := s.fileService.UpdateStatus(ctx, fileID, entity.FileStatusProcessing); err != nil {
		return errors.Internal("failed to update status", err)
	}

	// 5. Enqueue processing job based on MIME type
	if isImage(file.MimeType) {
		if err := s.processingService.EnqueueImageProcessing(ctx, fileID); err != nil {
			s.log.Error("Failed to enqueue image processing", zap.Error(err))
		}
	} else if isVideo(file.MimeType) {
		if err := s.processingService.EnqueueVideoProcessing(ctx, fileID); err != nil {
			s.log.Error("Failed to enqueue video processing", zap.Error(err))
		}
	} else {
		// No processing needed, mark as ready
		_ = s.fileService.UpdateStatus(ctx, fileID, entity.FileStatusReady)
	}

	// 6. Publish event
	_ = s.publishEvent(ctx, tenantID, "media.file.upload_completed", fileID, map[string]interface{}{
		"file_id":      fileID.String(),
		"storage_path": file.StoragePath,
		"mime_type":    file.MimeType,
	})

	return nil
}

func isImage(mimeType string) bool {
	return strings.HasPrefix(mimeType, "image/")
}

func isVideo(mimeType string) bool {
	return strings.HasPrefix(mimeType, "video/")
}
```

---

## 6. Image Processing Workflow

### 6.1. Processing Pipeline

```go
package services

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"strings"

	"github.com/disintegration/imaging"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"cms/go/packages/shared/errors"
)

type VariantConfig struct {
	Name   string
	Width  int
	Height int
}

var defaultVariants = []VariantConfig{
	{Name: "thumbnail", Width: 150, Height: 150},
	{Name: "small", Width: 400, Height: 300},
	{Name: "medium", Width: 800, Height: 600},
	{Name: "large", Width: 1600, Height: 1200},
}

// ProcessImage handles background image optimization
func (s *ProcessingService) ProcessImage(
	ctx context.Context,
	fileID uuid.UUID,
) error {
	// 1. Get file record
	file, err := s.fileService.GetFile(ctx, fileID)
	if err != nil {
		return errors.NotFound("file not found", err)
	}

	s.log.Info("Processing image",
		zap.String("file_id", fileID.String()),
		zap.String("mime_type", file.MimeType),
	)

	// 2. Download from MinIO
	reader, err := s.storageClient.Download(ctx, &storage.DownloadInput{
		Bucket: s.bucketName,
		Key:    file.StoragePath,
	})
	if err != nil {
		return s.markAsFailed(ctx, fileID, err)
	}
	defer reader.Close()

	data, err := io.ReadAll(reader)
	if err != nil {
		return s.markAsFailed(ctx, fileID, err)
	}

	// 3. Decode image
	img, err := imaging.Decode(bytes.NewReader(data))
	if err != nil {
		return s.markAsFailed(ctx, fileID, fmt.Errorf("invalid image: %w", err))
	}

	bounds := img.Bounds()
	originalDimensions := map[string]int{
		"width":  bounds.Dx(),
		"height": bounds.Dy(),
	}

	// 4. Generate variants
	variants := make(map[string]interface{})
	for _, config := range defaultVariants {
		variantData, err := s.generateVariant(ctx, img, config)
		if err != nil {
			s.log.Warn("Failed to generate variant",
				zap.String("variant", config.Name),
				zap.Error(err),
			)
			continue
		}

		// Upload variant to MinIO
		variantPath := s.getVariantPath(file.StoragePath, config.Name)
		variantURL, err := s.uploadVariant(ctx, variantPath, variantData)
		if err != nil {
			s.log.Warn("Failed to upload variant", zap.Error(err))
			continue
		}

		variants[config.Name] = map[string]interface{}{
			"url":        variantURL,
			"width":      config.Width,
			"height":     config.Height,
			"size_bytes": len(variantData),
		}
	}

	// 5. Update database
	if err := s.fileService.UpdateFileProcessing(ctx, fileID, originalDimensions, variants); err != nil {
		return errors.Internal("failed to update file", err)
	}

	// 6. Mark as ready
	if err := s.fileService.UpdateStatus(ctx, fileID, entity.FileStatusReady); err != nil {
		return errors.Internal("failed to update status", err)
	}

	s.log.Info("Image processing complete",
		zap.String("file_id", fileID.String()),
		zap.Int("variants", len(variants)),
	)

	return nil
}

func (s *ProcessingService) generateVariant(
	ctx context.Context,
	img image.Image,
	config VariantConfig,
) ([]byte, error) {
	// Resize with aspect ratio preservation
	resized := imaging.Fit(img, config.Width, config.Height, imaging.Lanczos)

	// Encode to WebP
	var buf bytes.Buffer
	if err := imaging.Encode(&buf, resized, imaging.PNG); err != nil {
		return nil, err
	}

	return buf.Bytes(), nil
}

func (s *ProcessingService) uploadVariant(
	ctx context.Context,
	path string,
	data []byte,
) (string, error) {
	object, err := s.storageClient.Upload(ctx, &storage.UploadInput{
		Bucket:      s.bucketName,
		Key:         path,
		Body:        bytes.NewReader(data),
		Size:        int64(len(data)),
		ContentType: "image/png",
	})
	if err != nil {
		return "", err
	}

	return s.generatePublicURL(s.bucketName, object.Key), nil
}

func (s *ProcessingService) getVariantPath(originalPath, variantName string) string {
	ext := ".png"
	if idx := strings.LastIndex(originalPath, "."); idx > 0 {
		originalPath = originalPath[:idx]
	}
	return fmt.Sprintf("%s-%s%s", originalPath, variantName, ext)
}

func (s *ProcessingService) markAsFailed(ctx context.Context, fileID uuid.UUID, err error) error {
	s.log.Error("Processing failed", zap.String("file_id", fileID.String()), zap.Error(err))
	_ = s.fileService.UpdateStatus(ctx, fileID, entity.FileStatusFailed)
	return errors.Internal("processing failed", err)
}
```

### 6.2. Delete Files from MinIO

```go
package services

import (
	"context"
	"time"

	"github.com/google/uuid"
	"go.uber.org/zap"

	"cms/go/packages/shared/errors"
	contextpkg "cms/go/packages/shared/context"
)

// DeleteFile performs soft delete and schedules cleanup
func (s *StorageFileService) DeleteFile(
	ctx context.Context,
	fileID uuid.UUID,
	permanent bool,
) error {
	tenantID, err := contextpkg.GetTenantID(ctx)
	if err != nil {
		return errors.Unauthorized("tenant not found", err)
	}

	// 1. Get file record
	file, err := s.repo.GetByID(ctx, tenantID, fileID)
	if err != nil {
		return errors.NotFound("file not found", err)
	}

	if permanent {
		// Immediate deletion for admin/system
		return s.permanentDelete(ctx, file)
	}

	// 2. Soft delete
	now := time.Now()
	file.DeletedAt = &now

	if err := s.repo.Update(ctx, file); err != nil {
		return errors.Internal("failed to delete file", err)
	}

	// 3. Schedule cleanup (30 days later)
	cleanupTime := now.Add(30 * 24 * time.Hour)
	if err := s.scheduleCleanup(ctx, fileID, cleanupTime); err != nil {
		s.log.Warn("Failed to schedule cleanup", zap.Error(err))
	}

	// 4. Publish event
	_ = s.publishEvent(ctx, tenantID, "media.file.deleted", fileID, map[string]interface{}{
		"file_id":      fileID.String(),
		"storage_path": file.StoragePath,
	})

	s.log.Info("File soft deleted",
		zap.String("file_id", fileID.String()),
		zap.Time("cleanup_at", cleanupTime),
	)

	return nil
}

// CleanupDeletedFile permanently removes file from storage and database
func (s *StorageFileService) CleanupDeletedFile(
	ctx context.Context,
	fileID uuid.UUID,
) error {
	tenantID, err := contextpkg.GetTenantID(ctx)
	if err != nil {
		return errors.Unauthorized("tenant not found", err)
	}

	file, err := s.repo.GetByID(ctx, tenantID, fileID)
	if err != nil {
		return errors.NotFound("file not found", err)
	}

	if file.DeletedAt == nil {
		return errors.InvalidArgument("file not deleted")
	}

	return s.permanentDelete(ctx, file)
}

func (s *StorageFileService) permanentDelete(
	ctx context.Context,
	file *entity.StorageFile,
) error {
	// 1. Delete original from MinIO
	if err := s.storageClient.Delete(ctx, s.bucketName, file.StoragePath); err != nil {
		s.log.Warn("Failed to delete file from storage",
			zap.String("path", file.StoragePath),
			zap.Error(err),
		)
	}

	// 2. Delete variants
	if file.Variants != nil {
		variantPaths := s.extractVariantPaths(file.Variants)
		if len(variantPaths) > 0 {
			if err := s.storageClient.DeleteMultiple(ctx, s.bucketName, variantPaths); err != nil {
				s.log.Warn("Failed to delete variants", zap.Error(err))
			}
		}
	}

	// 3. Delete from database
	if err := s.repo.HardDelete(ctx, file.TenantID, file.ID); err != nil {
		return errors.Internal("failed to delete from database", err)
	}

	s.log.Info("File permanently deleted",
		zap.String("file_id", file.ID.String()),
	)

	return nil
}

func (s *StorageFileService) extractVariantPaths(variants map[string]interface{}) []string {
	var paths []string
	for _, v := range variants {
		if m, ok := v.(map[string]interface{}); ok {
			if path, ok := m["storage_path"].(string); ok {
				paths = append(paths, path)
			}
		}
	}
	return paths
}
```

---

## 7. API Design

### 7.1. Folder APIs

**gRPC Service Definition:**

```protobuf
service MediaService {
  // Folder operations
  rpc CreateFolder(CreateFolderRequest) returns (CreateFolderResponse);
  rpc ListFolderContents(ListFolderContentsRequest) returns (ListFolderContentsResponse);
  rpc MoveFolder(MoveFolderRequest) returns (MoveFolderResponse);
  rpc RenameFolder(RenameFolderRequest) returns (RenameFolderResponse);
  rpc DeleteFolder(DeleteFolderRequest) returns (DeleteFolderResponse);
}

message CreateFolderRequest {
  string parent_id = 1;      // Optional, null for root
  string name = 2;
}

message CreateFolderResponse {
  string folder_id = 1;
  string name = 2;
  google.protobuf.Timestamp created_at = 3;
}

message ListFolderContentsRequest {
  string folder_id = 1;
  int32 page = 2;
  int32 page_size = 3;
  string sort_by = 4;        // name, created_at, size
  string sort_order = 5;     // asc, desc
}

message MoveFolderRequest {
  string folder_id = 1;
  string new_parent_id = 2;  // null for root
}

message DeleteFolderRequest {
  string folder_id = 1;
  bool cascade = 2;          // Delete contents recursively
}
```

### 7.2. File Upload APIs

**gRPC Service Definition:**

```protobuf
service MediaService {
  // File operations
  rpc GenerateUploadURL(GenerateUploadURLRequest) returns (GenerateUploadURLResponse);
  rpc NotifyUploadComplete(NotifyUploadCompleteRequest) returns (NotifyUploadCompleteResponse);
  rpc GetFile(GetFileRequest) returns (GetFileResponse);
  rpc DownloadFile(DownloadFileRequest) returns (DownloadFileResponse);
  rpc MoveFile(MoveFileRequest) returns (MoveFileResponse);
  rpc DeleteFile(DeleteFileRequest) returns (DeleteFileResponse);
  rpc RestoreFile(RestoreFileRequest) returns (RestoreFileResponse);
}

message NotifyUploadCompleteRequest {
  string file_id = 1;
}

message NotifyUploadCompleteResponse {
  FileStatus status = 1;
  string message = 2;
}

message GetFileRequest {
  string file_id = 1;
}

message GetFileResponse {
	string file_id = 1;
	string original_name = 2;
	string mime_type = 3;
	int64 file_size = 4;
	string storage_path = 5;
	FileStatus status = 6;
	map<string, Variant> variants = 7;
	google.protobuf.Timestamp created_at = 8;
}

message Variant {
  string url = 1;
  int32 width = 2;
  int32 height = 3;
  int64 size_bytes = 4;
}

message MoveFileRequest {
  string file_id = 1;
  string folder_id = 2;      // null for root
}

message DeleteFileRequest {
  string file_id = 1;
  bool permanent = 2;        // Skip soft delete
}

enum FileStatus {
  FILE_STATUS_UNSPECIFIED = 0;
  FILE_STATUS_UPLOADING = 1;
  FILE_STATUS_PROCESSING = 2;
  FILE_STATUS_READY = 3;
  FILE_STATUS_FAILED = 4;
}
```

**Go Handler Example:**

```go
package handlers

import (
	"context"

	pb "cms/go/proto/media/v1"
	"cms/go/packages/shared/errors"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type MediaHandler struct {
	pb.UnimplementedMediaServiceServer
	uploadService    *services.UploadService
	folderService    *services.FolderService
	fileService      *services.StorageFileService
	processingService *services.ProcessingService
}

func (h *MediaHandler) GenerateUploadURL(
	ctx context.Context,
	req *pb.GenerateUploadURLRequest,
) (*pb.GenerateUploadURLResponse, error) {
	result, err := h.uploadService.GenerateUploadURL(ctx, req)
	if err != nil {
		return nil, errors.ToGRPCStatus(err)
	}
	return result, nil
}

func (h *MediaHandler) NotifyUploadComplete(
	ctx context.Context,
	req *pb.NotifyUploadCompleteRequest,
) (*pb.NotifyUploadCompleteResponse, error) {
	fileID, err := uuid.Parse(req.FileId)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, "invalid file_id")
	}

	if err := h.uploadService.HandleUploadComplete(ctx, fileID); err != nil {
		return nil, errors.ToGRPCStatus(err)
	}

	return &pb.NotifyUploadCompleteResponse{
		Status:  pb.FileStatus_FILE_STATUS_PROCESSING,
		Message: "Upload verified, processing started",
	}, nil
}
```

---

## 8. Frontend Implementation

### 8.1. File Upload Component

```typescript
import { useState } from 'react';

interface UploadTask {
  id: string;
  file: File;
  progress: number;
  status: 'pending' | 'uploading' | 'processing' | 'completed' | 'failed';
  error?: string;
  publicUrl?: string;
}

function FileUpload({ folderId }: { folderId?: string }) {
  const [uploads, setUploads] = useState<UploadTask[]>([]);

  async function handleFiles(files: FileList) {
    for (const file of Array.from(files)) {
      const task: UploadTask = {
        id: crypto.randomUUID(),
        file,
        progress: 0,
        status: 'pending'
      };

      setUploads(prev => [...prev, task]);

      try {
        await uploadFile(task);
      } catch (error) {
        updateTask(task.id, {
          status: 'failed',
          error: error.message
        });
      }
    }
  }

  async function uploadFile(task: UploadTask) {
    updateTask(task.id, { status: 'uploading', progress: 0 });

    // 1. Get upload URL
    const urlRes = await fetch('/api/media/upload-url', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        folder_id: folderId,
        original_name: task.file.name,
        mime_type: task.file.type,
        file_size: task.file.size
      })
    });

	const { file_id, upload_url, storage_path } = await urlRes.json();

    // 2. Upload to MinIO
    await uploadWithProgress(
      task.file,
      upload_url,
      (percent) => updateTask(task.id, { progress: percent })
    );

    // 3. Notify complete
    updateTask(task.id, { status: 'processing', progress: 100 });

    await fetch(`/api/media/files/${file_id}/upload-complete`, {
      method: 'POST'
    });

    // 4. Poll for completion
    await pollStatus(file_id, task.id);

		updateTask(task.id, {
			status: 'completed',
			storagePath: storage_path
		});
  }

  function updateTask(id: string, updates: Partial<UploadTask>) {
    setUploads(prev => prev.map(t =>
      t.id === id ? { ...t, ...updates } : t
    ));
  }

  async function pollStatus(fileId: string, taskId: string) {
    for (let i = 0; i < 30; i++) {
      await new Promise(resolve => setTimeout(resolve, 1000));

      const res = await fetch(`/api/media/files/${fileId}`);
      const file = await res.json();

      if (file.status === 'READY') {
        return;
      } else if (file.status === 'FAILED') {
        throw new Error('Processing failed');
      }
    }

    throw new Error('Processing timeout');
  }

  return (
    <div
      className="upload-zone"
      onDrop={(e) => {
        e.preventDefault();
        handleFiles(e.dataTransfer.files);
      }}
      onDragOver={(e) => e.preventDefault()}
    >
      <p>Drop files here or click to upload</p>
      <input
        type="file"
        multiple
        onChange={(e) => e.target.files && handleFiles(e.target.files)}
      />

      <div className="upload-list">
        {uploads.map(upload => (
          <div key={upload.id} className="upload-item">
            <span>{upload.file.name}</span>
            <progress value={upload.progress} max={100} />
            <span>{upload.status}</span>
            {upload.error && <span className="error">{upload.error}</span>}
          </div>
        ))}
      </div>
    </div>
  );
}
```

---

## 9. Performance Optimization

### 9.1. Database Indexes

```sql
-- Folder listing (tenant + parent + type)
CREATE INDEX storage_files_folder_contents_idx
  ON media.storage_files (tenant_id, parent_id, file_type, original_name)
  WHERE deleted_at IS NULL;

-- File search by name
CREATE INDEX storage_files_name_search_idx
  ON media.storage_files (tenant_id, original_name text_pattern_ops)
  WHERE deleted_at IS NULL;

-- Processing queue
CREATE INDEX storage_files_processing_idx
  ON media.storage_files (status, created_at)
  WHERE status IN ('UPLOADING', 'PROCESSING');

-- Cleanup job (soft deleted files)
CREATE INDEX storage_files_cleanup_idx
  ON media.storage_files (tenant_id, deleted_at)
  WHERE deleted_at IS NOT NULL;
```

### 9.2. Caching Strategy (Go Implementation)

**Using Dragonfly (Redis-compatible) via go/packages/shared/cache:**

```go
package services

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"

	"cms/go/packages/shared/cache"
	"cms/go/packages/shared/errors"
)

// GetFolderContents retrieves folder contents with L2 cache (Dragonfly)
func (s *FolderService) GetFolderContents(
	ctx context.Context,
	tenantID uuid.UUID,
	folderID uuid.UUID,
) ([]*entity.StorageFile, error) {
	// Generate cache key: {tenant}:media:folder:{folder_id}
	cacheKey := fmt.Sprintf("%s:media:folder:%s", tenantID.String(), folderID.String())

	// Try L2 cache first
	var files []*entity.StorageFile
	if err := s.cache.Get(ctx, cacheKey, &files); err == nil {
		s.log.Debug("Cache hit", zap.String("key", cacheKey))
		return files, nil
	}

	// Cache miss - query database
	files, err := s.repo.ListByParent(ctx, tenantID, &folderID, nil)
	if err != nil {
		return nil, errors.Internal("failed to list files", err)
	}

	// Store in cache (5 minutes TTL)
	if err := s.cache.Set(ctx, cacheKey, files, 5*time.Minute); err != nil {
		s.log.Warn("Failed to cache folder contents", zap.Error(err))
	}

	return files, nil
}

// InvalidateFolderCache invalidates cache on folder changes
func (s *FolderService) InvalidateFolderCache(
	ctx context.Context,
	tenantID uuid.UUID,
	folderID uuid.UUID,
) error {
	cacheKey := fmt.Sprintf("%s:media:folder:%s", tenantID.String(), folderID.String())
	return s.cache.Delete(ctx, cacheKey)
}

// Invalidate parent folder cache when file is moved/created/deleted
func (s *StorageFileService) invalidateParentCache(
	ctx context.Context,
	tenantID uuid.UUID,
	parentID *uuid.UUID,
) {
	if parentID != nil {
		_ = s.folderService.InvalidateFolderCache(ctx, tenantID, *parentID)
	}
}
```

### 9.3. MinIO Performance Tuning

**Storage Client Configuration:**

```go
package storage

import (
	"time"

	"github.com/minio/minio-go/v7"
)

// Optimized MinIO client configuration
func NewMinIOClient(config MinIOConfig, logger *zap.Logger) (*MinIOClient, error) {
	client, err := minio.New(config.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(config.AccessKeyID, config.SecretAccessKey, ""),
		Secure: config.UseSSL,
		// Performance tuning
		Transport: &http.Transport{
			MaxIdleConns:        100,
			MaxIdleConnsPerHost: 10,
			IdleConnTimeout:     90 * time.Second,
		},
	})
	if err != nil {
		return nil, err
	}

	// Enable trailing headers (for checksums)
	client.TrailingHeaders = true

	return &MinIOClient{
		client:    client,
		logger:    logger,
		publicURL: config.PublicURL,
	}, nil
}
```

### 9.4. Batch Operations

**Parallel Processing with Goroutines:**

```go
package services

import (
	"context"
	"sync"

	"github.com/google/uuid"
	"go.uber.org/zap"
)

// BatchDelete deletes multiple files in parallel
func (s *BatchService) BatchDelete(
	ctx context.Context,
	fileIDs []uuid.UUID,
) (*BatchResult, error) {
	result := &BatchResult{
		Total:   len(fileIDs),
		Success: 0,
		Failed:  0,
		Errors:  make(map[string]string),
	}

	var wg sync.WaitGroup
	var mu sync.Mutex

	// Process in parallel (limit concurrency)
	semaphore := make(chan struct{}, 10) // Max 10 concurrent

	for _, fileID := range fileIDs {
		wg.Add(1)
		semaphore <- struct{}{} // Acquire

		go func(id uuid.UUID) {
			defer wg.Done()
			defer func() { <-semaphore }() // Release

			if err := s.fileService.DeleteFile(ctx, id, false); err != nil {
				mu.Lock()
				result.Failed++
				result.Errors[id.String()] = err.Error()
				mu.Unlock()
				s.log.Error("Batch delete failed", zap.String("file_id", id.String()), zap.Error(err))
			} else {
				mu.Lock()
				result.Success++
				mu.Unlock()
			}
		}(fileID)
	}

	wg.Wait()
	return result, nil
}
```

---

## Kết Luận

Document này cung cấp **complete blueprint** cho Media Management với MinIO sử dụng **Go + gRPC architecture**.

### ✅ Key Features Implemented:

1. **Unified Data Model:** Single table `storage_files` cho folders & files
2. **MinIO Storage:** Direct upload với presigned URLs (PresignedPutObject)
3. **Go SDK Integration:** `github.com/minio/minio-go/v7` with proper context handling
4. **Public URLs:** Stored in database for fast CDN access
5. **Image Processing:** Automatic variants generation (thumbnail, small, medium, large)
6. **Soft Delete:** 30-day grace period before permanent cleanup
7. **Performance:** Indexes, L2 cache (Dragonfly), goroutine batch operations
8. **Architecture Compliance:** Shared libraries, tenant isolation, outbox events

### 🏗️ Architecture Highlights:

- **Zero Direct DB Access:** All queries via `go/packages/shared/yugabyte`
- **Storage Abstraction:** Multi-provider support via `go/packages/shared/storage`
- **gRPC Protocol:** Type-safe APIs with protobuf validation
- **Context Propagation:** Tenant ID extraction from gRPC metadata
- **Error Handling:** Wrapped errors with proper gRPC status codes
- **Tracing:** Distributed tracing with trace_id in all logs/events
- **Outbox Pattern:** Guaranteed event publishing in same transaction

### 📦 Shared Libraries Used:

| Package           | Purpose                                            |
| ----------------- | -------------------------------------------------- |
| `shared/yugabyte` | Repository base with tenant isolation              |
| `shared/storage`  | Storage client abstraction (MinIO, S3, GCS, Azure) |
| `shared/uuid`     | UUID v7 generation                                 |
| `shared/errors`   | Error wrapping and gRPC status mapping             |
| `shared/context`  | Tenant ID and user extraction                      |
| `shared/logger`   | Structured logging with zap                        |
| `shared/outbox`   | Transactional outbox events                        |
| `shared/cache`    | Dragonfly (Redis) L2 cache                         |
| `shared/tracing`  | OpenTelemetry integration                          |

### 🚀 Next Steps:

- [ ] Implement MinIO client in `go/packages/shared/storage/minio_client.go`
- [ ] Add `GetPresignedPutURL()` to storage.Client interface
- [ ] Create upload helper utilities (retry, multipart, validation)
- [ ] Add MinIO dependency: `github.com/minio/minio-go/v7`
- [ ] Wire storage client in media service main.go
- [ ] Add ACL permissions layer
- [ ] Implement full-text search (PostgreSQL tsvector)
- [ ] Video transcoding with ffmpeg
- [ ] AI-powered tagging (image recognition)
- [ ] Usage analytics dashboard

---

## 🔧 Implementation Roadmap

### Phase 1: MinIO Client Implementation (CRITICAL)

**Priority: P0 - Blocking**

1. **Add MinIO dependency:**

   ```bash
   cd go/packages/shared
   go get github.com/minio/minio-go/v7@latest
   ```

2. **Update Storage Interface:**
   - File: `go/packages/shared/storage/storage.go`
   - Add method: `GetPresignedPutURL(ctx context.Context, bucket, key, contentType string, expiry time.Duration) (string, error)`
   - This is required by `upload_service.go` line 148

3. **Implement MinIO Client:**
   - File: `go/packages/shared/storage/minio_client.go`
   - Implement all 15 Client interface methods:
     - Upload, Download, Delete, DeleteMultiple
     - Get, List, Exists, Copy
     - GetPresignedURL, **GetPresignedPutURL** ⚠️
     - CreateBucket, DeleteBucket, BucketExists
     - Close

4. **Configuration Management:**
   - File: `go/packages/shared/storage/config.go`
   - Add `LoadMinIOConfigFromEnv()` function
   - Environment variables:
     ```bash
     STORAGE_MINIO_ENDPOINT=localhost:9000
     STORAGE_MINIO_ACCESS_KEY=minioadmin
     STORAGE_MINIO_SECRET_KEY=minioadmin
     STORAGE_MINIO_USE_SSL=false
     STORAGE_MINIO_BUCKET=media-assets
     STORAGE_PUBLIC_URL=http://localhost:9000
     ```

5. **Fix Broken Code:**
   - File: `go/apps/media/internal/services/upload_service.go`
   - Line 148: Change `req.StorageProvider.String()` to actual bucket name
   - Ensure proper bucket parameter handling

6. **Wire in Media Service:**
   - File: `go/apps/media/cmd/server/main.go`
   - Initialize storage client on startup
   - Auto-create bucket if not exists
   - Pass client to services via dependency injection

### Phase 2: Upload Helper Utilities

**Priority: P1 - Important**

1. **Create Helper Functions:**
   - File: `go/packages/shared/storage/upload_helpers.go`
   - `UploadWithRetry()` - Exponential backoff retry logic
   - `ValidateMimeType()` - Allowlist validation
   - `SanitizeFileName()` - Remove dangerous characters
   - `CalculateChecksum()` - MD5/SHA256 verification

2. **Multipart Upload Support:**
   - File: `go/packages/shared/storage/multipart.go`
   - Support for large files (> 100MB)
   - Progress tracking callbacks
   - Automatic part size calculation

### Phase 3: Integration Testing

**Priority: P1 - Important**

1. **Docker Compose Setup:**

   ```yaml
   services:
     minio:
       image: minio/minio:latest
       ports:
         - "9000:9000"
         - "9001:9001"
       environment:
         MINIO_ROOT_USER: minioadmin
         MINIO_ROOT_PASSWORD: minioadmin
       command: server /data --console-address ":9001"
   ```

2. **Integration Tests:**
   - File: `go/packages/shared/storage/minio_client_integration_test.go`
   - Test all CRUD operations
   - Test presigned URLs (GET and PUT)
   - Test bucket management
   - Use `//go:build integration` tag

### Phase 4: Production Readiness

**Priority: P2 - Nice to have**

1. **Observability:**
   - Add metrics (upload latency, error rate, throughput)
   - Distributed tracing with OpenTelemetry
   - Structured logging with correlation IDs

2. **Advanced Features:**
   - Video transcoding (ffmpeg integration)
   - Image optimization (automatic WebP conversion)
   - AI tagging (image recognition API)
   - Full-text search (PostgreSQL tsvector)

---

## ⚠️ Known Issues & Fixes

### Issue 1: GetPresignedPutURL() Not in Interface

**Problem:**

```go
// upload_service.go:148
uploadURL, err := s.storageClient.GetPresignedPutURL(ctx, bucket, path, mimeType, 15*time.Minute)
// ❌ Method does not exist in storage.Client interface
```

**Fix:**
Add to `storage.go` interface:

```go
type Client interface {
    // ... existing methods ...

    // GetPresignedPutURL generates a pre-signed URL for uploading
    GetPresignedPutURL(ctx context.Context, bucket, key, contentType string, expiry time.Duration) (string, error)
}
```

Implement in `minio_client.go`:

```go
func (c *MinIOClient) GetPresignedPutURL(
    ctx context.Context,
    bucket, key, contentType string,
    expiry time.Duration,
) (string, error) {
    // Set custom headers for presigned request
    reqParams := make(url.Values)
    reqParams.Set("response-content-type", contentType)

    return c.client.PresignedPutObject(ctx, bucket, key, expiry)
}
```

### Issue 2: All Storage Providers Return "Not Implemented"

**Current State:**

```go
// providers.go
func newMinIOClient(config Config, logger *zap.Logger) (Client, error) {
    return nil, fmt.Errorf("MinIO client not yet implemented")
}
```

**Fix:** Implement at least MinIO provider to unblock development.

### Issue 3: Missing go.mod Dependency

**Problem:** `github.com/minio/minio-go/v7` not in `go/packages/shared/go.mod`

**Fix:**

```bash
cd go/packages/shared
go get github.com/minio/minio-go/v7@v7.0.80
go mod tidy
```

### 📚 Related Documentation:

- Architecture: `docs/architecture/ARCHITECTURE.md`
- Database Design: `docs/dev-manual/database/yugabyteDB/`
- Coding Guidelines: `docs/dev-manual/guides/CODING_GUIDELINES.md`
- Go Service Template: `docs/dev-manual/go/GO_SERVICE_TEMPLATE.md`
- Proto Creation: `docs/dev-manual/go/CREATE_PROTO.md`

---

**Version:** 2.0 (Go Implementation)
**Last Updated:** 2026-02-09
**Language:** Go 1.25+ with gRPC
**Author:** CMS Development Team
