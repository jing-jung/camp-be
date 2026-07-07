# Implementation Plan: AWS 배포 아키텍처 개선 + 백엔드 성능 최적화

## Overview

AWS 배포 아키텍처 개선 및 백엔드 성능 최적화를 단계적으로 구현한다.  
구현 순서: (1) Python 백엔드 코드 개선 (캐시 레이어·DB 쿼리·Cold Start), (2) Terraform IaC 모듈 추가 (ElastiCache·WAF·CloudFront·CloudWatch·VPC 엔드포인트), (3) GitHub Actions CI/CD 워크플로우 추가.  
Terraform 리소스는 코드 변경이며 실제 AWS 프로비저닝은 `terraform apply`로 별도 진행된다.

---

## Tasks

- [ ] 1. 백엔드 Config 및 의존성 업데이트
  - [ ] 1.1 `app/config.py`에 `redis_url`, `cache_backend`, `provisioned_concurrency_enabled` 필드 추가
    - `Settings` 클래스에 `redis_url: str = Field(default="", validation_alias="REDIS_URL")` 추가
    - `cache_backend: str = Field(default="db", validation_alias="CACHE_BACKEND")` 추가
    - _Requirements: 5.4, 6.4_

  - [ ] 1.2 `requirements.txt` (또는 `pyproject.toml`)에 `redis` 패키지 추가
    - `redis>=5.0.0` 의존성 추가 (optional extra 또는 직접 포함)
    - _Requirements: 5.4_

- [ ] 2. ExternalApiCacheService 캐시 백엔드 재구현
  - [ ] 2.1 `app/services/external/cache.py`에 `CacheBackend` Protocol 및 `_redis_key`, `_hash_payload`, `_as_utc` 헬퍼 함수 작성
    - `CacheBackend` Protocol 정의 (`get`, `set` 메서드 시그니처)
    - `_redis_key(provider, cache_key) -> str` 구현
    - `_hash_payload(payload) -> str` 구현
    - `_as_utc(value: datetime) -> datetime` 구현
    - _Requirements: 5.4, 6.1_

  - [ ] 2.2 `RedisCacheBackend` 클래스 구현
    - `redis.from_url()` 초기화
    - `get()`: Redis GET → JSON 디코딩 → `None` 반환 (키 없을 때)
    - `set()`: `SETEX` 명령으로 TTL을 Redis 네이티브 EXPIRE에 위임 (`expires_at` Python 검사 없음)
    - _Requirements: 5.4, 5.6_

  - [ ] 2.3 `DbCacheBackend` 클래스 구현 (upsert 단일 쿼리)
    - `get()`: 만료 항목은 DELETE 없이 `None` 반환 (읽기 경로 쓰기 부하 제거)
    - `set()`: `INSERT ... ON CONFLICT DO UPDATE` 단일 upsert 쿼리로 구현
    - `set()` 내 `session.commit()` 호출 제거 (호출 측이 트랜잭션 경계 관리)
    - _Requirements: 6.1, 6.2, 6.3_

  - [ ] 2.4 `ExternalApiCacheService` 팩토리 및 폴백 로직 구현
    - `_resolve_backend()`: `REDIS_URL` 환경 변수 확인 → Redis ping 시도 → 실패 시 WARNING 로그 후 DB 폴백
    - 기존 `get()`, `set()` 메서드가 새 백엔드 인터페이스를 위임하도록 수정
    - _Requirements: 5.4, 5.5, 5.7_

  - [ ]* 2.5 Property 1 테스트 작성: 캐시 백엔드 라우팅 정확성
    - **Property 1: 캐시 백엔드 라우팅 정확성**
    - `REDIS_URL` 유효 + ping 성공 → `RedisCacheBackend`, 빈 URL 또는 ping 실패 → `DbCacheBackend` 반환 확인
    - **Validates: Requirements 5.4, 5.5, 5.7**

  - [ ]* 2.6 Property 2 테스트 작성: DB 캐시 upsert 멱등성
    - **Property 2: DB 캐시 upsert 멱등성**
    - `hypothesis`로 임의 `(provider, cache_key, payload_v1, payload_v2)` 생성 후 set() 2번 호출 → get() 결과가 payload_v2와 동일한지 검증
    - **Validates: Requirements 6.1**

  - [ ]* 2.7 Property 3 테스트 작성: 만료된 캐시 항목 None 반환
    - **Property 3: 만료된 캐시 항목은 None 반환**
    - `hypothesis`로 과거 `expires_at`을 가진 항목에 대해 `get()` 호출 시 `None` 반환 및 DELETE 미실행 확인
    - **Validates: Requirements 6.3**

- [ ] 3. Alembic 마이그레이션 작성
  - [ ] 3.1 `api_cache_entries` 테이블에 `(provider, cache_key)` UNIQUE 제약 조건 추가 마이그레이션 작성
    - `ALTER TABLE api_cache_entries ADD CONSTRAINT uq_api_cache_entries_provider_cache_key UNIQUE (provider, cache_key)` 포함
    - 이미 UNIQUE 제약이 있는 경우 `IF NOT EXISTS` 처리
    - _Requirements: 6.1_

  - [ ] 3.2 `price_metrics` 테이블에 `(ticker ASC, trade_date DESC)` 복합 인덱스 추가 마이그레이션 작성
    - `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_price_metrics_ticker_trade_date_desc ON price_metrics (ticker ASC, trade_date DESC)`
    - _Requirements: 9.3_

  - [ ] 3.3 `stocks` 테이블에 `(ticker, company_name)` 복합 인덱스 추가 마이그레이션 작성
    - `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stocks_ticker_company_name ON stocks (ticker, company_name)`
    - _Requirements: 8.3_

- [ ] 4. DB 쿼리 최적화 — CandidateService
  - [ ] 4.1 `app/services/candidate_service.py`의 `_candidate_evidence_summaries()` 메서드를 GROUP BY 집계 쿼리로 교체
    - `SELECT EvidenceChunk.ticker, SourceDocument.source_type, COUNT(*), MAX(coalesce(...))` + `GROUP BY` 집계 단일 쿼리로 변경
    - Python 루프 집계 로직 제거
    - 결과를 `CandidateEvidenceSummaryContract`로 직접 변환
    - _Requirements: 7.1, 7.2, 7.3_

  - [ ]* 4.2 Property 4 테스트 작성: EvidenceChunk GROUP BY 집계 정확성
    - **Property 4: EvidenceChunk GROUP BY 집계 정확성**
    - `hypothesis`로 임의 ticker 집합과 EvidenceChunk/SourceDocument 데이터 생성 후, 기존 Python 루프 집계 결과와 새 GROUP BY 집계 결과가 동일한지 검증
    - **Validates: Requirements 7.1, 7.2, 7.3**

  - [ ] 4.3 `app/services/candidate_service.py`의 `_latest_price_contracts()` 메서드를 `DISTINCT ON (ticker)` 쿼리로 교체
    - `select(PriceMetric).where(...).distinct(PriceMetric.ticker).order_by(ticker ASC, trade_date DESC)` 단일 쿼리로 변경
    - 전체 행 로드 후 Python 필터링 로직 제거
    - _Requirements: 9.1, 9.2_

  - [ ]* 4.4 Property 5 테스트 작성: DISTINCT ON 쿼리 ticker당 최신 가격 1건
    - **Property 5: DISTINCT ON 쿼리 — ticker당 최신 가격 1건**
    - `hypothesis`로 임의 ticker 목록과 복수 PriceMetric 행 생성 후, 각 ticker당 정확히 1건이 반환되고 `trade_date`가 최신임을 검증
    - **Validates: Requirements 9.1, 9.2**

- [ ] 5. DB 쿼리 최적화 — StockService COUNT 캐싱
  - [ ] 5.1 `app/services/stock_service.py`의 `search()` 메서드에 전체 COUNT `lru_cache` 캐싱 적용
    - `q=""` & 필터 없는 경우 `_total_stock_count(session_factory)` lru_cache 함수 호출로 반복 COUNT 쿼리 단축
    - COUNT와 데이터 쿼리가 동일 WHERE 조건 서브쿼리를 공유하도록 구현
    - _Requirements: 8.1, 8.2_

- [ ] 6. Lambda Cold Start 최적화 — Secrets Manager 예외 처리
  - [ ] 6.1 `app/services/external/aws_secrets.py`에 Secrets Manager 타임아웃 예외 처리 추가
    - `try/except` 블록으로 모든 예외를 포착하여 `logger.error()` 기록 후 재 raise
    - FastAPI 글로벌 예외 핸들러가 503 응답을 반환하도록 기존 핸들러 동작 확인
    - _Requirements: 10.5_

- [ ] 7. Checkpoint — 백엔드 코드 변경 검증
  - 모든 기존 테스트 통과 및 신규 property 테스트 통과 확인. 사용자에게 질문이 있으면 여기서 확인을 요청한다.

- [ ] 8. Terraform — ElastiCache Redis 모듈
  - [ ] 8.1 `infra/terraform/modules/elasticache/` 디렉터리 생성 및 `main.tf`, `variables.tf`, `outputs.tf` 작성
    - `aws_elasticache_subnet_group`, `aws_elasticache_cluster` (at-rest/in-transit 암호화 활성화) 리소스 정의
    - `aws_security_group.redis` 보안 그룹 정의 (포트 6379)
    - `enabled` 조건부 `count` 패턴 적용
    - _Requirements: 5.1, 5.2_

  - [ ] 8.2 `infra/terraform/main.tf`에 `module "elasticache"` 블록 추가 및 Lambda 보안 그룹에 포트 6379 이그레스 규칙 추가
    - `enable_elasticache` 변수 선언
    - `module.api_lambda` 환경 변수에 `REDIS_URL`, `CACHE_BACKEND` 주입
    - Lambda → Redis 포트 6379 이그레스 규칙(`aws_security_group_rule.lambda_redis_egress`) 추가
    - _Requirements: 5.3, 5.4, 6.4_

- [ ] 9. Terraform — WAF 모듈 (CloudFront + API Gateway)
  - [ ] 9.1 `infra/terraform/modules/waf_cloudfront/` 디렉터리 생성 및 CloudFront WAF WebACL Terraform 코드 작성
    - `provider = aws.us_east_1`, `scope = "CLOUDFRONT"`
    - `AWSManagedRulesCommonRuleSet` (priority 10), `AWSManagedRulesKnownBadInputsRuleSet` (priority 20) 관리형 규칙 그룹 추가
    - IP Rate Limit 규칙 (5분 이내 2000회 초과 차단) 추가
    - CloudWatch Logs WAF 로그 그룹 및 `aws_wafv2_web_acl_logging_configuration` 추가
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.6_

  - [ ] 9.2 `infra/terraform/modules/waf_apigw/` 디렉터리 생성 및 API Gateway WAF WebACL Terraform 코드 작성
    - `scope = "REGIONAL"`, `ap-northeast-2`
    - `AWSManagedRulesCommonRuleSet` 관리형 규칙 그룹 추가
    - IP Rate Limit 규칙 (5분 이내 1000회 초과 차단) 추가
    - `aws_wafv2_web_acl_association` 리소스로 API Gateway Stage ARN 연결
    - CloudWatch Logs WAF 로그 그룹 및 로깅 설정 추가
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [ ] 9.3 `infra/terraform/main.tf`에 `enable_waf` 변수 및 WAF 모듈 블록 추가
    - `enable_waf = false` 시 WAF 리소스 생성 건너뜀 (`count = var.enable_waf ? 1 : 0`)
    - `aws.us_east_1` provider alias 설정
    - _Requirements: 4.6_

- [ ] 10. Terraform — 프론트엔드 CloudFront 모듈
  - [ ] 10.1 `infra/terraform/modules/frontend_cloudfront/` 디렉터리 생성 및 S3 버킷, OAC, CloudFront Distribution Terraform 코드 작성
    - `aws_s3_bucket`, `aws_s3_bucket_public_access_block` (Block Public Access 전체 활성화)
    - `aws_cloudfront_origin_access_control` (sigv4 서명), `aws_s3_bucket_policy` (OAC Principal만 허용)
    - `aws_cloudfront_distribution`: `default_root_object = "index.html"`, `viewer_protocol_policy = "redirect-to-https"`, 4xx/403 → `/index.html` custom_error_response
    - WAF WebACL ARN `web_acl_id` 연결
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

  - [ ] 10.2 `infra/terraform/modules/frontend_cloudfront/outputs.tf`에 `cloudfront_distribution_arn`, `cloudfront_domain_name`, `frontend_s3_bucket_name` output 추가
    - _Requirements: 1.6_

  - [ ] 10.3 `infra/terraform/main.tf`에 `enable_frontend_cloudfront`, `frontend_rendering_mode` 변수 및 `module "frontend_cloudfront"` 블록 추가
    - `frontend_rendering_mode` validation 블록 포함 (`static` | `ssr` | `container`)
    - SSR 모드(`ssr`, `container`) 조건부 리소스 구성 주석 포함
    - _Requirements: 1.1, 2.1, 2.2_

- [ ] 11. Terraform — CloudWatch 경보 확장
  - [ ] 11.1 `infra/terraform/alarms.tf`에 CloudFront 5xx 오류율 경보 추가
    - `enable_operational_alarms && enable_frontend_cloudfront` 조건부 생성
    - 5% 초과 시 SNS 알림 (`evaluation_periods = 3`, `datapoints_to_alarm = 2`)
    - _Requirements: 12.1_

  - [ ] 11.2 `infra/terraform/alarms.tf`에 WAF 차단 수 경보 추가
    - `enable_operational_alarms && enable_waf` 조건부 생성
    - 1분 동안 100회 초과 차단 시 SNS 알림
    - _Requirements: 12.2_

  - [ ] 11.3 `infra/terraform/alarms.tf`에 ElastiCache 메모리 사용률 경보 추가
    - `enable_operational_alarms && enable_elasticache` 조건부 생성
    - 80% 초과 시 SNS 알림 (`evaluation_periods = 3`, `datapoints_to_alarm = 2`)
    - `enable_operational_alarms` 통합 변수로 3개 경보 생성 여부 제어
    - _Requirements: 12.3, 12.4_

- [ ] 12. Terraform — VPC 엔드포인트 outputs 보완
  - [ ] 12.1 `infra/terraform/outputs.tf`에 `secretsmanager_vpc_endpoint_id`, `s3_vpc_endpoint_id`, `lambda_security_group_id` output 추가
    - `try(aws_vpc_endpoint.secretsmanager[0].id, "")` 패턴 사용
    - 네트워크 감사 참조용
    - _Requirements: 13.4_

- [ ] 13. Terraform — Lambda DB 연결 최적화 변수 추가
  - [ ] 13.1 `infra/terraform/variables.tf`에 `DATABASE_POOL_SIZE`, `DATABASE_MAX_OVERFLOW` 변수 추가 및 `api_lambda` 모듈 환경 변수에 주입
    - `enable_rds_proxy = true` 시 권장 값 (`POOL_SIZE=2`, `MAX_OVERFLOW=0`) 주석 문서화
    - `enable_rds_proxy = false` 시 권장 값 (`POOL_SIZE=5`, `MAX_OVERFLOW=10`) 주석 문서화
    - _Requirements: 10.4_

  - [ ] 13.2 `infra/terraform/variables.tf`에 `enable_provisioned_concurrency`, `provisioned_concurrency_count` 변수 추가
    - Lambda 모듈에서 `aws_lambda_provisioned_concurrency_config` 리소스 조건부 생성 (`count = var.enable_provisioned_concurrency ? 1 : 0`)
    - _Requirements: 10.3_

- [ ] 14. Terraform — lru_cache 싱글턴 Property 테스트
  - [ ]* 14.1 Property 6 테스트 작성: lru_cache 싱글턴 동일성
    - **Property 6: lru_cache 싱글턴 동일성**
    - `app/db.py`의 `get_engine()`, `get_session_factory()` 다중 호출 시 `is` 비교로 동일 객체 반환 확인
    - `hypothesis` `@given` 또는 parametrize로 호출 횟수 변화에도 동일 객체 보장 검증
    - **Validates: Requirements 10.1**

- [ ] 15. GitHub Actions CI/CD — 프론트엔드 배포 워크플로우 추가
  - [ ] 15.1 `.github/workflows/frontend-deploy.yml` 신규 파일 작성
    - `npm run build` → `aws s3 sync frontend/out/ s3://.../ --delete` → `aws cloudfront create-invalidation --paths "/*"` 순서로 step 구성
    - Terraform output에서 `frontend_s3_bucket_name`, `cloudfront_distribution_id` 읽기 step 포함
    - `enable_frontend_cloudfront = true`일 때만 실행되도록 조건 추가
    - _Requirements: 1.7_

- [ ] 16. Final Checkpoint — 전체 통합 검증
  - 모든 pytest 테스트(단위·속성 기반) 통과 확인, Terraform `validate` 및 `fmt` 실행, GitHub Actions workflow YAML 문법 검증. 사용자에게 질문이 있으면 여기서 확인을 요청한다.

---

## Notes

- 태스크 앞에 `*`가 붙은 항목은 선택 사항이며, MVP를 빠르게 전달하려는 경우 건너뛸 수 있다.
- 각 태스크는 특정 요구사항에 대한 추적성을 위해 _Requirements_ 레퍼런스를 포함한다.
- Property 테스트는 `pytest` + `hypothesis` 라이브러리를 사용하며 최소 100회 반복을 기본으로 한다.
- Terraform 모듈 변경은 코드 변경이며 실제 인프라 프로비저닝은 `terraform apply`로 별도 진행된다.
- Checkpoint 태스크에서 자동화 테스트가 통과하지 않을 경우 해당 영역 구현 태스크로 되돌아가 수정한다.
- RDS Proxy(`enable_rds_proxy`)와 Secrets Manager/S3 VPC 엔드포인트는 `main.tf`에 이미 조건부 구현이 존재하므로 보완(outputs 추가, 변수 문서화)만 수행한다.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "3.1", "3.2", "3.3"] },
    { "id": 1, "tasks": ["2.1", "5.1", "6.1", "8.1", "9.1", "9.2", "10.1", "12.1", "13.1", "13.2"] },
    { "id": 2, "tasks": ["2.2", "2.3", "4.1", "4.3", "8.2", "9.3", "10.2", "11.1", "11.2", "11.3"] },
    { "id": 3, "tasks": ["2.4", "10.3", "15.1"] },
    { "id": 4, "tasks": ["2.5", "2.6", "2.7", "4.2", "4.4", "14.1"] }
  ]
}
```
