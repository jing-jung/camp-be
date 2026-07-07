# Requirements Document

## Introduction

본 문서는 StockBrief 서비스의 AWS 배포 아키텍처 개선 요구사항을 정의합니다.  
개선 범위는 네 가지 영역으로 구성됩니다: (1) 프론트엔드 배포 방식 전환(Amplify → S3 + CloudFront), (2) WAF 적용 범위 확장(CloudFront + API Gateway), (3) 백엔드 성능 개선(캐시 레이어 도입 및 DB 쿼리 최적화), (4) 현재 아키텍처 누락 요소 보완(RDS Proxy, VPC 엔드포인트, CloudWatch 경보 등).  
현재 스택은 FastAPI + Lambda(Mangum), API Gateway HTTP API v2, PostgreSQL(RDS), Cognito JWT 인증, Bedrock/AgentCore AI, Terraform IaC, GitHub Actions CI/CD 기반이며 배포 리전은 ap-northeast-2입니다.

---

## Glossary

- **CloudFront Distribution**: AWS 글로벌 CDN 서비스. 정적 파일 및 SPA 배포와 WAF 연결에 사용됩니다.
- **S3 Static Bucket**: 프론트엔드 빌드 산출물을 저장하는 S3 버킷. OAC(Origin Access Control)를 통해 CloudFront에서만 접근 허용됩니다.
- **WAF Web ACL**: AWS WAF WebACL. IP 기반 속도 제한, 관리형 규칙(AWSManagedRulesCommonRuleSet), SQL 인젝션 방어 규칙을 포함합니다.
- **API Gateway**: AWS API Gateway HTTP API v2. Lambda 프록시 통합으로 FastAPI 백엔드를 노출합니다.
- **Lambda**: AWS Lambda. FastAPI + Mangum으로 패키징된 백엔드 함수.
- **ElastiCache Redis Cluster**: AWS ElastiCache for Redis. 외부 API 응답 캐시 및 세션 캐시에 사용되는 인메모리 캐시 레이어.
- **DB-based Cache**: 현재 구현된 `ExternalApiCacheService`. PostgreSQL `api_cache_entries` 테이블을 캐시 저장소로 사용합니다.
- **RDS**: Amazon RDS PostgreSQL 인스턴스. 서비스의 주 데이터베이스.
- **RDS Proxy**: AWS RDS Proxy. Lambda의 DB 연결 수를 제한하고 연결 재사용률을 높이는 프록시 레이어.
- **Terraform Module**: `infra/terraform/modules/` 하위의 재사용 가능한 Terraform 구성 단위.
- **OAC**: Origin Access Control. CloudFront가 S3 버킷에 서명된 요청을 전송할 수 있도록 하는 접근 제어 메커니즘.
- **SSR**: Server-Side Rendering. Lambda@Edge 또는 컨테이너 기반으로 Next.js 페이지를 서버에서 렌더링하는 방식.
- **Static Export**: Next.js `output: export` 모드. HTML/CSS/JS를 S3에 업로드하고 CloudFront로 서빙하는 방식.
- **DISTINCT ON**: PostgreSQL 고유 쿼리 절. 파티션 내 첫 번째 행만 반환하여 Python 측 필터링을 제거합니다.
- **GROUP BY Aggregation**: PostgreSQL 집계 쿼리. Python 측 루프 집계를 DB 레벨로 이전합니다.
- **lru_cache**: Python `functools.lru_cache`. Lambda warm 인스턴스에서 DB 엔진 및 Secrets Manager 호출을 재사용합니다.
- **Cold Start**: Lambda 함수가 처음 실행되거나 유휴 후 재실행될 때 발생하는 초기화 지연.
- **Provisioned Concurrency**: Lambda가 미리 초기화된 실행 환경을 유지하여 Cold Start를 제거하는 기능.

---

## Requirements

### Requirement 1: 프론트엔드 배포 - S3 + CloudFront (Static Export 옵션)

**User Story:** As a 인프라 엔지니어, I want Amplify 의존성을 제거하고 S3 + CloudFront 기반으로 프론트엔드를 배포하고 싶다, so that 배포 파이프라인 제어권을 높이고 CloudFront WAF 연동을 단순화할 수 있다.

#### Acceptance Criteria

1. THE Terraform Module SHALL `enable_amplify = false`일 때 S3 Static Bucket과 CloudFront Distribution을 생성한다.
2. THE S3 Static Bucket SHALL 퍼블릭 액세스 차단(Block Public Access)을 활성화하고 OAC를 통해서만 CloudFront에서 접근을 허용한다.
3. WHEN 프론트엔드 빌드 산출물이 S3 Static Bucket에 업로드될 때, THE CloudFront Distribution SHALL 해당 파일을 엣지 로케이션에서 캐싱하고 사용자에게 서빙한다.
4. THE CloudFront Distribution SHALL `index.html`을 기본 루트 객체로 설정하고, 4xx 오류를 `/index.html`로 리다이렉트하여 SPA 라우팅을 지원한다.
5. THE CloudFront Distribution SHALL HTTPS 전용 뷰어 프로토콜 정책(redirect-to-https)을 적용한다.
6. WHERE `enable_frontend_cloudfront = true`일 때, THE Terraform Module SHALL CloudFront Distribution의 ARN과 도메인을 Terraform output으로 노출한다.
7. THE GitHub Actions CI/CD Workflow SHALL 프론트엔드 빌드 후 `aws s3 sync`와 `aws cloudfront create-invalidation`을 순서대로 실행하여 캐시를 무효화한다.

---

### Requirement 2: 프론트엔드 배포 - SSR 옵션 (Lambda@Edge 또는 컨테이너)

**User Story:** As a 인프라 엔지니어, I want SSR이 필요한 경우를 위한 배포 경로를 문서화하고 싶다, so that 팀이 Static Export와 SSR 중 적절한 방식을 선택할 수 있다.

#### Acceptance Criteria

1. WHERE `frontend_rendering_mode = "ssr"`일 때, THE Terraform Module SHALL Lambda@Edge 함수를 CloudFront 오리진 요청 핸들러로 연결하는 구성을 지원한다.
2. WHERE `frontend_rendering_mode = "container"`일 때, THE Terraform Module SHALL ECS Fargate 서비스를 CloudFront 커스텀 오리진으로 연결하는 구성을 지원한다.
3. THE Architecture Decision Record SHALL Static Export 옵션과 SSR 옵션의 비용, Cold Start, 운영 복잡성 트레이드오프를 문서화한다.
4. WHEN SSR 모드가 활성화될 때, THE CloudFront Distribution SHALL Static Export와 동일한 WAF WebACL을 재사용한다.

---

### Requirement 3: WAF - CloudFront 적용

**User Story:** As a 보안 엔지니어, I want CloudFront 앞단에 WAF를 적용하고 싶다, so that 웹 애플리케이션 레이어 공격(SQL 인젝션, XSS, 과도한 요청)을 엣지에서 차단할 수 있다.

#### Acceptance Criteria

1. THE Terraform Module SHALL `us-east-1` 리전에 CloudFront 전용 WAF WebACL을 생성한다 (CloudFront WAF는 us-east-1 필수).
2. THE WAF WebACL SHALL AWS 관리형 규칙 그룹 `AWSManagedRulesCommonRuleSet`을 포함한다.
3. THE WAF WebACL SHALL AWS 관리형 규칙 그룹 `AWSManagedRulesKnownBadInputsRuleSet`을 포함한다.
4. THE WAF WebACL SHALL IP 기반 속도 제한 규칙을 포함하며, 동일 IP에서 5분 이내 2000회 초과 요청 시 차단한다.
5. THE CloudFront Distribution SHALL 생성된 WAF WebACL ARN을 `web_acl_id`로 연결한다.
6. WHEN WAF가 요청을 차단할 때, THE WAF WebACL SHALL 차단 이벤트를 CloudWatch Logs에 기록한다.

---

### Requirement 4: WAF - API Gateway 적용

**User Story:** As a 보안 엔지니어, I want API Gateway에도 별도 WAF를 적용하고 싶다, so that CloudFront를 우회하는 직접 API 호출을 방어할 수 있다.

#### Acceptance Criteria

1. THE Terraform Module SHALL `ap-northeast-2` 리전에 API Gateway 전용 WAF WebACL을 생성한다.
2. THE WAF WebACL SHALL AWS 관리형 규칙 그룹 `AWSManagedRulesCommonRuleSet`을 포함한다.
3. THE WAF WebACL SHALL IP 기반 속도 제한 규칙을 포함하며, 동일 IP에서 5분 이내 1000회 초과 요청 시 차단한다.
4. THE API Gateway SHALL 생성된 WAF WebACL을 Stage ARN에 연결(`aws_wafv2_web_acl_association`)한다.
5. WHEN WAF가 API 요청을 차단할 때, THE WAF WebACL SHALL 차단 이벤트를 CloudWatch Logs에 기록한다.
6. WHERE `enable_waf = false`일 때, THE Terraform Module SHALL WAF 관련 리소스 생성을 건너뛴다.

---

### Requirement 5: 캐시 레이어 - ElastiCache Redis 도입

**User Story:** As a 백엔드 엔지니어, I want ElastiCache Redis를 도입하여 외부 API 캐시를 인메모리로 처리하고 싶다, so that Lambda → RDS 왕복 횟수를 줄이고 응답 지연을 단축할 수 있다.

#### Acceptance Criteria

1. THE Terraform Module SHALL VPC 내 프라이빗 서브넷에 ElastiCache Redis Cluster를 생성한다.
2. THE ElastiCache Redis Cluster SHALL 암호화를 활성화한다 (at-rest 및 in-transit TLS).
3. THE Lambda SHALL VPC 보안 그룹을 통해 ElastiCache Redis 엔드포인트의 포트 6379에만 접근을 허용한다.
4. WHEN `REDIS_URL` 환경 변수가 설정될 때, THE ExternalApiCacheService SHALL Redis를 기본 캐시 저장소로 사용하고 DB 조회를 수행하지 않는다.
5. IF Redis 연결이 실패할 때, THEN THE ExternalApiCacheService SHALL DB-based Cache 방식으로 폴백(fallback)하고 오류를 WARNING 레벨로 기록한다.
6. THE ExternalApiCacheService SHALL TTL 만료 처리를 Redis 네이티브 TTL(`EXPIRE`)에 위임하여 `expires_at` 컬럼 기반 Python 레벨 만료 검사를 제거한다.
7. WHERE `enable_elasticache = false`일 때, THE ExternalApiCacheService SHALL 기존 DB-based Cache 방식만 사용한다.

---

### Requirement 6: 캐시 레이어 - DB 기반 캐시 코드 개선

**User Story:** As a 백엔드 엔지니어, I want DB 기반 캐시(`ExternalApiCacheService`)의 불필요한 DB 왕복을 줄이고 싶다, so that Redis 미도입 환경에서도 Lambda Cold Start 및 Warm 실행의 DB 부하를 낮출 수 있다.

#### Acceptance Criteria

1. THE ExternalApiCacheService SHALL `set()` 메서드에서 SELECT + INSERT/UPDATE 2회 쿼리를 `INSERT ... ON CONFLICT DO UPDATE` 단일 upsert 쿼리로 대체한다.
2. THE ExternalApiCacheService SHALL `set()` 메서드 내 `session.commit()` 호출을 제거하고, 호출 측(service layer)이 트랜잭션 경계를 관리하도록 한다.
3. THE ExternalApiCacheService SHALL `get()` 메서드에서 만료된 항목에 대해 즉시 DELETE를 실행하지 않고 `None`을 반환하여 읽기 경로의 쓰기 부하를 제거한다.
4. THE Terraform Module SHALL Lambda 환경 변수에 `CACHE_BACKEND` 값(`db` 또는 `redis`)을 포함시켜 캐시 백엔드를 런타임에 전환할 수 있도록 한다.

---

### Requirement 7: DB 쿼리 최적화 - EvidenceChunk 집계

**User Story:** As a 백엔드 엔지니어, I want `_candidate_evidence_summaries()` 함수에서 Python 집계를 DB 집계로 대체하고 싶다, so that 전체 EvidenceChunk 행을 Python으로 로드하는 메모리 및 네트워크 오버헤드를 제거할 수 있다.

#### Acceptance Criteria

1. THE CandidateService SHALL `_candidate_evidence_summaries()` 메서드에서 `SELECT EvidenceChunk, SourceDocument` 전체 행 로드를 `SELECT ticker, source_type, COUNT(*), MAX(published_at) GROUP BY ticker, source_type` 집계 쿼리로 교체한다.
2. WHEN `_candidate_evidence_summaries()`가 호출될 때, THE CandidateService SHALL 단일 집계 쿼리만 실행하고 Python 레벨 루프 집계를 수행하지 않는다.
3. THE 집계 쿼리 결과 SHALL `news_count`, `disclosure_count`, `latest_at` 값을 직접 포함하여 추가 Python 변환 없이 `CandidateEvidenceSummaryContract`를 생성할 수 있어야 한다.

---

### Requirement 8: DB 쿼리 최적화 - 종목 검색 COUNT 쿼리

**User Story:** As a 백엔드 엔지니어, I want `StockService.search()`에서 순차적으로 실행되는 COUNT 쿼리와 데이터 쿼리를 개선하고 싶다, so that 동일한 쿼리 조건을 두 번 평가하는 오버헤드를 줄일 수 있다.

#### Acceptance Criteria

1. THE StockService SHALL `search()` 메서드에서 COUNT 쿼리와 데이터 쿼리가 동일한 `WHERE` 조건을 공유하는 서브쿼리를 재사용하도록 구현한다.
2. WHEN `q` 파라미터가 빈 문자열이고 `market` 필터도 없을 때, THE StockService SHALL `Stock` 테이블 전체 COUNT를 캐싱하는 방식으로 반복 COUNT 쿼리를 단축할 수 있도록 설계한다.
3. THE `(ticker, company_name)` 컬럼 조합 SHALL 검색 쿼리 성능을 위한 복합 인덱스 생성 대상으로 마이그레이션에 포함된다.

---

### Requirement 9: DB 쿼리 최적화 - 최신 가격 조회 (DISTINCT ON)

**User Story:** As a 백엔드 엔지니어, I want `_latest_price_contracts()`에서 전체 가격 행을 로드한 후 Python에서 필터링하는 방식을 제거하고 싶다, so that DB가 최신 가격만 반환하도록 하여 불필요한 데이터 전송을 방지할 수 있다.

#### Acceptance Criteria

1. THE CandidateService SHALL `_latest_price_contracts()` 메서드에서 `ORDER BY ticker, trade_date DESC` 전체 로드 후 Python 필터링을 `SELECT DISTINCT ON (ticker) ... ORDER BY ticker, trade_date DESC` 단일 쿼리로 교체한다.
2. WHEN `tickers` 리스트가 제공될 때, THE CandidateService SHALL 각 ticker당 정확히 1개의 최신 `PriceMetric` 행을 반환하는 쿼리를 실행한다.
3. THE `PriceMetric` 테이블 SHALL `(ticker, trade_date DESC)` 복합 인덱스가 존재하여 DISTINCT ON 쿼리 플랜이 인덱스 스캔을 활용할 수 있어야 한다.

---

### Requirement 10: Lambda DB 연결 최적화 (Cold Start)

**User Story:** As a 인프라 엔지니어, I want Lambda Cold Start 시 Secrets Manager 호출 및 DB 엔진 초기화 지연을 줄이고 싶다, so that API 응답 지연의 Tail Latency(p99)를 낮출 수 있다.

#### Acceptance Criteria

1. THE Lambda SHALL `lru_cache` 싱글턴(`get_engine`, `get_session_factory`, `resolve_database_url`)을 유지하여 Warm 인스턴스에서 DB 엔진을 재사용한다.
2. WHERE `enable_rds_proxy = true`일 때, THE RDS Proxy SHALL Lambda의 DB 연결 수를 제한하고 연결 재사용률을 높여 Cold Start 직후 연결 폭증을 방지한다.
3. WHERE `enable_provisioned_concurrency = true`일 때, THE Lambda SHALL Provisioned Concurrency를 적용하여 Cold Start를 제거한다.
4. THE Lambda 환경 변수 SHALL `DATABASE_POOL_SIZE`와 `DATABASE_MAX_OVERFLOW`를 포함하며, RDS Proxy 활성화 여부에 따라 권장 값을 Terraform 변수로 제공한다.
5. IF Secrets Manager 호출이 Lambda 초기화 중 타임아웃될 때, THEN THE Lambda SHALL 오류를 CloudWatch Logs에 기록하고 503 응답을 반환한다.

---

### Requirement 11: 아키텍처 누락 요소 보완 - RDS Proxy 기본 활성화 경로

**User Story:** As a 인프라 엔지니어, I want `enable_rds_proxy` 변수를 사용하여 RDS Proxy 활성화 경로를 명확히 문서화하고 싶다, so that Lambda 동시성 증가 시 연결 한도 초과 없이 확장할 수 있다.

#### Acceptance Criteria

1. THE Terraform `rds_proxy` Module SHALL `enabled = true`일 때 RDS Proxy 인스턴스, IAM 역할, Secrets Manager 연결을 생성한다.
2. WHEN `enable_rds_proxy = true`일 때, THE `api_lambda` Module SHALL `database_host`로 RDS 직접 엔드포인트 대신 RDS Proxy 엔드포인트를 사용한다.
3. THE Terraform README SHALL RDS Proxy 활성화 조건(Lambda 동시 실행 수 기준)과 비용 영향을 문서화한다.

---

### Requirement 12: 아키텍처 누락 요소 보완 - CloudWatch 경보 완성도

**User Story:** As a SRE, I want CloudFront, WAF, ElastiCache에 대한 CloudWatch 경보를 추가하고 싶다, so that 배포 이후 이상 징후를 빠르게 감지할 수 있다.

#### Acceptance Criteria

1. THE CloudWatch Module SHALL CloudFront 5xx 오류율이 5% 초과 시 SNS 알림을 발생시키는 경보를 포함한다.
2. THE CloudWatch Module SHALL WAF에서 1분 동안 차단 건수가 100회 초과 시 SNS 알림을 발생시키는 경보를 포함한다.
3. WHERE `enable_elasticache = true`일 때, THE CloudWatch Module SHALL ElastiCache Redis 메모리 사용률이 80% 초과 시 SNS 알림을 발생시키는 경보를 포함한다.
4. THE `enable_operational_alarms` 변수 SHALL CloudFront, WAF, ElastiCache 경보의 생성 여부를 통합 제어한다.

---

### Requirement 13: 아키텍처 누락 요소 보완 - S3 VPC 엔드포인트 및 네트워크 완성도

**User Story:** As a 인프라 엔지니어, I want VPC 내 Lambda가 S3와 Secrets Manager에 프라이빗 경로로 접근하도록 하고 싶다, so that NAT Gateway 비용을 줄이고 데이터 전송 보안을 강화할 수 있다.

#### Acceptance Criteria

1. THE Terraform Module SHALL `s3_gateway_endpoint_enabled = true`일 때 S3 Gateway VPC 엔드포인트를 Lambda 서브넷 라우팅 테이블에 연결한다.
2. THE Terraform Module SHALL VPC 내 Lambda에 대해 Secrets Manager Interface VPC 엔드포인트를 생성하여 인터넷 우회 없이 Secrets Manager에 접근할 수 있도록 한다.
3. WHEN Lambda가 VPC 서브넷에 배치될 때, THE Lambda 보안 그룹 SHALL S3 엔드포인트(포트 443)와 RDS(포트 5432)에 대한 이그레스(egress) 규칙만 허용한다.
4. THE Terraform outputs SHALL VPC 엔드포인트 ID와 보안 그룹 ID를 포함하여 네트워크 감사 시 참조할 수 있도록 한다.
