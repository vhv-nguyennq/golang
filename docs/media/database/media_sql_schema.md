# Media Service - SQL Schema (YugabyteDB)

**Schema:** `public`
**Database:** YugabyteDB (YSQL)
**Version:** 2.0
**Generated:** 2026-02-06

---

## Schema

```sql
CREATE SCHEMA IF NOT EXISTS public;
```

---

## Table: storage_files

```sql
CREATE TABLE IF NOT EXISTS public.storage_files (
    id UUID PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    parent_id UUID NULL,
    file_type TEXT NOT NULL DEFAULT 'FILE' CHECK (file_type IN ('FOLDER', 'FILE')),
    original_name TEXT NOT NULL CHECK (length(original_name) > 0),
    storage_path TEXT NOT NULL,
    public_url TEXT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size BIGINT NOT NULL DEFAULT 0 CHECK (file_size >= 0),
    dimensions JSONB NOT NULL DEFAULT '{}',
    alt_text TEXT NULL,
    caption TEXT NULL,
    variants JSONB NOT NULL DEFAULT '{}',
    metadata JSONB NOT NULL DEFAULT '{}',
    storage_provider VARCHAR(20) NOT NULL DEFAULT 'S3' CHECK (storage_provider IN ('S3', 'R2', 'MINIO', 'CLOUDFLARE')),
    visibility VARCHAR(20) NOT NULL DEFAULT 'PRIVATE' CHECK (visibility IN ('PUBLIC', 'PRIVATE', 'INTERNAL')),
    status VARCHAR(20) NOT NULL DEFAULT 'PROCESSING' CHECK (status IN ('UPLOADING', 'PROCESSING', 'READY', 'FAILED')),
    uploaded_by TEXT NULL,
    created_by TEXT NULL,
    updated_by TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now() CHECK (updated_at >= created_at),
    deleted_at TIMESTAMPTZ NULL,
    version BIGINT NOT NULL DEFAULT 1 CHECK (version >= 1),
    UNIQUE (tenant_id, storage_path)
);
```

---

## Indexes

```sql
-- Sharding / tenant isolation
CREATE INDEX IF NOT EXISTS storage_files_tenant_hash_idx
    ON public.storage_files (tenant_id HASH);

-- Common lookups by tenant, status, time
CREATE INDEX IF NOT EXISTS storage_files_tenant_status_created_idx
    ON public.storage_files (tenant_id HASH, status ASC, created_at DESC);

-- JSONB search
CREATE INDEX IF NOT EXISTS storage_files_metadata_ybgin_idx
    ON public.storage_files USING ybgin (metadata);

-- Soft delete filter
CREATE INDEX IF NOT EXISTS storage_files_not_deleted_idx
    ON public.storage_files (tenant_id HASH, created_at DESC)
    WHERE deleted_at IS NULL;
```
