# Tài liệu CSDL Crawler

## Danh sách bảng

| Tên bảng | Loại bảng | Mô tả |
| --- | --- | --- |
| crawler.campaigns | YugabyteDB | Quản lý chiến dịch thu thập dữ liệu. |
| crawler.sources | YugabyteDB | Nguồn thu thập, URL gốc, engine và cấu hình truy xuất. |
| crawler.categories | YugabyteDB | Danh mục thu thập theo cây phân cấp. |
| crawler.source_categories | YugabyteDB | Liên kết nhiều danh mục với một nguồn. |
| crawler.extractor_profiles | YugabyteDB | Cấu hình bóc tách (thủ công/AI), schema, phân trang. |
| crawler.parser_presets | YugabyteDB | (Đã gộp) preset parser nằm trong `crawler.extractor_profiles.parser_presets`. |
| crawler.format_configs | YugabyteDB | (Đã gộp) cấu hình định dạng nằm trong `crawler.source_endpoints.format_config`. |
| crawler.network_profiles | YugabyteDB | Cấu hình proxy, headers, init script, hành vi giả lập. |
| crawler.auth_profiles | YugabyteDB | Cấu hình xác thực cho nguồn bảo vệ. |
| crawler.schedules | YugabyteDB | Lịch chạy (cron/interval/manual). |
| crawler.jobs | YugabyteDB | Định nghĩa job tự động/thủ công. |
| crawler.execution_runs | YugabyteDB | Cửa sổ thực thi (window start/end, SLA) theo chiến dịch. |
| crawler.runs | YugabyteDB | Lưu trạng thái và kết quả từng lần chạy (liên kết execution_runs). |
| crawler.source_rules | YugabyteDB | Chính sách politeness, rate limit theo nguồn. |
| crawler.source_rule_snapshots | YugabyteDB | Snapshot policy với version để rollback khi crawler lỗi. |
| crawler.source_endpoints | YugabyteDB | Nhiều endpoint (RSS, API, sitemap, HLS) cho một nguồn. |
| crawler.url_frontier | YugabyteDB | Hàng đợi URL active, retry, ưu tiên (lịch sử → ClickHouse). |
| crawler.items | YugabyteDB | Nội dung đã bóc tách (hash partitioned by source_id, TTL 30 ngày). |
| crawler.item_deduplication_log | YugabyteDB | Lịch sử phát hiện trùng lặp (URL, content, canonical, dedupe_key). |
| crawler.item_processing_stages | YugabyteDB | Pipeline xử lý từ raw ingest → AI processing → normalized content. |
| crawler.routing_rules | YugabyteDB | Quy tắc định tuyến dữ liệu sang tenant/section đích. |
| crawler_execution_logs | ClickHouse | Nhật ký thực thi crawler (telemetry). |
| crawler_source_metrics | ClickHouse | SLO/SLI metrics (latency, success_rate, retries) đo chất lượng nguồn. |
| crawler_url_frontier_log | ClickHouse | Lịch sử URL frontier (PENDING → PROCESSING → DONE/FAILED). |

## crawler.campaigns

Quản lý chiến dịch thu thập dữ liệu.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| code | varchar(50) | NO |  | UNIQUE (tenant_id, code), CHECK code ~ '^[a-z0-9_-]+$' | Mã chiến dịch. |
| name | text | NO |  | CHECK length(name) > 0 | Tên chiến dịch. |
| description | text | YES | NULL |  | Mô tả chiến dịch. |
| status | varchar(20) | NO | ACTIVE | CHECK status IN (ACTIVE, PAUSED, ARCHIVED) | Trạng thái chiến dịch. |
| priority | int4 | NO | 0 | CHECK priority >= 0 | Độ ưu tiên. |
| settings | jsonb | NO | {} |  | Cài đặt chiến dịch. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.sources

Nguồn thu thập với URL gốc, engine và cấu hình.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| campaign_id | UUID | NO |  | FK -> crawler.campaigns(id) | Thuộc chiến dịch. |
| code | varchar(50) | NO |  | UNIQUE (tenant_id, campaign_id, code), CHECK code ~ '^[a-z0-9_-]+$' | Mã nguồn. |
| name | text | NO |  | CHECK length(name) > 0 | Tên nguồn. |
| seed_url | text | NO |  | CHECK seed_url ~* '^https?://' | URL khởi điểm. |
| source_type | varchar(20) | NO | NEWS | CHECK source_type IN (NEWS, VIDEO, DOCUMENT, MIXED, RSS, API, FILE, STREAM) | Loại nguồn. |
| engine_type | varchar(20) | NO | HTTP | CHECK engine_type IN (HTTP, BROWSER, SESSION) | Engine xử lý. |
| default_language | varchar(10) | YES | NULL |  | Ngôn ngữ mặc định. |
| content_types | jsonb | NO | [] | CHECK jsonb_typeof(content_types) = 'array' | Các loại nội dung. |
| is_active | bool | NO | true |  | Kích hoạt nguồn. |
| crawl_depth | int4 | NO | 2 | CHECK crawl_depth >= 0 | Độ sâu thu thập. |
| max_pages | int4 | NO | 0 | CHECK max_pages >= 0 | 0 = không giới hạn. |
| schedule_id | UUID | YES | NULL | FK -> crawler.schedules(id) | Lịch chạy. |
| extractor_profile_id | UUID | YES | NULL | FK -> crawler.extractor_profiles(id) | Cấu hình bóc tách. |
| network_profile_id | UUID | YES | NULL | FK -> crawler.network_profiles(id) | Cấu hình mạng/proxy. |
| auth_profile_id | UUID | YES | NULL | FK -> crawler.auth_profiles(id) | Cấu hình xác thực. |
| headers | jsonb | NO | {} |  | Header bổ sung. |
| cookies | jsonb | NO | {} |  | Cookie mặc định. |
| metadata | jsonb | NO | {} |  | Meta thông tin. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.categories

Bảng danh mục phân cấp.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| campaign_id | UUID | NO |  | FK -> crawler.campaigns(id) | Thuộc chiến dịch. |
| code | varchar(50) | NO |  | UNIQUE (tenant_id, campaign_id, code) | Mã danh mục. |
| name | text | NO |  | CHECK length(name) > 0 | Tên danh mục. |
| description | text | YES | NULL |  | Mô tả. |
| parent_id | UUID | YES | NULL | FK -> crawler.categories(id) | Danh mục cha. |
| is_active | bool | NO | true |  | Kích hoạt danh mục. |
| priority | int4 | NO | 0 | CHECK priority >= 0 | Thứ tự ưu tiên. |
| routing_key | varchar(100) | YES | NULL |  | Khóa định tuyến (nếu cần). |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.source_categories

Liên kết nhiều danh mục cho một nguồn.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| source_id | UUID | NO |  | FK -> crawler.sources(id) | Nguồn. |
| category_id | UUID | NO |  | FK -> crawler.categories(id) | Danh mục. |
| is_primary | bool | NO | false |  | Danh mục chính. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.extractor_profiles

Hồ sơ bóc tách (thủ công/AI).

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| code | varchar(50) | NO |  | UNIQUE (tenant_id, code) | Mã hồ sơ. |
| name | text | NO |  | CHECK length(name) > 0 | Tên hồ sơ. |
| mode | varchar(20) | NO | MANUAL | CHECK mode IN (MANUAL, AI, HYBRID) | Chế độ bóc tách. |
| config | jsonb | NO | {} |  | Cấu hình selector/schema. |
| parser_presets | jsonb | NO | [] | CHECK jsonb_typeof(parser_presets) = 'array' | Danh sách preset parser gắn theo extractor. |
| parser_presets_version | int4 | NO | 1 | CHECK parser_presets_version >= 1 | Phiên bản cấu hình preset parser. |
| preprocess_config | jsonb | NO | {} |  | DOM pruning, chunking. |
| pagination_config | jsonb | NO | {} |  | Phân trang và next page. |
| dedup_config | jsonb | NO | {} |  | Cấu hình trùng lặp. |
| validation_config | jsonb | NO | {} |  | Kiểm tra bắt buộc. |
| is_active | bool | NO | true |  | Kích hoạt. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

### Quy ước schema mẫu cho `parser_presets`

`parser_presets` là mảng JSON, mỗi phần tử biểu diễn một preset. Khuyến nghị cấu trúc:

```json
[
	{
		"name": "rss_default",
		"format": "RSS",
		"config_version": 1,
		"enabled": true,
		"selectors": {
			"title": "title",
			"link": "link",
			"published_at": "pubDate",
			"summary": "description"
		},
		"mapping": {
			"title": "title",
			"url": "link",
			"published_at": "published_at",
			"summary": "summary"
		},
		"filters": {
			"include_keywords": ["kinh te", "tai chinh"],
			"exclude_keywords": ["quang cao"]
		}
	}
]
```

Schema ràng buộc tối thiểu:
- `name` (string, bắt buộc)
- `format` (string, bắt buộc, enum: RSS, ATOM, SITEMAP, JSON_API, HTML, PDF_OCR, IMAGE_OCR, HLS, M3U8)
- `config_version` (int, mặc định 1)
- `enabled` (bool, mặc định true)
- `selectors` (object, tùy chọn)
- `mapping` (object, tùy chọn)
- `filters` (object, tùy chọn)

Gợi ý:
- `selectors` và `mapping` nên đi theo cặp để ánh xạ dữ liệu thống nhất.

## crawler.parser_presets

Preset parser theo định dạng nguồn.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| code | varchar(50) | NO |  | UNIQUE (tenant_id, code) | Mã preset. |
| name | text | NO |  | CHECK length(name) > 0 | Tên preset. |
| format_type | varchar(20) | NO | HTML | CHECK format_type IN (HTML, RSS, ATOM, SITEMAP, API, HLS, M3U8, FILE, JSON, XML) | Định dạng nguồn. |
| config | jsonb | NO | {} |  | Cấu hình parser. |
| is_active | bool | NO | true |  | Kích hoạt. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.format_configs

Cấu hình theo định dạng nguồn (dùng chung cho RSS, sitemap, API, HLS...).

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| code | varchar(50) | NO |  | UNIQUE (tenant_id, code) | Mã cấu hình. |
| name | text | NO |  | CHECK length(name) > 0 | Tên cấu hình. |
| format_type | varchar(20) | NO | RSS | CHECK format_type IN (RSS, SITEMAP, ATOM, API, JSON_API, HLS, M3U8, FILE, JSON, XML, HTML) | Loại định dạng. |
| config | jsonb | NO | {} | CHECK jsonb_typeof(config) = 'object' | Cấu hình chi tiết theo định dạng. |
| is_active | bool | NO | true |  | Kích hoạt. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.network_profiles

Cấu hình proxy, headers, init script và hành vi.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| code | varchar(50) | NO |  | UNIQUE (tenant_id, code) | Mã hồ sơ. |
| name | text | NO |  | CHECK length(name) > 0 | Tên hồ sơ. |
| proxy_mode | varchar(20) | NO | DIRECT | CHECK proxy_mode IN (DIRECT, ROTATING, STATIC) | Chế độ proxy. |
| proxy_config | jsonb | NO | {} |  | Cấu hình proxy/pool. |
| user_agent_strategy | varchar(20) | NO | ROTATE | CHECK user_agent_strategy IN (FIXED, ROTATE) | Chiến lược UA. |
| headers | jsonb | NO | {} |  | Header bổ sung. |
| cookies | jsonb | NO | {} |  | Cookie mặc định. |
| init_scripts | jsonb | NO | [] |  | Script khởi tạo trình duyệt. |
| behavior_config | jsonb | NO | {} |  | Scroll, delay, random. |
| is_active | bool | NO | true |  | Kích hoạt. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.auth_profiles

Cấu hình xác thực cho nguồn bảo vệ.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| code | varchar(50) | NO |  | UNIQUE (tenant_id, code) | Mã hồ sơ. |
| name | text | NO |  | CHECK length(name) > 0 | Tên hồ sơ. |
| auth_type | varchar(20) | NO | NONE | CHECK auth_type IN (NONE, BASIC, BEARER, COOKIE, FORM, OAUTH2, API_KEY) | Kiểu xác thực. |
| config | jsonb | NO | {} |  | Cấu hình xác thực. |
| token_url | text | YES | NULL | CHECK (auth_type <> 'OAUTH2' OR token_url IS NOT NULL) | Token URL nếu dùng OAUTH2. |
| token_refresh_url | text | YES | NULL |  | Refresh token URL. |
| is_active | bool | NO | true |  | Kích hoạt. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.source_rules

Chính sách politeness và giới hạn theo nguồn.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| source_id | UUID | NO |  | FK -> crawler.sources(id) | Nguồn áp dụng. |
| respect_robots | bool | NO | true |  | Tôn trọng robots.txt. |
| user_agent | text | YES | NULL |  | User-Agent áp dụng. |
| crawl_delay_seconds | int4 | NO | 0 | CHECK crawl_delay_seconds >= 0 | Độ trễ crawl. |
| max_concurrency | int4 | NO | 1 | CHECK max_concurrency >= 1 | Số kết nối song song. |
| rate_limit_per_min | int4 | NO | 0 | CHECK rate_limit_per_min >= 0 | Giới hạn/phút, 0 = không giới hạn. |
| max_requests_per_run | int4 | NO | 0 | CHECK max_requests_per_run >= 0 | Giới hạn request/lần chạy. |
| allow_patterns | jsonb | NO | [] |  | Danh sách pattern được phép. |
| deny_patterns | jsonb | NO | [] | CHECK jsonb_typeof(deny_patterns) = 'array' | Danh sách pattern chặn. |
| headers_override | jsonb | NO | {} | CHECK jsonb_typeof(headers_override) = 'object' | Ghi đè header. |
| is_active | bool | NO | true |  | Kích hoạt. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.source_rule_snapshots

Snapshot policy với version để rollback policy khi crawler lỗi.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| source_id | UUID | NO |  | FK -> crawler.sources(id) | Nguồn áp dụng. |
| source_rule_id | UUID | NO |  | FK -> crawler.source_rules(id) | Source rule gốc. |
| snapshot_version | int4 | NO |  | UNIQUE (tenant_id, source_id, snapshot_version), CHECK snapshot_version >= 1 | Version snapshot. |
| snapshot_at | timestamptz | NO | now() |  | Thời điểm snapshot. |
| respect_robots | bool | NO |  |  | Tôn trọng robots.txt. |
| user_agent | text | YES | NULL |  | User-Agent áp dụng. |
| crawl_delay_seconds | int4 | NO |  | CHECK crawl_delay_seconds >= 0 | Độ trễ crawl. |
| max_concurrency | int4 | NO |  | CHECK max_concurrency >= 1 | Số kết nối song song. |
| rate_limit_per_min | int4 | NO |  | CHECK rate_limit_per_min >= 0 | Giới hạn/phút. |
| max_requests_per_run | int4 | NO |  | CHECK max_requests_per_run >= 0 | Giới hạn request/lần chạy. |
| allow_patterns | jsonb | NO |  | CHECK jsonb_typeof(allow_patterns) = 'array' | Danh sách pattern được phép. |
| deny_patterns | jsonb | NO |  | CHECK jsonb_typeof(deny_patterns) = 'array' | Danh sách pattern chặn. |
| headers_override | jsonb | NO |  | CHECK jsonb_typeof(headers_override) = 'object' | Ghi đè header. |
| reason | text | YES | NULL |  | Lý do snapshot (before policy change). |
| is_active | bool | NO | true |  | Kích hoạt (cho phép rollback). |
| created_by | UUID | YES | NULL |  | User ID tạo snapshot. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.source_endpoints

Nhiều endpoint cho một nguồn (RSS, API, sitemap, HLS).

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| source_id | UUID | NO |  | FK -> crawler.sources(id) | Nguồn áp dụng. |
| endpoint_type | varchar(20) | NO | HTML | CHECK endpoint_type IN (HTML, RSS, ATOM, SITEMAP, API, HLS, M3U8, FILE) | Loại endpoint. |
| method | varchar(10) | NO | GET | CHECK method IN (GET, POST) | HTTP method. |
| url | text | NO |  | CHECK url ~* '^https?://' | URL endpoint. |
| auth_profile_id | UUID | YES | NULL | FK -> crawler.auth_profiles(id) | Hồ sơ xác thực. |
| extractor_profile_id | UUID | YES | NULL | FK -> crawler.extractor_profiles(id) | Hồ sơ bóc tách. |
| schedule_id | UUID | YES | NULL | FK -> crawler.schedules(id) | Lịch chạy riêng. |
| headers | jsonb | NO | {} |  | Header bổ sung. |
| params | jsonb | NO | {} |  | Query params. |
| body_template | text | YES | NULL |  | Payload template. |
| parser_config | jsonb | NO | {} |  | Cấu hình parser. |
| format_config | jsonb | NO | {} | CHECK jsonb_typeof(format_config) = 'object' | Cấu hình theo định dạng (RSS, sitemap, API...). |
| format_config_version | int4 | NO | 1 | CHECK format_config_version >= 1 | Phiên bản cấu hình định dạng. |
| trace_id | varchar(64) | YES | NULL |  | Trace ID phục vụ quan sát. |
| is_primary | bool | NO | false |  | Endpoint chính. |
| priority | int4 | NO | 0 | CHECK priority >= 0 | Ưu tiên. |
| is_active | bool | NO | true |  | Kích hoạt. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

### Quy ước schema mẫu cho `format_config`

`format_config` là JSON object, gắn với từng endpoint. Khuyến nghị cấu trúc theo định dạng:

**RSS/ATOM**

```json
{
	"format": "RSS",
	"config_version": 1,
	"item_path": "channel.item",
	"fields": {
		"title": "title",
		"url": "link",
		"published_at": "pubDate",
		"summary": "description"
	},
	"dedup": {
		"key": "url",
		"hash": "sha256"
	}
}
```

**SITEMAP**

```json
{
	"format": "SITEMAP",
	"config_version": 1,
	"loc_path": "urlset.url.loc",
	"lastmod_path": "urlset.url.lastmod",
	"max_depth": 2
}
```

**API/JSON_API**

```json
{
	"format": "JSON_API",
	"config_version": 1,
	"data_path": "data.items",
	"pagination": {
		"type": "page",
		"param": "page",
		"start": 1,
		"size": 20
	},
	"fields": {
		"title": "title",
		"url": "url",
		"published_at": "publishedAt"
	}
}
```

Schema ràng buộc tối thiểu:
- `format` (string, bắt buộc, enum: RSS, ATOM, SITEMAP, JSON_API, HTML, PDF_OCR, IMAGE_OCR, HLS, M3U8)
- `config_version` (int, mặc định 1)
- `fields` (object, khuyến nghị có `title`, `url` nếu là bài viết)
- `pagination` (object, tùy chọn)

Ràng buộc bổ sung tại bảng:
- Nếu `endpoint_type` khác `HTML` thì `format_config` bắt buộc có `format`.
- `format` phải thuộc enum ở trên.

## crawler.schedules

Lịch chạy.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| code | varchar(50) | NO |  | UNIQUE (tenant_id, code) | Mã lịch. |
| name | text | NO |  | CHECK length(name) > 0 | Tên lịch. |
| schedule_type | varchar(20) | NO | CRON | CHECK schedule_type IN (CRON, INTERVAL, MANUAL) | Loại lịch. |
| cron_expr | varchar(100) | YES | NULL | CHECK (schedule_type <> 'CRON' OR cron_expr IS NOT NULL) | Biểu thức cron. |
| interval_seconds | int8 | YES | NULL | CHECK (schedule_type <> 'INTERVAL' OR interval_seconds > 0) | Chu kỳ giây. |
| timezone | varchar(50) | NO | UTC |  | Múi giờ. |
| start_at | timestamptz | YES | NULL |  | Bắt đầu. |
| end_at | timestamptz | YES | NULL |  | Kết thúc. |
| is_active | bool | NO | true |  | Kích hoạt. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.jobs

Định nghĩa job thu thập.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| source_id | UUID | NO |  | FK -> crawler.sources(id) | Nguồn áp dụng. |
| schedule_id | UUID | YES | NULL | FK -> crawler.schedules(id) | Lịch chạy. |
| job_type | varchar(20) | NO | SCHEDULED | CHECK job_type IN (SCHEDULED, MANUAL, RETRY) | Loại job. |
| run_mode | varchar(20) | NO | FULL | CHECK run_mode IN (FULL, INCREMENTAL) | Chế độ chạy. |
| priority | int4 | NO | 0 | CHECK priority >= 0 | Ưu tiên. |
| max_retries | int4 | NO | 3 | CHECK max_retries >= 0 | Số lần retry. |
| retry_backoff_seconds | int4 | NO | 60 | CHECK retry_backoff_seconds >= 0 | Backoff giây. |
| is_active | bool | NO | true |  | Kích hoạt job. |
| last_run_at | timestamptz | YES | NULL |  | Lần chạy gần nhất. |
| next_run_at | timestamptz | YES | NULL |  | Lần chạy tiếp theo. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.execution_runs

Cửa sổ thực thi với SLA cho chiến dịch.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| campaign_id | UUID | NO |  | FK -> crawler.campaigns(id) | Chiến dịch. |
| run_code | varchar(50) | NO |  | UNIQUE (tenant_id, campaign_id, run_code) | Mã run duy nhất. |
| description | text | YES | NULL |  | Mô tả mục đích run. |
| window_start | timestamptz | NO |  | CHECK window_end > window_start | Bắt đầu cửa sổ thực thi. |
| window_end | timestamptz | NO |  |  | Kết thúc cửa sổ thực thi. |
| sla_target_seconds | int4 | NO | 0 | CHECK sla_target_seconds >= 0 | SLA mục tiêu (giây). |
| status | varchar(20) | NO | PENDING | CHECK status IN (PENDING, RUNNING, COMPLETED, FAILED, TIMEOUT, CANCELLED) | Trạng thái execution run. |
| started_at | timestamptz | YES | NULL |  | Thời điểm bắt đầu thực tế. |
| finished_at | timestamptz | YES | NULL |  | Thời điểm kết thúc thực tế. |
| duration_ms | int8 | NO | 0 | CHECK duration_ms >= 0 | Tổng thời gian (ms). |
| sla_breach | bool | NO | false |  | True nếu vi phạm SLA. |
| total_sources | int4 | NO | 0 | CHECK total_sources >= 0 | Tổng nguồn trong run. |
| completed_sources | int4 | NO | 0 | CHECK completed_sources >= 0 | Số nguồn hoàn thành. |
| failed_sources | int4 | NO | 0 | CHECK failed_sources >= 0 | Số nguồn thất bại. |
| total_items | int4 | NO | 0 | CHECK total_items >= 0 | Tổng số item đã thu. |
| metadata | jsonb | NO | {} |  | Metadata bổ sung. |
| trace_id | varchar(64) | YES | NULL |  | Trace ID truy vết. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.runs

Trạng thái từng lần chạy (liên kết execution_run).

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| execution_run_id | UUID | YES | NULL | FK -> crawler.execution_runs(id) | Cửa sổ execution run. |
| job_id | UUID | NO |  | FK -> crawler.jobs(id) | Job thực thi. |
| campaign_id | UUID | NO |  | FK -> crawler.campaigns(id) | Chiến dịch. |
| source_id | UUID | NO |  | FK -> crawler.sources(id) | Nguồn. |
| status | varchar(20) | NO | RUNNING | CHECK status IN (RUNNING, COMPLETED, FAILED, TIMEOUT, CANCELLED) | Trạng thái chạy. |
| started_at | timestamptz | NO | now() |  | Thời điểm bắt đầu. |
| finished_at | timestamptz | YES | NULL |  | Thời điểm kết thúc. |
| duration_ms | int8 | NO | 0 | CHECK duration_ms >= 0 | Tổng thời gian. |
| items_found | int4 | NO | 0 | CHECK items_found >= 0 | Số link tìm thấy. |
| items_imported | int4 | NO | 0 | CHECK items_imported >= 0 | Số item lưu thành công. |
| items_rejected | int4 | NO | 0 | CHECK items_rejected >= 0 | Số item bị loại. |
| pages_crawled | int4 | NO | 0 | CHECK pages_crawled >= 0 | Số trang đã quét. |
| http_requests | int4 | NO | 0 | CHECK http_requests >= 0 | Số request HTTP. |
| bandwidth_kb | int4 | NO | 0 | CHECK bandwidth_kb >= 0 | Dung lượng KB. |
| error_code | varchar(50) | YES | NULL |  | Mã lỗi. |
| error_message | text | YES | NULL |  | Chi tiết lỗi. |
| config_snapshot | jsonb | NO | {} |  | Snapshot cấu hình. |
| trace_id | varchar(64) | YES | NULL |  | ID truy vết. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.url_frontier

**Hàng đợi URL active** - Chỉ chứa URLs đang xử lý hoặc pending. 

Lịch sử state transitions được log sang ClickHouse `crawler_url_frontier_log` qua CDC/Kafka.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| execution_run_id | UUID | YES | NULL | FK -> crawler.execution_runs(id) | Cửa sổ execution run. |
| campaign_id | UUID | NO |  | FK -> crawler.campaigns(id) | Chiến dịch. |
| source_id | UUID | NO |  | FK -> crawler.sources(id) | Nguồn. |
| endpoint_id | UUID | YES | NULL | FK -> crawler.source_endpoints(id) | Endpoint nguồn. |
| url | text | NO |  | CHECK url ~* '^https?://' | URL cần xử lý. |
| url_hash | char(64) | NO |  | UNIQUE (tenant_id, source_id, url_hash) | Hash SHA256 URL. |
| status | varchar(20) | NO | PENDING | CHECK status IN (PENDING, PROCESSING, DONE, FAILED, SKIPPED) | Trạng thái. |
| priority | int4 | NO | 0 | CHECK priority >= 0 | Ưu tiên. |
| depth | int4 | NO | 0 | CHECK depth >= 0 | Độ sâu. |
| retry_count | int4 | NO | 0 | CHECK retry_count >= 0 | Số lần retry. |
| next_fetch_at | timestamptz | NO | now() |  | Lần fetch tiếp theo. |
| last_fetch_at | timestamptz | YES | NULL |  | Lần fetch gần nhất. |
| last_error | text | YES | NULL |  | Lỗi gần nhất. |
| http_status | int4 | YES | NULL |  | HTTP status. |
| canonical_url | text | YES | NULL |  | URL canonical. |
| metadata | jsonb | NO | {} |  | Meta thông tin. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.items

Nội dung đã bóc tách (liên kết execution_run).

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| execution_run_id | UUID | YES | NULL | FK -> crawler.execution_runs(id) | Cửa sổ execution run. |
| campaign_id | UUID | NO |  | FK -> crawler.campaigns(id) | Chiến dịch. |
| source_id | UUID | NO |  | FK -> crawler.sources(id) | Nguồn. |
| endpoint_id | UUID | YES | NULL | FK -> crawler.source_endpoints(id) | Endpoint nguồn. |
| url | text | NO |  | CHECK url ~* '^https?://' | URL gốc. |
| url_hash | char(64) | NO |  | UNIQUE (tenant_id, source_id, url_hash) | Hash SHA256 URL. |
| canonical_url | text | YES | NULL |  | URL canonical. |
| content_hash | char(64) | YES | NULL |  | Hash nội dung. |
| dedupe_key | char(64) | YES | NULL |  | Hash dedupe nâng cao (canonical_url + content_hash). |
| parent_item_id | UUID | YES | NULL | FK -> crawler.items(id) | Item cha (đại diện nhóm nội dung tương tự). |
| similarity_score | numeric(5,2) | YES | NULL | CHECK similarity_score >= 0 AND similarity_score <= 100 | Độ tương đồng % với item cha (0-100). |
| cluster_key | char(64) | YES | NULL |  | Hash nhóm các item nội dung tương tự. |
| title | text | YES | NULL |  | Tiêu đề. |
| summary | text | YES | NULL |  | Tóm tắt. |
| author | text | YES | NULL |  | Tác giả. |
| language | varchar(10) | YES | NULL |  | Mã ngôn ngữ. |
| item_type | varchar(20) | NO | ARTICLE | CHECK item_type IN (ARTICLE, VIDEO, DOCUMENT, IMAGE, AUDIO, DATA) | Loại nội dung. |
| source_format | varchar(20) | NO | HTML | CHECK source_format IN (HTML, RSS, ATOM, API, HLS, M3U8, PDF, DOCX, JSON, XML) | Định dạng nguồn. |
| mime_type | varchar(100) | YES | NULL |  | MIME type. |
| published_at | timestamptz | YES | NULL |  | Thời điểm phát hành. |
| fetched_at | timestamptz | YES | NULL |  | Thời điểm lấy nội dung. |
|  |  |  |  | CHECK (published_at IS NULL OR fetched_at IS NULL OR published_at <= fetched_at) | Ràng buộc thời gian hợp lệ. |
| content_text | text | YES | NULL |  | Văn bản thuần. |
| content_markdown | text | YES | NULL |  | Markdown sạch. |
| content_html | text | YES | NULL |  | HTML. |
| content_json | jsonb | NO | {} |  | JSON kết quả bóc tách. |
| raw_html_url | text | YES | NULL |  | Đường dẫn HTML raw. |
| media_urls | jsonb | NO | [] | CHECK jsonb_typeof(media_urls) = 'array' | Danh sách media. |
| assets | jsonb | NO | [] | CHECK jsonb_typeof(assets) = 'array' | Tài nguyên đính kèm (ảnh, video, PDF) - mảng objects. |
| category_ids | jsonb | NO | [] | CHECK jsonb_typeof(category_ids) = 'array' | Danh mục - mảng {category_id, is_primary}. |
| status | varchar(20) | NO | NEW | CHECK status IN (NEW, PUBLISHED, REJECTED, DUPLICATE, ERROR) | Trạng thái xử lý. |
| rejection_reason | text | YES | NULL | CHECK status NOT IN (REJECTED, DUPLICATE) OR rejection_reason IS NOT NULL | Lý do bị loại/trùng. |
| ai_confidence | numeric(5,2) | NO | 0 | CHECK ai_confidence >= 0 AND ai_confidence <= 100 | Độ tin cậy AI. |
| trace_id | varchar(64) | YES | NULL |  | Trace ID phục vụ quan sát. |
| expires_at | timestamptz | YES | NULL |  | TTL - tự động xóa sau thời điểm này. NULL = giữ vĩnh viễn. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

### Quy ước schema cho `assets` và `category_ids`

**`assets`** - Mảng JSONB lưu tài nguyên đính kèm (thay thế bảng `item_assets`):

```json
[
  {
    "type": "IMAGE",
    "url": "https://example.com/image.jpg",
    "checksum": "abc123...def",
    "size_bytes": 102400,
    "mime_type": "image/jpeg",
    "width": 1920,
    "height": 1080,
    "metadata": {}
  },
  {
    "type": "VIDEO",
    "url": "https://example.com/video.mp4",
    "checksum": "xyz789...",
    "size_bytes": 5242880,
    "mime_type": "video/mp4",
    "duration_seconds": 120,
    "width": 1280,
    "height": 720,
    "metadata": {}
  }
]
```

Các trường bắt buộc: `type` (IMAGE, VIDEO, PDF, AUDIO, OTHER), `url`.

**`category_ids`** - Mảng JSONB lưu danh mục (thay thế bảng `item_categories`):

```json
[
  {
    "category_id": "uuid-category-1",
    "is_primary": true
  },
  {
    "category_id": "uuid-category-2",
    "is_primary": false
  }
]
```

Các trường bắt buộc: `category_id` (UUID), `is_primary` (boolean).

### Chiến lược TTL (Time-To-Live)

Bảng `items` hỗ trợ tự động xóa dữ liệu cũ qua trường `expires_at`:

**Cách hoạt động:**
- Khi crawl, set `expires_at = created_at + retention_period` (VD: 90 ngày)
- Background job chạy định kỳ (VD: mỗi giờ):
  ```sql
  DELETE FROM crawler.items 
  WHERE tenant_id = :tenant_id 
    AND expires_at < now() 
    AND deleted_at IS NULL
  LIMIT 10000;
  ```
- Items với `expires_at = NULL` được giữ vĩnh viễn

**Khuyến nghị retention:**
- Bài tin tức: 90-180 ngày
- Bài duplicate/rejected: 7-30 ngày  
- Bài published: có thể NULL (giữ lâu dài) hoặc 365 ngày
- Video/Document: 180-365 ngày

**Index:** `idx_items_expires_at` tối ưu cho cleanup query nhanh.

## crawler.item_deduplication_log

Lịch sử phát hiện trùng lặp.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| item_id | UUID | NO |  | FK -> crawler.items(id) | Item bị phát hiện trùng. |
| duplicate_of_item_id | UUID | NO |  | FK -> crawler.items(id) | Item gốc (đã có trước). |
| detected_by | varchar(20) | NO | URL_HASH | CHECK detected_by IN (URL_HASH, CANONICAL_URL, CONTENT_HASH, DEDUPE_KEY, AI_SIMILARITY) | Phương pháp phát hiện. |
| url_match | bool | NO | false |  | URL có khớp không. |
| canonical_url_match | bool | NO | false |  | Canonical URL có khớp không. |
| content_hash_match | bool | NO | false |  | Content hash có khớp không. |
| dedupe_key_match | bool | NO | false |  | Dedupe key có khớp không. |
| similarity_score | numeric(5,2) | YES | NULL | CHECK similarity_score >= 0 AND similarity_score <= 100 | Độ tương đồng % (dùng cho AI_SIMILARITY). |
| detected_at | timestamptz | NO | now() |  | Thời điểm phát hiện. |
| metadata | jsonb | NO | {} |  | Metadata chi tiết. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.item_processing_stages

Pipeline xử lý từ raw ingest → normalized content.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu. |
| item_id | UUID | NO |  | FK -> crawler.items(id) | Item đang được xử lý. |
| stage | varchar(20) | NO | RAW_INGESTED | CHECK stage IN (RAW_INGESTED, AI_PROCESSING, NORMALIZED, VALIDATION_FAILED, ENRICHMENT, READY, FAILED) | Giai đoạn xử lý. |
| raw_storage_url | text | YES | NULL |  | URL lưu trữ raw content (S3/MinIO). |
| normalized_storage_url | text | YES | NULL |  | URL lưu trữ normalized content. |
| ai_model_version | varchar(50) | YES | NULL |  | Phiên bản AI model sử dụng. |
| ai_processing_metadata | jsonb | NO | {} |  | Metadata từ AI (confidence, labels...). |
| processing_started_at | timestamptz | YES | NULL |  | Bắt đầu xử lý giai đoạn này. |
| processing_finished_at | timestamptz | YES | NULL |  | Kết thúc xử lý giai đoạn này. |
| processing_duration_ms | int8 | NO | 0 | CHECK processing_duration_ms >= 0 | Thời gian xử lý (ms). |
| error_code | varchar(50) | YES | NULL |  | Mã lỗi nếu thất bại. |
| error_message | text | YES | NULL |  | Chi tiết lỗi. |
| retry_count | int4 | NO | 0 | CHECK retry_count >= 0 | Số lần retry. |
| is_current | bool | NO | true |  | Giai đoạn hiện tại của item. |
| trace_id | varchar(64) | YES | NULL |  | Trace ID quan sát. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

## crawler.routing_rules

Quy tắc định tuyến sang tenant/section đích.

| Field | Kiểu dữ liệu | Null? | Mặc định | Ràng buộc & Logic kiểm tra | Mô tả |
| --- | --- | --- | --- | --- | --- |
| id | UUID | NO |  | PRIMARY KEY | Định danh UUID v7. |
| tenant_id | UUID | NO |  |  | Tenant sở hữu quy tắc. |
| campaign_id | UUID | NO |  | FK -> crawler.campaigns(id) | Chiến dịch. |
| category_id | UUID | YES | NULL | FK -> crawler.categories(id) | Danh mục (nếu áp dụng). |
| rule_type | varchar(20) | NO | CATEGORY | CHECK rule_type IN (CATEGORY, TAG, KEYWORD, SOURCE) | Loại quy tắc. |
| match_config | jsonb | NO | {} |  | Cấu hình match. |
| target_tenant_id | UUID | NO |  |  | Tenant đích. |
| target_app_code | varchar(50) | NO |  | CHECK length(target_app_code) > 0 | App đích. |
| target_section_id | UUID | YES | NULL |  | Section đích. |
| target_category_path | text | YES | NULL |  | Đường dẫn danh mục. |
| is_active | bool | NO | true |  | Kích hoạt. |
| priority | int4 | NO | 0 | CHECK priority >= 0 | Ưu tiên áp dụng. |
| created_at | timestamptz | NO | now() |  | Thời điểm tạo. |
| updated_at | timestamptz | NO | now() | CHECK updated_at >= created_at | Thời điểm cập nhật. |
| deleted_at | timestamptz | YES | NULL |  | Soft delete. |
| version | int8 | NO | 1 | CHECK version >= 1 | Optimistic locking. |

---

## ClickHouse Tables (Analytics & Telemetry)

Các bảng sau lưu trữ tại **ClickHouse** để tối ưu analytics, time-series data, và historical logs.

**Schema ClickHouse:** `docs/dev-manual/database/clickhouse/crawler_analytics_schema.sql`

### crawler_execution_logs

Nhật ký thực thi crawler (telemetry). Tham chiếu: `docs/dev-manual/database/clickhouse/telemetry_schema_sql.md`

### crawler_source_metrics

**SLO/SLI metrics đo chất lượng nguồn** - Time-windowed aggregation.

Schema ClickHouse:
```sql
CREATE TABLE crawler_source_metrics (
    tenant_id String,
    source_id String,
    window_start DateTime64(3),
    window_end DateTime64(3),
    total_requests UInt64,
    successful_requests UInt64,
    failed_requests UInt64,
    timeout_requests UInt64,
    total_retries UInt64,
    avg_latency_ms Float64,
    p50_latency_ms UInt64,
    p95_latency_ms UInt64,
    p99_latency_ms UInt64,
    max_latency_ms UInt64,
    success_rate Float32,
    avg_retries_per_request Float32,
    total_items_extracted UInt64,
    total_bandwidth_kb UInt64,
    avg_items_per_request Float64,
    metadata String,
    created_at DateTime64(3) DEFAULT now64()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(window_start)
ORDER BY (tenant_id, source_id, window_start)
TTL window_start + INTERVAL 90 DAY;
```

**Dùng cho:**
- Dashboard monitoring chất lượng nguồn
- Alert khi success_rate < threshold
- Identify slow sources (latency p95/p99)
- Capacity planning

### crawler_url_frontier_log

**Lịch sử URL frontier tracking** - Log mọi state transition.

Schema ClickHouse:
```sql
CREATE TABLE crawler_url_frontier_log (
    tenant_id String,
    source_id String,
    execution_run_id String,
    url String,
    url_hash String,
    status LowCardinality(String), -- PENDING, PROCESSING, DONE, FAILED, SKIPPED
    event_type LowCardinality(String), -- ENQUEUED, STARTED, COMPLETED, FAILED, RETRIED
    depth UInt16,
    retry_count UInt8,
    http_status UInt16,
    error_message String,
    processing_duration_ms UInt64,
    fetched_at DateTime64(3),
    event_at DateTime64(3) DEFAULT now64(),
    metadata String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_at)
ORDER BY (tenant_id, source_id, event_at, url_hash)
TTL event_at + INTERVAL 30 DAY;
```

**Dùng cho:**
- Debug URL processing issues
- Analyze crawl patterns
- Retry statistics
- Historical audit trail

**Data Flow:**
1. YugabyteDB `url_frontier`: Active queue (INSERT/UPDATE/DELETE)
2. Trigger/CDC: Log state changes → Kafka
3. ClickHouse `crawler_url_frontier_log`: Append-only history

**Lợi ích:**
- YugabyteDB: Lightweight (chỉ active URLs)
- ClickHouse: Full history với TTL tự động

### Materialized Views (Aggregations)

**crawler_source_daily_summary** - Daily rollup metrics nguồn:
```sql
CREATE MATERIALIZED VIEW crawler_source_daily_summary
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (tenant_id, source_id, date)
TTL date + INTERVAL 180 DAY
AS SELECT
    tenant_id, source_id, toDate(window_start) as date,
    sum(total_requests) as total_requests,
    sum(successful_requests) as successful_requests,
    avg(success_rate) as avg_success_rate,
    avg(avg_latency_ms) as avg_latency_ms,
    sum(total_items_extracted) as total_items_extracted
FROM crawler_source_metrics
GROUP BY tenant_id, source_id, date;
```

**crawler_url_processing_stats** - Thống kê URL theo status:
```sql
CREATE MATERIALIZED VIEW crawler_url_processing_stats
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (tenant_id, source_id, status, date)
TTL date + INTERVAL 180 DAY
AS SELECT
    tenant_id, source_id, status, toDate(event_at) as date,
    count() as url_count,
    uniq(url_hash) as unique_urls,
    avg(processing_duration_ms) as avg_duration_ms,
    quantile(0.95)(processing_duration_ms) as p95_duration_ms
FROM crawler_url_frontier_log
WHERE event_type IN ('COMPLETED', 'FAILED')
GROUP BY tenant_id, source_id, status, date;
```

**Lợi ích Materialized Views:**
- Pre-aggregated data → Query dashboard nhanh
- Auto-update khi raw data thay đổi
- TTL 180 ngày (dài hơn raw data) cho historical trend

---

### TTL Summary (ClickHouse)

| Bảng/View | TTL | Lý do |
|-----------|-----|-------|
| crawler_source_metrics | 90 ngày | Raw metrics, chi tiết cao |
| crawler_url_frontier_log | 30 ngày | Debug logs, volume lớn |
| crawler_source_daily_summary | 180 ngày | Daily rollup, nhẹ hơn |
| crawler_url_processing_stats | 180 ngày | Daily stats, nhẹ hơn |

**Cleanup tự động:** ClickHouse xóa partitions cũ khi TTL hết hạn (background merge).
- Columnar storage: Query analytics nhanh
- Partition by time: Drop old data efficiently

---

## Table Partitioning Strategy (YugabyteDB)

### Partitioning cho Bảng `items`

**Recommendation: Hash partition theo source_id (16 partitions)**

Bảng `items` được hash partition theo `source_id` vì:
- **90% queries** filter theo `source_id` (crawl/publish pipeline)
- **Data locality**: Tất cả items từ 1 source nằm cùng partition
- **Load balancing**: Traffic phân tán đều 16 partitions
- **Tenant isolation**: Mỗi tenant có sources khác nhau → auto distribute

```sql
CREATE TABLE crawler.items (
    id UUID DEFAULT uuid_generate_v7(),
    tenant_id UUID NOT NULL,
    source_id UUID NOT NULL,
    -- ... all other columns ...
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ,  -- TTL field
    
    PRIMARY KEY (source_id, id)  -- source_id FIRST for partition key
) PARTITION BY HASH (source_id);

-- Create 16 hash partitions for load balancing
CREATE TABLE items_p0 PARTITION OF crawler.items FOR VALUES WITH (MODULUS 16, REMAINDER 0);
CREATE TABLE items_p1 PARTITION OF crawler.items FOR VALUES WITH (MODULUS 16, REMAINDER 1);
-- ... items_p2 through items_p15

-- Indexes for common queries
CREATE INDEX idx_items_tenant_status ON crawler.items (tenant_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_items_source_created ON crawler.items (source_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_items_url_hash ON crawler.items (tenant_id, source_id, url_hash) WHERE deleted_at IS NULL;
CREATE INDEX idx_items_expires_at ON crawler.items (expires_at ASC) WHERE deleted_at IS NULL AND expires_at IS NOT NULL;
```

**Query Performance:**
```sql
-- ⚡⚡⚡ Ultra-fast: Single partition scan
SELECT * FROM crawler.items 
WHERE source_id = '...' AND status = 'PUBLISHED'
LIMIT 1000;

-- ⚡⚡ Fast with index
SELECT * FROM crawler.items 
WHERE tenant_id = '...' AND created_at >= now() - INTERVAL '7 days'
ORDER BY created_at DESC;
```

---

### TTL Cleanup Strategy (30 days retention)

Vì chỉ cần giữ 30 ngày, sử dụng **background delete job** với batching:

```sql
-- Background job: Hourly cleanup
CREATE OR REPLACE FUNCTION crawler.cleanup_expired_items()
RETURNS BIGINT AS $$
DECLARE
    deleted_count BIGINT := 0;
    batch_size INT := 10000;
    total_deleted BIGINT := 0;
BEGIN
    LOOP
        -- Delete items in batches (avoid long locks)
        DELETE FROM crawler.items
        WHERE (expires_at < now() OR created_at < now() - INTERVAL '30 days')
          AND deleted_at IS NULL
        LIMIT batch_size;
        
        GET DIAGNOSTICS deleted_count = ROW_COUNT;
        total_deleted := total_deleted + deleted_count;
        
        EXIT WHEN deleted_count = 0;
        
        -- Sleep between batches to reduce contention
        PERFORM pg_sleep(0.1);
    END LOOP;
    
    RETURN total_deleted;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION crawler.cleanup_expired_items IS 'Hourly job: Delete items older than 30 days';
```

**Schedule:**
```bash
# Add to crontab (run every hour)
0 * * * * psql -h localhost -U postgres -d crawler_db -c "SELECT crawler.cleanup_expired_items();"
```

---

### Partitioning cho Bảng `url_frontier` (Active Queue)

**Recommendation: Hash partition theo source_id (8 partitions)**

```sql
CREATE TABLE crawler.url_frontier (
    id UUID DEFAULT uuid_generate_v7(),
    tenant_id UUID NOT NULL,
    source_id UUID NOT NULL,
    -- ... other columns ...
    
    PRIMARY KEY (source_id, priority DESC, id)
) PARTITION BY HASH (source_id);

-- 8 partitions (smaller than items since active queue)
CREATE TABLE url_frontier_p0 PARTITION OF crawler.url_frontier FOR VALUES WITH (MODULUS 8, REMAINDER 0);
-- ... url_frontier_p1 through url_frontier_p7
```

**Query Performance:**
```sql
-- ⚡ Lightning fast: Single partition + priority ordering
SELECT * FROM crawler.url_frontier
WHERE source_id = '...' AND status = 'PENDING'
ORDER BY priority DESC
LIMIT 1000;
```

---

### Partitioning Decision Matrix

| Bảng | Strategy | # Partitions | Lý do |
|------|----------|--------------|-------|
| **items** | Hash(source_id) | 16 | Real-time queries, high volume |
| **url_frontier** | Hash(source_id) | 8 | Active queue, per-source processing |
| **execution_runs** | No partition | - | Low write rate |
| **runs** | No partition | - | Reference data |
| **Other tables** | No partition | - | Low volume (< 1M rows) |

---

### YugabyteDB Best Practices

**1. Primary Key Design:**
```sql
-- ✅ GOOD: High cardinality column first
PRIMARY KEY (source_id, id)  -- source_id distributes well

-- ❌ BAD: Low cardinality first → hot partitions
PRIMARY KEY (status, id)  -- Only 5 status values
```

**2. Monitoring Partition Pruning:**
```sql
-- Verify single partition scan
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM crawler.items 
WHERE source_id = '...' AND status = 'PUBLISHED';

-- Should show: "Partition Scan on items_pX" (single partition)
-- NOT: "Seq Scan on items" (all partitions)
```