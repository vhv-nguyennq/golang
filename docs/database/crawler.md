# **Báo cáo Nghiên cứu: Kiến trúc Hệ thống Thu thập Dữ liệu Đa Khách thể Tích hợp Trí tuệ Nhân tạo**

## **Tổng quan về Hệ thống Thu thập Dữ liệu Quy mô Doanh nghiệp**

Trong kỷ nguyên dữ liệu số hiện đại, thông tin phi cấu trúc trên nền tảng web đóng vai trò là nguồn tài nguyên cốt lõi cho mọi hoạt động phân tích nghiệp vụ, đào tạo mô hình ngôn ngữ lớn (LLMs), và tình báo doanh nghiệp. Tuy nhiên, sự phát triển bùng nổ của các chuẩn định dạng web, kết hợp với các kiến trúc kết xuất nội dung động và cơ chế phòng vệ an ninh mạng phức tạp, đã khiến việc thu thập dữ liệu trở thành một thách thức kỹ thuật to lớn.1 Một hệ thống thu thập dữ liệu (web crawler) cấp độ doanh nghiệp không thể chỉ dừng lại ở các đoạn mã cào dữ liệu (scraping scripts) đơn lẻ, mà phải được thiết kế dưới dạng một nền tảng phân tán, có khả năng mở rộng linh hoạt, tích hợp sâu trí tuệ nhân tạo (AI) và phục vụ đồng thời nhiều phân hệ đích thông qua kiến trúc đa khách thể (multi-tenant architecture).3

Kiến trúc phân tán của hệ thống crawler thế hệ mới đòi hỏi sự phối hợp nhịp nhàng giữa hàng loạt vi dịch vụ (microservices) nhằm đảm bảo tính sẵn sàng cao (fault tolerance) và khả năng xử lý hàng tỷ yêu cầu mỗi ngày.6 Thay vì triển khai theo mô hình đơn nút (single-node) nơi một máy chủ duy nhất đảm nhiệm toàn bộ quy trình từ tải trang, phân tích cú pháp đến lưu trữ, hệ thống hiện đại phân tách các chức năng này vào các cụm máy chủ chuyên biệt.3 Theo các mô hình kiến trúc tham chiếu, quá trình này thường được điều phối bởi các dịch vụ đám mây như AWS Batch, kết hợp với Amazon EventBridge Scheduler để kích hoạt các chiến dịch thu thập theo chu kỳ.8 Các tiến trình cào dữ liệu cốt lõi (worker nodes) được vận hành bên trong các bộ chứa (containers) thông qua Amazon Elastic Container Service (ECS) hoặc AWS Fargate, đặt trong các mạng riêng ảo (VPC) nhằm đảm bảo tốc độ băng thông và khả năng ẩn danh mạng.8 Dữ liệu thô sau khi được bóc tách sẽ được định tuyến vào các kho lưu trữ đối tượng như Amazon S3 trước khi trải qua bước phân tích ngữ nghĩa và đưa vào hệ thống cơ sở dữ liệu có cấu trúc.6

Hàng đợi URL (URL Frontier) đóng vai trò là bộ não điều phối lưu lượng của toàn bộ hệ thống. Nhiệm vụ của hàng đợi không chỉ là lưu trữ các liên kết cần truy cập mà còn phải thực thi các thuật toán lập lịch trình (scheduling algorithms) nhằm tuân thủ nghiêm ngặt chính sách lịch sự (politeness policy) và các tệp robots.txt của trang web đích.6 Hệ thống phải tính toán độ trễ thu thập (crawl delay), ưu tiên các URL dựa trên tín hiệu về độ tươi mới (freshness) và tầm quan trọng của nội dung, đồng thời loại bỏ các liên kết trùng lặp thông qua các cấu trúc dữ liệu xác suất như Bộ lọc Bloom (Bloom Filters) hoặc các thuật toán băm kiểm tra (checksum) nhằm tránh lãng phí tài nguyên hệ thống và ngăn chặn nguy cơ bị đánh dấu là tấn công từ chối dịch vụ (DDoS).6

## **Năng lực Xử lý và Bóc tách Dữ liệu Đa Định dạng**

Sự đa dạng của thông tin trên internet yêu cầu hệ thống crawler phải sở hữu các luồng xử lý (pipelines) chuyên biệt cho từng loại định dạng. Một nền tảng toàn diện phải có khả năng hấp thụ từ tin tức văn bản thông thường, luồng video phát trực tiếp, thư viện hình ảnh động, cho đến các tài liệu pháp quy phức tạp dưới dạng PDF.1

### **Xử lý Dữ liệu Văn bản, Tin tức và Giao thức RSS**

Đối với các bài viết tin tức và văn bản tĩnh, giao thức Nguồn Cấp Dữ liệu Chuẩn (RSS \- Really Simple Syndication) hoặc Atom luôn được hệ thống ưu tiên thiết lập làm luồng thu thập hạng nhất. RSS cung cấp một cấu trúc XML đã được định dạng sẵn, loại bỏ hoàn toàn nhu cầu phân tích cây tài liệu (DOM tree) phức tạp, từ đó giảm thiểu đáng kể chi phí tính toán (compute cost) và độ trễ.8 Đối với các bài viết tin tức định dạng HTML tiêu chuẩn, hệ thống sử dụng các thư viện phân tích cú pháp hiệu năng cao như BeautifulSoup hoặc lxml kết hợp với các bộ chọn CSS (CSS Selectors) và XPath.10 Tuy nhiên, để đáp ứng yêu cầu đào tạo mô hình ngôn ngữ hoặc phân tích chuyên sâu, dữ liệu thô không được giữ nguyên mà phải trải qua quá trình tinh lọc (sanitization). Quá trình này tự động loại bỏ các thẻ quảng cáo, kịch bản theo dõi (tracking scripts), định dạng CSS nội tuyến, và chuyển đổi cấu trúc HTML phức tạp thành định dạng Markdown gọn gàng. Định dạng Markdown này không chỉ bảo toàn các cấu trúc ngữ nghĩa cốt lõi như tiêu đề (headings), bảng biểu (tables), và khối mã (code blocks) mà còn cực kỳ tối ưu cho các hệ thống Tái tạo Tăng cường Truy xuất (RAG \- Retrieval-Augmented Generation).11

### **Trích xuất Luồng Video Phát Tuyến (HLS và m3u8)**

Việc thu thập dữ liệu video từ các nền tảng truyền thông hiện đại đòi hỏi kỹ thuật phức tạp hơn nhiều so với việc tải các tệp tin .mp4 tĩnh. Hầu hết các nền tảng phát tuyến (streaming) hiện nay sử dụng giao thức HTTP Live Streaming (HLS), trong đó một video nguyên bản được chia cắt thành hàng nghìn phân đoạn nhỏ (MPEG transport stream \- tệp .ts) và được lập chỉ mục bởi một tệp danh sách phát có phần mở rộng .m3u8.12 Việc tiếp cận tệp .m3u8 này thường bị cản trở do chúng được tạo động thông qua mã JavaScript, ẩn bên trong các khung nội tuyến (iframes), hoặc yêu cầu các chuỗi xác thực phiên bản (session tokens) thay đổi liên tục.13

Để vượt qua rào cản này, hệ thống crawler áp dụng kỹ thuật Đánh chặn Lưu lượng Mạng (Network Interception) thông qua các trình duyệt tự động hóa như Puppeteer hoặc Playwright. Quá trình bắt đầu bằng việc khởi chạy một phiên bản trình duyệt không đầu (headless browser) truy cập vào trang web đích và mô phỏng các hành vi tương tác của người dùng, chẳng hạn như nhấp chuột vào nút phát video hoặc chọn độ phân giải.12 Hệ thống sử dụng giao thức Chrome DevTools Protocol (CDP) để lắng nghe toàn bộ các sự kiện mạng, đặc biệt là sự kiện network.requestWillBeSent.14 Khi hệ thống quét thấy một yêu cầu mạng chứa định dạng .m3u8 hoặc tiêu đề nội dung application/vnd.apple.mpegurl, nó sẽ tự động trích xuất liên kết này. Trong một số kiến trúc nâng cao, hệ thống có thể tích hợp các thư viện chuyên dụng như puppeteer-stream để cấu hình bắt luồng trực tiếp với các tham số độ trễ khởi động (startDelay) nhằm khắc phục các lỗi kết nối máy khách, đồng thời định tuyến liên kết m3u8 này đến các công cụ biên dịch dòng lệnh như FFmpeg để tải và hợp nhất các tệp .ts thành tệp video hoàn chỉnh ngay trên máy chủ lưu trữ.12

### **Kỹ thuật Thu thập Thư viện Hình ảnh và Tương tác DOM**

Đối với các bài viết dạng thư viện ảnh (image galleries), rào cản lớn nhất đối với hệ thống crawler là các kỹ thuật tối ưu hóa hiệu năng hiển thị phía máy khách (client-side rendering optimizations), điển hình là cơ chế tải tĩnh (lazy loading). Thay vì mã hóa cứng (hardcode) thuộc tính src của hình ảnh ngay từ đầu, các trang web thường giấu đường dẫn hình ảnh thực tế trong các thuộc tính dữ liệu (ví dụ: data-src) và chỉ tải chúng khi người dùng cuộn trang đến đúng vị trí hình ảnh đó.1

Hệ thống crawler giải quyết vấn đề này bằng cách thiết lập các chuỗi lệnh mô phỏng sinh trắc học. Trình duyệt tự động sẽ thực hiện thao tác cuộn trang (scroll) với các khoảng dừng ngẫu nhiên, kích hoạt các sự kiện quan sát giao diện (Intersection Observers) của JavaScript để ép buộc trang web tải toàn bộ nội dung ảnh.11 Thêm vào đó, hệ thống được lập trình để quét cấu trúc thuộc tính srcset nhằm tự động lựa chọn và trích xuất độ phân giải hình ảnh cao nhất có sẵn, loại bỏ các tệp tin thu nhỏ (thumbnails) không đạt yêu cầu chất lượng.1

### **Bóc tách Dữ liệu Từ Tài liệu Pháp quy và PDF (OCR & NLP)**

Một cấu phần quan trọng của hệ thống crawler là khả năng xử lý thông tin từ các cổng thông tin điện tử của chính phủ, nơi dữ liệu thường được lưu trữ dưới dạng văn bản pháp quy, nghị định, thông tư định dạng PDF hoặc hình ảnh quét (scanned images). Do tính chất phi cấu trúc của các định dạng này, các bộ chọn HTML truyền thống hoàn toàn vô tác dụng.17

Quy trình thu thập tài liệu pháp quy được thiết kế như một chuỗi khép kín tích hợp Trí tuệ Nhân tạo. Ngay khi tệp PDF được tải xuống, hệ thống sẽ đưa tài liệu qua đường ống Nhận dạng Ký tự Quang học (OCR). OCR đóng vai trò thiết lập các hộp giới hạn (bounding boxes) xung quanh các khối văn bản để chuyển đổi điểm ảnh (pixels) thành văn bản máy tính có thể đọc được (machine-readable text).17 Tuy nhiên, OCR đơn thuần không thể hiểu được ngữ nghĩa của luật pháp. Do đó, Xử lý Ngôn ngữ Tự nhiên (NLP) và mô hình Học máy (Machine Learning) được tiếp tục áp dụng để nhận diện các mẫu cấu trúc tài liệu.20 Các thuật toán học sâu (Deep Learning) sẽ tiến hành phân tách tài liệu thành các cặp Truy vấn \- Kết quả (Question \- Answer format), bóc tách các thực thể pháp lý quan trọng như "Số hiệu", "Cơ quan ban hành", "Ngày có hiệu lực", và các phân tầng logic như "Chương", "Điều", "Khoản".20 Điều này biến một tài liệu PDF nguyên khối thành một tập hợp dữ liệu JSON/XML có cấu trúc chặt chẽ, sẵn sàng để lập chỉ mục trong cơ sở dữ liệu và cho phép người dùng cuối thực hiện các truy vấn tìm kiếm phức tạp đối với từng điều khoản pháp lý cụ thể.18

## **Khả năng Thích ứng với Môi trường Kiến trúc Đa Nền tảng**

Mỗi công nghệ xây dựng trang web mang đến những rào cản độc nhất về cách thức phân phối và quản lý trạng thái dữ liệu. Năng lực của phần mềm crawler được đánh giá qua khả năng phân tích và bóc tách thông tin một cách mượt mà trên tất cả các kiến trúc này.

### **Các Ứng dụng Kết xuất phía Máy khách (ReactJS, Angular, Vue)**

Sự bùng nổ của kiến trúc Ứng dụng Đơn trang (Single Page Applications \- SPA) được xây dựng bằng ReactJS, Angular hoặc VueJS đã làm thay đổi hoàn toàn cách tiếp cận của các trình thu thập dữ liệu. Khác với các trang web truyền thống nơi mã nguồn HTML chứa đầy đủ thông tin, các hệ thống ReactJS thường chỉ gửi về một khung HTML trống rỗng (ví dụ: \<div id="root"\>\</div\>) kèm theo các tệp JavaScript khổng lồ.1 Dữ liệu thực sự chỉ xuất hiện sau khi trình duyệt chạy mã JavaScript để kết xuất nội dung động (Client-Side Rendering) thông qua các lệnh gọi API bất đồng bộ.22

Các trình cào dữ liệu dựa trên giao thức HTTP thuần túy (như cURL, Scrapy cơ bản, hoặc BeautifulSoup) sẽ gặp thất bại toàn diện trước kiến trúc này.22 Giải pháp tối ưu nhất mà hệ thống áp dụng là vận hành các trình duyệt không đầu (Headless Browsers) như Playwright hoặc Puppeteer, cho phép thực thi toàn bộ vòng đời của JavaScript. Hệ thống sẽ lắng nghe các trạng thái mạng và chỉ bắt đầu trích xuất dữ liệu khi toàn bộ ứng dụng đã trải qua quá trình "hydrat hóa" (hydration) hoàn tất.23 Trong các thiết lập tối ưu hóa băng thông, crawler có thể bỏ qua hoàn toàn việc kết xuất giao diện đồ họa. Thay vào đó, nó theo dõi các yêu cầu mạng (XHR/Fetch) do ứng dụng ReactJS phát ra và trực tiếp đánh chặn các gói tin JSON trả về từ máy chủ API nội bộ, qua đó trích xuất dữ liệu gốc với độ trễ thấp nhất và cấu trúc nguyên bản, loại bỏ nhu cầu phân tích cây DOM.1

### **Hệ thống Quản lý Trạng thái phía Máy chủ (ASP.NET Web Forms)**

Đối lập hoàn toàn với tính phi trạng thái của các ứng dụng ReactJS, các hệ thống di sản được xây dựng trên nền tảng ASP.NET Web Forms lại duy trì một trạng thái phiên làm việc (Session State) cực kỳ nghiêm ngặt giữa máy khách và máy chủ. Đây là rào cản kỹ thuật đặc thù thường gặp khi thu thập dữ liệu từ các trang web của cơ quan nhà nước, tổ chức giáo dục, và các hệ thống doanh nghiệp cũ.22

Trọng tâm của cơ chế phòng vệ tự nhiên trong ASP.NET là các trường dữ liệu ẩn (hidden fields) khổng lồ chứa trạng thái giao diện, bao gồm \_\_VIEWSTATE, \_\_EVENTVALIDATION, và \_\_VIEWSTATEGENERATOR.22 Các giá trị này được mã hóa bằng Base64 và đi kèm với chữ ký mã hóa nhằm ngăn chặn giả mạo (tampering). Khi crawler muốn thực hiện thao tác chuyển trang (pagination) hoặc nhấp vào một danh sách thả xuống, hệ thống ASP.NET không sử dụng các đường dẫn URL khác nhau (HTTP GET) mà sử dụng một yêu cầu HTTP POST trở lại chính URL đó (Postback), kèm theo toàn bộ trạng thái hiện hành.22

Nếu crawler thực hiện một yêu cầu POST chứa dữ liệu cũ hoặc không đồng bộ với trạng thái phiên bản (session), máy chủ sẽ trả về lỗi EVENTVALIDATION error.27 Để lập trình một đường ống thu thập dữ liệu ổn định trên ASP.NET, hệ thống áp dụng thuật toán mô phỏng trạng thái như sau:

1. **Khởi tạo và Thu thập Trạng thái**: Trình thu thập gửi yêu cầu GET ban đầu đến URL đích. Từ mã nguồn HTML trả về, hệ thống phân tích cú pháp để lấy và lưu trữ các giá trị \_\_VIEWSTATE, \_\_EVENTVALIDATION, và \_\_VIEWSTATEGENERATOR vào bộ nhớ cục bộ cùng với các cookie định danh phiên (Session ID).24  
2. **Xây dựng Gói Tải trọng Động**: Để thực hiện thao tác chuyển tiếp, hệ thống xây dựng một biểu mẫu dữ liệu (form data) chứa các biến trạng thái vừa thu thập. Các tham số bổ sung bắt buộc phải có là \_\_EVENTTARGET (đại diện cho ID của phần tử giao diện gây ra sự kiện, ví dụ như ID của nút "Trang tiếp theo") và \_\_EVENTARGUMENT.22  
3. **Mã hóa và Đăng tải Phản hồi**: Toàn bộ gói dữ liệu được mã hóa URL (URL-encoded), xử lý cẩn thận các ký tự đặc biệt như dấu /, \+, và \= để tương thích với chuẩn mã hóa hex.25 Yêu cầu POST sau đó được gửi đi cùng với cookie phiên. Sau khi nhận được kết quả trang thứ hai, crawler phải ngay lập tức trích xuất cặp \_\_VIEWSTATE và \_\_EVENTVALIDATION mới nhất để chuẩn bị cho chu kỳ vòng lặp tiếp theo.27 Quy trình này đảm bảo tính toàn vẹn phiên bản mà không cần phải chạy trình duyệt nặng nề, gia tăng tốc độ bóc tách dữ liệu lên nhiều lần.

### **Kiến trúc Web Truyền thống (PHP và HTML Tĩnh)**

Đối với các trang web được xây dựng bằng PHP, Ruby, hoặc các nền tảng kết xuất phía máy chủ (Server-Side Rendering) thông thường, dữ liệu chủ yếu được phản hồi đầy đủ ngay trong mã nguồn HTML thô. Việc xử lý trên các kiến trúc này tương đối trực diện. Hệ thống thu thập chỉ cần sử dụng các bộ máy phân tích cú pháp nhẹ, quản lý cookie đăng nhập (để truy cập các phân vùng dữ liệu yêu cầu xác thực), và theo dõi bộ đệm (caching headers) để tránh tải lại nội dung không cần thiết.22

## **Hệ thống Trốn tránh Tiên tiến và Vượt Tường lửa Không gian Mạng (WAF/Anti-Bot Evasion)**

Khi hệ thống thu thập dữ liệu tiếp cận hàng triệu trang web mỗi ngày, chúng sẽ không thể tránh khỏi việc đối đầu với các Tường lửa Ứng dụng Web (Web Application Firewalls \- WAF) và các hệ thống chống bot tối tân như Cloudflare, Akamai, DataDome, Imperva, và PerimeterX.2 Các giải pháp an ninh mạng vào năm 2025/2026 đã loại bỏ việc chặn IP thô sơ, thay vào đó, chúng triển khai các mô hình học máy theo từng khách hàng (per-customer ML models) và đánh giá điểm tín nhiệm (Trust Score Evaluation) dựa trên sinh trắc học hành vi và phân tích dấu vân tay ở cấp độ giao thức.28

### **Cơ chế Hoạt động của Tường lửa Ứng dụng Web (WAF)**

Sự phức tạp của WAF thể hiện qua cơ chế kiểm tra đa lớp đối với từng yêu cầu HTTP/S gửi đến máy chủ 2:

1. **Dấu vân tay Mạng và Khóa Mật mã (JA3/TLS Fingerprinting)**: Khi một kết nối HTTPS được thiết lập, quá trình bắt tay (TLS handshake) sẽ truyền tải một tập hợp các thông tin về các bộ mã hóa (cipher suites) và tiện ích mở rộng (extensions) mà ứng dụng máy khách hỗ trợ.28 Hệ thống WAF biên dịch dữ liệu này thành một mã băm duy nhất (JA3 fingerprint). Các thư viện HTTP tiêu chuẩn trong Python, Node.js, hay Golang sở hữu các dấu vân tay JA3 khác biệt hoàn toàn so với một trình duyệt Google Chrome hoặc Safari thực tế của người dùng.23 Do đó, WAF có thể nhận diện ngay lập tức sự khác biệt ở tầng vận chuyển và chặn truy cập từ gốc.  
2. **Dấu vân tay JavaScript và Kết xuất Phần cứng (Browser Fingerprinting)**: Sau khi vượt qua tầng mạng, WAF tiến hành thực thi các đoạn mã JavaScript phức tạp trên máy khách. Mục tiêu là truy xuất độ phân giải của WebGL, phương thức kết xuất đồ họa Canvas, và bối cảnh âm thanh (Audio Context).28 Đặc biệt, chúng kiểm tra các biến số như navigator.webdriver. Nếu biến này trả về giá trị true (mặc định cho các công cụ như Selenium hay Puppeteer), kết nối sẽ bị hệ thống nhận định là tự động hóa và ngăn chặn.11  
3. **Phân tích Vận tốc và Mô hình Hành vi (Rate Limiting & Behavioral Modeling)**: WAF đo lường vận tốc yêu cầu (request velocity). Ví dụ, nếu crawler cố gắng lấy 100 trang trong vòng một phút với một tần suất hoàn hảo không có sự gián đoạn ngẫu nhiên, WAF sẽ xếp loại nó vào diện tấn công từ chối dịch vụ (DDoS) hoặc thu thập dữ liệu bất hợp pháp, dẫn đến các mã lỗi điển hình của Cloudflare như 429 (Quá nhiều yêu cầu) hoặc 1015 (Giới hạn tốc độ).2  
4. **Hệ thống Kiểm thử Thách thức (Turnstile & CAPTCHA)**: Các hệ thống bảo mật hiện đại đã chuyển từ CAPTCHA truyền thống sang Cloudflare Turnstile, một công nghệ thách thức không tương tác. Thay vì yêu cầu giải mã hình ảnh, Turnstile thực hiện các phép tính nhúng bằng JavaScript trên máy khách dựa trên bối cảnh để xác thực "tính người" (proof-of-work) của trình duyệt.28

### **Kiến trúc Vượt Rào Cản Đa Lớp (Multi-Layer Evasion Architecture)**

Để đảm bảo tỷ lệ thành công tối đa cho các chiến dịch cào dữ liệu, kiến trúc của hệ thống crawler phải tích hợp một môi trường trốn tránh (stealth automation) toàn diện, nâng cấp liên tục để vô hiệu hóa các cơ chế phát hiện của WAF. Các cấu trúc kỹ thuật cốt lõi bao gồm:

| Lớp Phòng thủ WAF | Giải pháp Vượt rào cản Kỹ thuật (Evasion Strategy) | Công nghệ / Tham số Cấu hình Tương ứng |
| :---- | :---- | :---- |
| **Dấu vân tay TLS (JA3)** | Mô phỏng giao thức truyền tải, giả mạo chữ ký TLS và giao thức HTTP/2 để có chữ ký khớp hoàn toàn với một trình duyệt dân dụng tiêu chuẩn.28 | Thư viện **Nodriver** (khuyến nghị thay thế cho undetected-chromedriver vào năm 2025\) hoặc cấu hình cURL giả lập trình duyệt.28 |
| **Phát hiện Trình duyệt Tự động hóa** | Khử mã hóa phần mềm trình duyệt không đầu. Triển khai các mã kịch bản khởi tạo (init\_scripts) can thiệp sâu vào nhân JavaScript. Xóa bỏ hoặc ghi đè các tham số nội bộ do nền tảng tự động hóa sinh ra.11 | Tích hợp **Camoufox** (tạo vân tay đa dạng trên nhân Firefox) hoặc cấu hình tham số \--disable-blink-features=AutomationControlled và ghi đè Object.defineProperty(navigator, 'webdriver', {get: () \=\> false}).11 |
| **Phát hiện Chuyển động Cơ học** | Mô hình hóa luồng điều hướng tự nhiên. Ứng dụng sinh trắc học hành vi bằng cách kết hợp di chuyển con trỏ chuột theo đường cong Bezier, thay đổi nhịp độ nhấp chuột, và cuộn trang có độ trễ.28 | Thư viện **SeleniumBase UC Mode** kết hợp các hàm tạo thời gian chờ ngẫu nhiên và đường dẫn duyệt trang có tính không xác định.28 |
| **Giới hạn IP và Đánh giá Tín nhiệm Địa lý** | Triển khai hạ tầng phân tán IP động quy mô lớn. Tận dụng dải IP dân dụng (Residential Proxies) và IP thế hệ mới (IPv6) vốn ít bị các cơ sở dữ liệu danh tiếng (IP Reputation databases) theo dõi và đánh giá xấu.28 | Hệ thống bộ định tuyến mạng quản lý hàng triệu IP, kích hoạt duy trì phiên (Sticky Sessions) để tránh rớt kết nối đột ngột giữa chừng.11 |
| **Kiểm thử Turnstile/CAPTCHA** | Ưu tiên phương pháp ngăn chặn kích hoạt bằng cách duy trì vân tay sạch. Nếu bị thách thức, hệ thống định tuyến các phép toán này qua các dịch vụ giải quyết tự động để trả về kết quả chứng minh điện toán.28 | Tích hợp API của **2Captcha** hoặc **CapSolver** hoặc các hệ thống quản lý API vượt rào nguyên khối như ScrapFly Web Scraping API.28 |

Hơn nữa, một rủi ro lớn trong quản lý thu thập dữ liệu là sự lỗi thời của bộ công cụ. Hệ thống này cấm tuyệt đối việc sử dụng các công nghệ đã bị WAF bắt bài như puppeteer-stealth (đã ngừng hỗ trợ hoàn toàn vào tháng 2/2025). Mọi kiến trúc ẩn danh đều được dịch chuyển sang các khung cấu trúc tương lai, đảm bảo quá trình thu thập không bị cản trở bởi các lỗi mã hóa như Lỗi 1009 (Chặn theo khu vực địa lý) hay Lỗi 1010 (Đánh chặn theo dấu vân tay độc hại).28 Bằng cách này, hệ thống duy trì được tính liên tục (session persistence) của các bộ đệm và cookie, cho phép trích xuất sâu các trang web của những ông lớn công nghệ (Amazon, LinkedIn) mà không cần phải xác thực lại danh tính liên tục.28

## **Ứng dụng Trí tuệ Nhân tạo (AI) trong Phân tích Cấu hình và Tự động Bóc tách**

Trong các kiến trúc cào dữ liệu truyền thống, quá trình cấu hình và lập trình thuật toán bóc tách yêu cầu hàng trăm giờ làm việc của các kỹ sư phần mềm. Mỗi khi cấu trúc trang web đích (DOM layout) trải qua các bản cập nhật giao diện, các bộ chọn XPath hoặc CSS cứng nhắc ngay lập tức bị gãy vỡ, dẫn đến sự đình trệ của toàn bộ hệ thống thu thập (XPath drift).31 Việc tích hợp Trí tuệ Nhân tạo, đặc biệt là các Mô hình Ngôn ngữ Lớn (LLMs), đã thiết lập một mô hình hoạt động hoàn toàn mới: Chuyển đổi từ trích xuất dựa trên cú pháp cố định sang trích xuất dựa trên ngữ nghĩa linh hoạt (semantic extraction).31

### **Tối ưu hóa Mã nguồn HTML (DOM Pruning & Condensation)**

Gửi toàn bộ mã nguồn HTML của một trang web (có thể lên tới hàng triệu ký tự) trực tiếp vào API của các LLM (như GPT-4o, Claude 3.5) là bất khả thi về mặt kỹ thuật do các giới hạn về độ dài cửa sổ ngữ cảnh (token limits) và cực kỳ tốn kém về mặt chi phí kinh tế.31 Hơn nữa, việc nhồi nhét quá nhiều thông tin gây nhiễu khiến khả năng suy luận của LLM bị suy giảm nghiêm trọng (hiệu ứng phân tâm ngữ cảnh).34

Hệ thống AI giải quyết nút thắt này thông qua một đường ống tiền xử lý chuyên sâu dựa trên các mô hình toán học tìm kiếm.11 Các công cụ cấu hình crawler hiện đại (như nền tảng Crawl4AI) sử dụng các chiến lược phân đoạn thông minh (smart chunking). Thuật toán được lập trình với các tham số ngưỡng tối đa như chunk\_token\_threshold (giới hạn từ 3000 \- 5000 tokens) và một mức độ chồng lấn overlap\_threshold để đảm bảo ngữ cảnh của nội dung không bị đứt gãy tại các điểm nối.11

Quan trọng hơn, hệ thống áp dụng thuật toán BM25 (Best Matching 25\) và TF-IDF (Term Frequency-Inverse Document Frequency) để thanh lọc cấu trúc DOM.11 Các đoạn mã vô nghĩa, thẻ định dạng div, span không chứa nội dung văn bản liên quan đến truy vấn sẽ bị loại bỏ hoàn toàn. Thuật toán sẽ tính toán hàm khoảng cách (distance function) giữa các nút DOM có chứa từ khóa cốt lõi (cue texts) và thu gọn những khu vực không liên quan thành các ký hiệu ....32 Kết quả sinh ra là một tài liệu Markdown cực kỳ tinh gọn (Fit Markdown), giữ lại 100% giá trị thông tin nhưng giảm đến hơn 80% dung lượng mã, tối ưu hoàn hảo cho việc xử lý của LLM.11

### **Trợ lý AI Tự động Sinh Đường dẫn (Autonomous XPath Agent)**

Một tính năng đột phá của hệ thống là khả năng sử dụng AI để tự động sinh ra và tự kiểm tra các cấu hình trích xuất (XPath expressions) mà không cần sự can thiệp của con người. Thay vì giao phó toàn bộ công việc cho một mô hình đắt đỏ duy nhất, hệ thống triển khai một kiến trúc đường ống hai giai đoạn (Two-stage LLM Pipeline) nhằm tối ưu hiệu năng và chi phí.32

1. **Giai đoạn 1 (Trích xuất Thông tin Đóng vai trò Bản lề \- Information Extraction)**: Một mô hình ngôn ngữ cỡ nhỏ và tiết kiệm (ví dụ: GPT-4o mini, DeepSeek) được giao nhiệm vụ duyệt qua mã HTML đã nén. Mô hình này được cung cấp lời nhắc (prompt) để xác định các từ khóa ngữ cảnh (cue text) nằm ngay sát giá trị mục tiêu, giúp AI nhận biết được vị trí tương đối của dữ liệu cần lấy dù cấu trúc HTML cực kỳ phức tạp.32  
2. **Giai đoạn 2 (Lập trình XPath Không gian \- XPath Programming)**: Sau khi mã HTML được cô đọng triệt để dựa trên các từ khóa bản lề, nó được chuyển giao cho một mô hình suy luận mạnh mẽ hơn (ví dụ: GPT-4o hoặc Claude 3.5). Lời nhắc yêu cầu mô hình này lập trình một đường dẫn XPath.32 Hệ thống sử dụng thuật toán lan truyền từ dưới lên (bottom-up propagation), bắt đầu từ nút chứa dữ liệu mục tiêu và mở rộng dần lên gốc tài liệu, đồng thời tích hợp các thuộc tính phong phú như class hoặc id để đảm bảo đường dẫn linh hoạt và không dễ bị gãy vỡ.36  
3. **Vòng lặp Đánh giá Hội thoại (Conversational Evaluator)**: Tính năng tự động hóa được hoàn thiện thông qua vòng lặp phản hồi. Nếu XPath do LLM tạo ra thử nghiệm thất bại trên một biến thể khác của cùng một trang web, AI đánh giá (evaluator) sẽ phân tích lỗi, đối chiếu với cấu trúc DOM gốc và yêu cầu LLM tái cấu trúc lại XPath cho đến khi đạt độ chính xác tuyệt đối.32

### **Ánh xạ Dữ liệu Cấu trúc Động (Dynamic Schema Mapping)**

Khi thông tin được bóc tách từ nhiều trang web, hệ thống phải đối mặt với sự khác biệt về thuật ngữ và cấu trúc (ví dụ: một trang web gọi là "Người đại diện", trang khác gọi là "Tác giả"). Hệ thống sử dụng tính năng ánh xạ tự động (Schema Mapping Automation) được hỗ trợ bởi AI để hợp nhất dữ liệu vào định dạng chung.34

Kỹ thuật được áp dụng là trích xuất theo Lược đồ Pydantic (Pydantic Schema) hoặc cấu trúc JSON được định nghĩa sẵn.11 Quản trị viên chỉ cần khai báo một khuôn mẫu JSON mục tiêu (destination schema) và một hướng dẫn bằng ngôn ngữ tự nhiên (instruction).11 Ví dụ: *"Tự động tách 'Họ và Tên' từ nguồn gốc thành hai trường 'First\_Name' và 'Last\_Name', và nếu bài viết có chứa từ khóa 'Kinh tế', gán giá trị 'Category' là 'Macroeconomics'"*.38 AI sẽ tự động phân tích các tiêu đề cột, loại dữ liệu, nội suy các mối quan hệ đa tầng, sau đó tạo ra các suy luận ánh xạ kèm theo điểm độ tin cậy (confidence scores). Nhờ vậy, từ một trang web hỗn độn, dữ liệu đầu ra luôn là một tệp JSON sạch sẽ, tuân thủ tuyệt đối cấu trúc mà các hệ thống hạ nguồn (downstream applications) yêu cầu, xóa bỏ kỷ nguyên của các chuỗi kịch bản lập trình dài dòng (zero-template logic).33

## **Cấu hình Hệ thống Thành Chiến dịch và Phân phối Dữ liệu Đa Khách thể**

Giá trị thực sự của một nền tảng thu thập dữ liệu chuyên nghiệp không chỉ nằm ở khâu "cào dữ liệu", mà còn ở khả năng tổ chức, quản trị chiến dịch ở quy mô lớn và điều phối dữ liệu tinh xảo tới các điểm cuối (endpoints) đích.1

### **Cấu trúc Phân cấp Thu thập Dữ liệu (Campaign Hierarchy)**

Hệ thống được thiết kế dựa trên một cây cấu trúc dữ liệu phân cấp (Hierarchy Management), mang lại khả năng quản trị logic minh bạch đối với hàng triệu tác vụ thu thập đang chạy song song:

1. **Chiến dịch (Campaigns)**: Là các container cấp cao nhất định hình mục tiêu vĩ mô. Một tổ chức có thể thiết lập nhiều chiến dịch độc lập như "Chiến dịch Thu thập Thông tin Đấu thầu Toàn quốc" hoặc "Chiến dịch Theo dõi Biến động Giá Thương mại điện tử". Mỗi chiến dịch được gắn các tham số riêng biệt về quyền ưu tiên tài nguyên điện toán, tỷ lệ luân phiên proxy, và cấu hình băng thông mạng.40  
2. **Nguồn thu thập (Sources)**: Bên trong mỗi chiến dịch, quản trị viên chỉ định các tên miền hoặc URL hạt giống (seed URLs). Các nguồn này sẽ tự động trải qua quy trình xác thực tính liên tục. Nền tảng cấu hình bộ đệm thông minh (Smart TTL Cache) theo dõi ngày sửa đổi cuối cùng của tệp sitemap.xml (validate\_sitemap\_lastmod) để đảm bảo không tiêu tốn tài nguyên cào lại các nội dung cũ (Data Freshness Management).11  
3. **Danh mục Thu thập (Categories)**: Trong cùng một nguồn, hệ thống cho phép phân nhánh thành các danh mục chi tiết (ví dụ: Tin Trong nước, Tin Thế giới, Video Giải trí). Thông qua bộ định tuyến siêu dữ liệu, mỗi danh mục được ánh xạ với một chiến lược trích xuất XPath hoặc AI riêng biệt, đồng thời thiết lập chính sách lưu trữ dài hạn.40

Khả năng phân tán khối lượng công việc được tối ưu hóa thông qua các hàm điều phối nâng cao (như arun\_many()), cho phép vận hành đồng thời (genuine parallel processing) các tập hợp URL khác nhau với các chiến lược cấu hình (multi-config intelligence) riêng biệt trong cùng một lô (batch).11

### **Hệ thống Phân phối Dữ liệu Đa Khách thể (Multi-Tenant Data Routing)**

Sau khi dữ liệu thô được tinh chế thành thông tin có cấu trúc chuẩn, hệ thống đối mặt với bài toán phân phối lưu lượng: Làm thế nào để định tuyến các danh mục nội dung khác nhau tới các trang web con và hệ thống quản trị nội dung (CMS) thuộc các phòng ban hoặc công ty con khác nhau, mà vẫn dùng chung một nền tảng hạ tầng thống nhất? Lời giải nằm ở việc triển khai kiến trúc đa khách thể (Multi-Tenant Architecture).4

Kiến trúc đa khách thể (multi-tenancy) hoạt động tương tự như một tòa nhà chung cư cao tầng: một kết cấu hạ tầng mạng cốt lõi (backend/database) được chia sẻ cho nhiều khách thuê (tenants \- các trang web con), nhưng dữ liệu và cấu hình giao diện của từng người hoàn toàn được cách ly an toàn trong không gian riêng của họ.43 Hệ thống thu thập dữ liệu được thiết kế tương thích sâu sắc với mô hình CMS không đầu (Headless CMS). Trong kiến trúc Headless, nội dung dữ liệu backend được tách rời hoàn toàn khỏi mã nguồn hiển thị frontend.43 Khi crawler đẩy dữ liệu về trung tâm, hệ thống sử dụng các bộ API GraphQL hoặc RESTful để phân phát các luồng thông tin này đến nhiều thiết bị và giao diện khác nhau (ứng dụng di động, trang web tĩnh, cổng thông tin nội bộ) mà không bị phụ thuộc vào bất kỳ công nghệ giao diện cụ thể nào.5

Việc phân phối tới "cụ thể các chuyên mục" trên hệ thống khách thể yêu cầu một luồng định tuyến dữ liệu tự động (Automated Data Mapping Pipeline). Quản trị viên xây dựng các quy tắc kinh doanh (business rules) trong bộ máy định tuyến để tự động hóa hoàn toàn việc này.47 Ví dụ, bất kỳ nội dung pháp quy nào được crawler bóc tách thành công và được AI gán nhãn category: thuế sẽ ngay lập tức được đẩy qua API, với tham số TenantID \= 05 (Trang web Kế toán) và SectionID \= 22 (Chuyên mục Phân tích Luật Thuế).

### **Chiến lược Triển khai Cơ sở Dữ liệu cho Mô hình Đa Khách thể**

Khả năng linh hoạt trong định tuyến nội dung phụ thuộc rất lớn vào kiến trúc lưu trữ dữ liệu đa khách thể được chọn. Việc chia sẻ tài nguyên mang lại hiệu quả chi phí khổng lồ, nhưng đi kèm với các thách thức phức tạp về phân tách dữ liệu (Data Partitioning) và rủi ro rò rỉ chéo.44 Qua phân tích các mẫu thiết kế nền tảng (Design Patterns), có ba mô hình triển khai cơ sở dữ liệu phổ biến để hỗ trợ một hệ thống crawler phân phối nội dung quy mô lớn 42:

| Mô hình Cơ sở Dữ liệu Đa Khách thể | Đặc tính Kỹ thuật và Cấu trúc | Lợi ích Chiến lược | Điểm hạn chế và Thách thức Vận hành |
| :---- | :---- | :---- | :---- |
| **Bảng Đa Khách Thể (Multi-Tenant Table \- MTT) / Chung CSDL, Chung Lược đồ** | Tất cả các trang web con (tenants) lưu trữ dữ liệu cào được trong cùng một cơ sở dữ liệu và cùng một tập hợp bảng. Các hàng dữ liệu (rows) được phân biệt nghiêm ngặt thông qua một cột định danh duy nhất (ví dụ: Tenant\_ID).42 | Mô hình tiết kiệm tài nguyên và thân thiện với chi phí nhất. Khả năng mở rộng vô hạn (Scalability), có thể phục vụ hàng triệu tenant mà không gia tăng độ trễ cơ sở hạ tầng. Việc bổ sung một hệ thống CMS con mới diễn ra ngay lập tức.42 | Tính cô lập dữ liệu yếu nhất. Rủi ro cao về bảo mật nếu các truy vấn phần mềm thiếu logic lọc Tenant\_ID (yêu cầu cấu hình Row-Level Security khắt khe). Rất khó để một trang web con tùy chỉnh các trường dữ liệu (columns) mới riêng rẽ mà không làm ảnh hưởng đến cấu trúc tổng thể.42 |
| **Chung Cơ sở Dữ liệu, Riêng Lược đồ (Shared DB, Isolated Schema)** | Các trang web con sử dụng chung phần cứng máy chủ CSDL vật lý nhưng mỗi trang web sở hữu một Lược đồ (Schema) hoàn toàn riêng biệt. Cấu trúc bảng biểu (tables) được nhân bản độc lập cho từng hệ thống.51 | Đạt được sự cân bằng tuyệt vời giữa hiệu suất phân bổ tài nguyên và tính cô lập dữ liệu hợp lý. Tách biệt rủi ro truy cập nhầm lẫn giữa các trang web con. Hỗ trợ cập nhật và sao lưu dữ liệu cho từng đối tượng dễ dàng hơn.51 | Sự gia tăng số lượng tenant kéo theo sự gia tăng tuyến tính của số lượng Schema, gây ra khó khăn trong việc vận hành bộ nhớ đệm cơ sở dữ liệu và bảo trì các mã lệnh định tuyến kết nối động.51 |
| **Khách Thể Cấp Đối Tượng (Object Per Tenant \- OPT) / Hệ thống Hoàn toàn Độc lập** | Mỗi một trang web con sở hữu một cơ sở dữ liệu và máy chủ ứng dụng hoàn toàn chuyên dụng, tách biệt vật lý hoặc luận lý. Hệ thống crawler gửi yêu cầu qua các cổng kết nối API độc lập.42 | Tính bảo mật và cô lập dữ liệu đạt mức tối đa. Ngăn chặn triệt để tình trạng cạnh tranh tài nguyên (Noisy Neighbor), đảm bảo hiệu năng tải trang tĩnh không bị ảnh hưởng bởi lưu lượng cào dữ liệu của tenant khác. Khả năng cá nhân hóa cấu trúc dữ liệu không giới hạn.42 | Chi phí lưu trữ và điện toán tăng phi mã. Việc triển khai các bản cập nhật phần mềm hoặc điều chỉnh luồng dữ liệu đòi hỏi quá trình can thiệp phức tạp lên hàng loạt hệ thống, làm giảm tính tự động hóa tổng thể.50 |

Đối với cấu hình của hệ thống crawler ưu tiên phân phối tin tức, tài liệu và video tới hàng loạt chuyên mục của nhiều trang web con, mô hình **Chung CSDL, Chung Lược đồ (MTT)** thường được khuyến nghị áp dụng nhờ sự kết hợp cùng kiến trúc **Phân mảnh Đa Khách thể (Sharded Multi-Tenancy)**.42 Dữ liệu cào được sẽ được phân tách thành các vùng phân mảnh (shards) dựa trên dung lượng của chiến dịch hoặc vị trí địa lý của hệ thống web con đích, qua đó giải quyết triệt để rào cản tắc nghẽn cổ chai (bottleneck) trong quá trình ghi dữ liệu đồng thời.49 Các mã định danh cấp phát động sẽ ánh xạ tự động luồng thông tin vào hàng ngàn thư mục con của Headless CMS thông qua kiến trúc hướng sự kiện (event-driven architecture), giảm thiểu độ trễ từ lúc dữ liệu được bóc tách cho đến lúc người dùng cuối nhìn thấy bài viết mới trên giao diện.4

## **Kết luận**

Hệ thống phần mềm thu thập dữ liệu hiện đại là một tổ hợp các công nghệ điện toán tiên tiến nhất, vượt xa khái niệm cào HTML truyền thống. Phân tích chi tiết kiến trúc kỹ thuật chỉ ra rằng sức mạnh của nền tảng hội tụ ở ba yếu tố quyết định:

Thứ nhất, tính linh hoạt và đa năng trong bóc tách thông tin đa phương tiện. Mọi loại tài liệu phức tạp, từ sự phân mảnh của luồng video HLS (.m3u8), các tài liệu pháp quy PDF dày đặc chữ cần xử lý bằng hệ thống nhãn quan máy tính (OCR) và NLP, cho đến các kiến trúc web động (ReactJS) và hệ thống trạng thái máy chủ bảo thủ (ASP.NET), đều được giải mã thông qua mạng lưới các trình duyệt không đầu và thuật toán giả lập trạng thái phiên bản tinh vi.

Thứ hai, khả năng sinh tồn độc lập trong môi trường an ninh mạng khắc nghiệt. Việc sử dụng mạng IP xoay vòng quy mô lớn kết hợp với các khung ẩn danh (như Nodriver) cho phép giả mạo chữ ký TLS và vân tay sinh trắc học hoàn hảo. Điều này cho phép hệ thống vô hiệu hóa sự kiểm duyệt của các bộ quy tắc tường lửa học máy (WAF) khắt khe nhất, bảo toàn tính liên tục của luồng cào dữ liệu ngay cả khi đối mặt với các bẫy kiểm thử Turnstile hay CAPTCHA.

Thứ ba, sự hội nhập sâu sắc của AI vào quá trình điều phối chiến dịch Đa Khách thể. Thay vì phụ thuộc vào lập trình thủ công, hệ thống trao quyền cho Mô hình Ngôn ngữ Lớn để tự động thu gọn DOM, sinh mã XPath một cách tự động để thích ứng với mọi sự thay đổi giao diện, và tự động hóa toàn bộ luồng tư duy ánh xạ dữ liệu (Schema Mapping). Sự hỗ trợ này giảm thiểu hàng trăm giờ công thiết lập cấu hình. Kết hợp cùng mô hình quản trị chiến dịch phân cấp và định tuyến dữ liệu theo kiến trúc Headless CMS đa khách thể, hệ thống đáp ứng trọn vẹn yêu cầu vận hành tự động, cô lập dữ liệu an toàn và phân phối tri thức chính xác tuyệt đối tới hàng ngàn chuyên mục trên hệ sinh thái trực tuyến của doanh nghiệp.

Dựa trên các yêu cầu của hệ thống, dưới đây là danh sách các tính năng nghiệp vụ cốt lõi của phần mềm thu thập dữ liệu (crawler), được trình bày hoàn toàn dưới góc độ chức năng ứng dụng thực tế và không bao gồm các đề xuất công nghệ kỹ thuật sâu:

**1\. Nhóm Tính năng Thu thập và Trích xuất Dữ liệu (Crawling & Extraction)**

* **Thu thập đa định dạng:** Khả năng tiếp cận, tải về và xử lý đa dạng các loại nội dung bao gồm văn bản tin tức, thư viện hình ảnh, luồng video phát trực tuyến, cho đến các tài liệu pháp quy đính kèm như PDF, Word, hoặc Excel.  
* **Tương thích mọi cấu trúc Website:** Hỗ trợ thu thập thông tin mượt mà trên nhiều nền tảng web khác nhau, từ các website tĩnh truyền thống, website động tải dữ liệu ngầm, ứng dụng một trang (Single Page Application), cho đến các hệ thống yêu cầu duy trì trạng thái phiên làm việc phức tạp hoặc bắt buộc đăng nhập.  
* **Tự động hóa hành vi tương tác:** Hệ thống có khả năng mô phỏng các thao tác của người thật như tự động cuộn trang, nhấp chuột, điền biểu mẫu, hoặc chọn danh mục để kích hoạt hiển thị đầy đủ các dữ liệu bị ẩn.  
* **Vượt rào cản chặn truy cập tự động:** Khả năng tự động nhận diện và vượt qua các hệ thống tường lửa ứng dụng web (WAF), tự động giải quyết các bài kiểm tra xác thực (như CAPTCHA) và thay đổi đặc điểm nhận dạng để quá trình thu thập không bị gián đoạn hay đánh dấu là bot độc hại.

**2\. Nhóm Tính năng Ứng dụng Trí tuệ Nhân tạo (AI Automation)**

* **Tự động nhận diện và bóc tách nội dung:** Sử dụng AI để tự động đọc hiểu bố cục trang web và trích xuất chính xác các vùng thông tin cần thiết (như tiêu đề bài viết, giá trị sản phẩm, số hiệu văn bản pháp luật, cơ quan ban hành) mà không cần con người định nghĩa quy tắc thủ công.  
* **Tự phục hồi và điều chỉnh kịch bản (Self-healing):** Hệ thống có khả năng nhận biết khi website nguồn thay đổi giao diện, từ đó AI tự động sinh ra kịch bản mới để tiếp tục thu thập dữ liệu mà không cần lập trình viên can thiệp sửa mã.  
* **Ánh xạ dữ liệu thông minh (Schema Mapping):** AI tự động phân tích, chuẩn hóa và đồng bộ các thông tin có tên gọi khác nhau từ nhiều nguồn (ví dụ: gộp trường "Người đại diện" ở nguồn A và "Tác giả" ở nguồn B) vào chung một cấu trúc chuẩn của hệ thống lưu trữ.  
* **Số hóa tài liệu quét (OCR & NLP):** Tự động đọc và chuyển đổi nội dung từ các tệp PDF dạng ảnh quét thành văn bản máy tính, đồng thời bóc tách các điều khoản, thông tin tóm tắt bên trong tài liệu để lưu trữ dưới dạng có cấu trúc.

**3\. Nhóm Tính năng Quản trị Chiến dịch và Nguồn Thu thập**

* **Quản lý phân cấp logic:** Cho phép quản trị viên thiết lập hệ thống theo sơ đồ dạng cây: Chiến dịch tổng thể \-\> Nguồn website mục tiêu \-\> Danh mục chuyên sâu (ví dụ: Nguồn báo A \-\> Danh mục Tin Kinh tế), giúp dễ dàng vận hành và theo dõi hàng ngàn tác vụ song song.  
* **Lập lịch trình và phân bổ ưu tiên:** Cung cấp tính năng cài đặt thời gian chạy tự động (theo giờ, ngày, hoặc chạy liên tục) và ưu tiên tài nguyên cho những chuyên mục mang tính thời sự, cần độ trễ thấp.  
* **Quản lý tính toàn vẹn và chống trùng lặp:** Hệ thống tự động so sánh, loại bỏ nội dung đã thu thập trước đó, chỉ bóc tách những bài viết mới xuất bản hoặc những nội dung có sự thay đổi cập nhật từ trang nguồn.

**4\. Nhóm Tính năng Phân phối Dữ liệu Đa Khách thể (Multi-Tenant Routing)**

* **Định tuyến nội dung tự động:** Cho phép thiết lập các bộ quy tắc tự động hóa để phân phối dữ liệu vừa thu thập về đúng trang web con (tenant) và đúng chuyên mục đích (Ví dụ: Các văn bản được AI gắn nhãn "Kế toán" sẽ tự động chuyển về mục "Quy định" trên trang web của phòng Tài chính).  
* **Cô lập và bảo mật dữ liệu khách thể:** Đảm bảo mỗi trang web con hoạt động trong một không gian dữ liệu riêng biệt. Quản trị viên của trang web con này không thể can thiệp vào cấu hình hoặc dữ liệu của trang web con khác dù đang sử dụng chung một hệ thống trung tâm.

**5\. Nhóm Tính năng Giám sát và Báo cáo**

* **Thống kê hiệu suất chiến dịch:** Cung cấp các báo cáo trực quan về khối lượng dữ liệu, số lượng bài viết, tài liệu, luồng video đã thu thập thành công theo thời gian thực đối với từng nguồn cụ thể.  
* **Cảnh báo sự cố:** Tự động gửi cảnh báo cho đội ngũ quản trị khi phát hiện lỗi gián đoạn từ nguồn, lỗi thay đổi cấu trúc nghiêm trọng mà AI không thể tự phục hồi, hoặc khi IP thu thập bị đưa vào danh sách đen.

Tính năng "Khai báo Nguồn tin" (Source Declaration) là trung tâm điều khiển của hệ thống crawler, nơi quản trị viên thiết lập các quy tắc từ cơ bản đến nâng cao để tiếp cận và trích xuất dữ liệu. Để đáp ứng đa dạng các loại kiến trúc website, tính năng này được chia thành các nhóm cấu hình chi tiết như sau:

**1\. Cấu hình Thông tin Nền tảng và Điều phối**

* **Định danh & Phân loại:** Khai báo URL gốc (Seed URL), tên nguồn tin, định dạng dữ liệu đích (tin tức, video, tài liệu), và thiết lập ánh xạ nguồn tin này vào các chuyên mục cụ thể trên hệ thống phân phối.  
* **Chính sách Lịch trình:** Cài đặt tần suất quét (ví dụ: quét sitemap mỗi 15 phút), giới hạn độ sâu thu thập (crawl depth), số lượng trang tối đa mỗi lần chạy, và cấu hình bỏ qua các bài viết cũ dựa trên bộ đệm bộ nhớ (cache).  
* **Chiến lược Mạng:** Lựa chọn sử dụng IP nội bộ hay phải định tuyến qua mạng proxy (Proxy Rotation), thiết lập Header và giả mạo User-Agent để mô phỏng các trình duyệt hoặc thiết bị di động khác nhau.

**2\. Cấu hình Môi trường Truy xuất (Thích ứng Kiến trúc Web)** Hệ thống cho phép chọn các chế độ (engine) tải trang khác nhau tùy thuộc vào công nghệ của website đích:

* **Chế độ HTTP Thuần túy (Dành cho web HTML tĩnh, SSR, PHP):** Gửi yêu cầu tải mã nguồn HTML trực tiếp thông qua HTTP GET. Chế độ này bỏ qua việc tải hình ảnh, CSS, hay JavaScript để đạt tốc độ bóc tách nhanh nhất và tiết kiệm tài nguyên hệ thống.  
* **Chế độ Trình duyệt Không đầu (Dành cho ReactJS, VueJS, Angular):** Khởi chạy các trình duyệt tự động hóa (như Playwright/Puppeteer) để xử lý các Ứng dụng Đơn trang (SPA). Hệ thống có tính năng chờ tải trang (wait conditions) cho đến khi mã JavaScript nội bộ thực thi xong (hydrat hóa). Nâng cao hơn, tính năng này cho phép chặn bắt trực tiếp các yêu cầu mạng nội bộ (XHR/Fetch) để lấy thẳng dữ liệu JSON thô từ API của website thay vì phải đọc giao diện.  
* **Chế độ Duy trì Trạng thái (Dành cho hệ thống ASP.NET):** Cung cấp cấu hình giả lập phiên làm việc (Session). Crawler được thiết lập để đọc, lưu trữ và đính kèm các trường dữ liệu ẩn bắt buộc như `__VIEWSTATE`, `__VIEWSTATEGENERATOR` và `__EVENTVALIDATION` vào các yêu cầu POST tiếp theo. Điều này giúp hệ thống vượt qua rào cản chuyển trang hoặc chọn danh mục dropdown của ASP.NET mà không bị máy chủ trả về lỗi xác thực.

**3\. Cấu hình Bộ lọc và Bóc tách Dữ liệu (Extraction Configuration)**

* **Bóc tách Thủ công (Truyền thống):** Cung cấp giao diện để nhập các bộ chọn chính xác như XPath, CSS Selectors, hoặc Biểu thức chính quy (Regex). Hỗ trợ thiết lập quy tắc bóc tách cho các luồng phân trang, như tìm kiếm tham số `?page=N` trên URL hoặc chỉ định bộ chọn cho nút "Trang tiếp theo".  
* **Bóc tách tự động bằng AI (Zero-template Logic):** Tích hợp Trí tuệ Nhân tạo để thay thế hoàn toàn cấu trúc XPath cứng nhắc. Quản trị viên chỉ cần khai báo một "Lược đồ JSON đích" (JSON schema) kèm theo các chỉ dẫn bằng ngôn ngữ tự nhiên (ví dụ: "Tìm tất cả giá sản phẩm và quy đổi về định dạng số").  
* **AI Trợ lý Sinh XPath:** Cấu hình sử dụng AI để tự động phân tích cây giao diện (DOM), loại bỏ các thẻ HTML rác (DOM pruning) để thu gọn dữ liệu, sau đó suy luận và sinh ra các đoạn mã XPath có tính chống chịu cao, dùng để bóc tách thông tin một cách tự động và ổn định trên diện rộng.

**4\. Cấu hình Tiền xử lý và Vượt Tường lửa (Anti-Bot Evasion)**

* **Kịch bản Khởi tạo (Init Scripts):** Cho phép người dùng viết các đoạn mã JavaScript tiêm ngầm vào trình duyệt trước khi trang web tải xong. Chức năng này giúp che giấu dấu vết của phần mềm tự động hóa (ví dụ: vô hiệu hóa biến `navigator.webdriver`).  
* **Sinh trắc học Hành vi:** Cấu hình các thao tác mô phỏng con người như thời gian chờ ngẫu nhiên giữa các lần nhấp, chuyển động cuộn trang cơ học, giúp hệ thống duy trì điểm tín nhiệm cao và tránh bị các hệ thống như Cloudflare, DataDome hay Imperva phát hiện và đưa ra các bài kiểm tra chặn truy cập.

