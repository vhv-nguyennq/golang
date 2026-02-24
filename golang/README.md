# Golang CRUD API

CRUD mẫu cho `products` dùng Go chuẩn (`net/http`), lưu dữ liệu in-memory.

## Chạy

```bash
cd golang
go run .
```

Server chạy ở `http://localhost:8080`.

## API

- `POST /products` tạo mới
- `GET /products` lấy danh sách
- `GET /products/{id}` lấy chi tiết
- `PUT /products/{id}` cập nhật
- `DELETE /products/{id}` xoá

Ví dụ tạo product:

```bash
curl -X POST http://localhost:8080/products \
  -H 'Content-Type: application/json' \
  -d '{"name":"Mouse","price":25.5}'
```
