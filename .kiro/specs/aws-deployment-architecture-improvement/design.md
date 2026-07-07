# Design Document

## AWS 배포 아키텍처 개선 + 백엔드 성능 최적화

---

## Overview

StockBrief 서비스의 AWS 배포 아키텍처를 개선하고 백엔드 성능을 최적화한다.
개선 범위: (1) 프론트엔드 배포 전환 (Amplify → S3 + CloudFront), (2) WAF 적용 확장
(CloudFront + API Gateway), (3) ElastiCache Redis 도입 및 DB 캐시 코드 개선,
(4) DB 쿼리 최적화 (GROUP BY, DISTINCT ON, COUNT), (5) Lambda Cold Start 개선,
(6) CloudWatch 경보 및 VPC 엔드포인트 보완.

현재 스택: FastAPI + Mangum + Lambda, API Gateway HTTP API v2, PostgreSQL(RDS),
Cognito JWT, Bedrock/AgentCore AI, Terraform IaC, GitHub Actions CI/CD.
배포 리전: ap-northeast-2.

---

## Architecture

### 전체 시스템 아키텍처 (개선 후)

```
사용자 브라우저
    │
    ▼
[CloudFront Distribution]  ◄──── WAF WebACL (us-east-1)
    │ 정적 파일 서빙         CloudFront 5xx 경보
    │
    ├── Origin 1: S3 Static Bucket (OAC, Block Public Access)
    │   └── Next.js Static Export (HTML/CSS/JS)
    │
    └── Origin 2: API Gateway HTTP API v2
            │
            ▼
        WAF WebACL (ap-northeast-2) ── WAF 차단 수 경보
            │
            ▼
        Lambda (FastAPI + Mangum)
            │   lru_cache: get_engine, get_session_factory, resolve_database_url
            │
            ├── ElastiCache Redis ── ElastiCache 메모리 경보
            │   (REDIS_URL 설정 시 기본 캐시 백엔드)
            │   (Redis 실패 시 DB 캐시로 폴백)
            │
            ├── RDS Proxy (enable_rds_proxy=true)
            │       └── RDS PostgreSQL
            │
            ├── Secrets Manager (VPC Interface Endpoint)
            │
            └── S3 (VPC Gateway Endpoint)
```

---

## Components and Interfaces

### 1. 프론트엔드 배포: S3 + CloudFront Terraform 모듈

**신규 모듈:** `infra/terraform/modules/frontend_cloudfront/`

| 리소스 | 설명 |
|---|---|
| `aws_s3_bucket` | 프론트엔드 빌드 산출물 저장 버킷 |
| `aws_s3_bucket_public_access_block` | Block Public Access 전체 활성화 |
| `aws_cloudfront_origin_access_control` | S3 OAC (sigv4 서명) |
| `aws_cloudfront_distribution` | SPA 서빙 + WAF 연결 |
| `aws_s3_bucket_policy` | OAC CloudFront Principal만 허용 |

**Terraform 변수:**

```hcl
variable "enable_frontend_cloudfront" {
  description = "S3+CloudFront 프론트엔드 배포 활성화 여부"
  type        = bool
  default     = false
}

variable "frontend_rendering_mode" {
  description = "프론트엔드 렌더링 모드: static | ssr | container"
  type        = string
  default     = "static"
  validation {
    condition     = contains(["static", "ssr", "container"], var.frontend_rendering_mode)
    error_message = "frontend_rendering_mode은 static, ssr, container 중 하나여야 합니다."
  }
}
```

**CloudFront Distribution 핵심 설정:**

```hcl
default_root_object = "index.html"

viewer_certificate {
  cloudfront_default_certificate = true
}

viewer_protocol_policy = "redirect-to-https"

custom_error_response {
  error_code            = 403
  response_code         = 200
  response_page_path    = "/index.html"
}

custom_error_response {
  error_code            = 404
  response_code         = 200
  response_page_path    = "/index.html"
}
```

**Terraform outputs:**

```hcl
output "cloudfront_distribution_arn" { ... }
output "cloudfront_domain_name"       { ... }
output "frontend_s3_bucket_name"      { ... }
```

### SSR 옵션 Architecture Decision Record

| 항목 | Static Export (기본) | SSR (Lambda@Edge) | SSR (Container/Fargate) |
|---|---|---|---|
| 빌드 산출물 | HTML/CSS/JS → S3 | Lambda 함수 zip | Docker 이미지 → ECR |
| Cold Start | 없음 | 있음 (Lambda@Edge) | 없음 (태스크 pre-warm 가능) |
| 비용 | S3 + CloudFront만 | Lambda@Edge 실행 비용 | ECS Fargate 상시 비용 |
| 운영 복잡성 | 낮음 | 중간 | 높음 |
| 권장 | 대부분의 경우 | SEO 필수 + 낮은 트래픽 | 높은 트래픽 + 복잡한 SSR |

SSR 모드 활성화 시 CloudFront는 Static Export와 동일한 WAF WebACL ARN을 재사용한다.
`frontend_rendering_mode = "ssr"`이면 Lambda@Edge 함수를 CloudFront origin-request 이벤트에 연결하고,
`frontend_rendering_mode = "container"`이면 ALB + ECS Fargate를 CloudFront 커스텀 오리진으로 연결한다.

---

### 2. WAF: CloudFront + API Gateway 이중 레이어

**CloudFront WAF (us-east-1 필수):**

```hcl
# infra/terraform/modules/waf_cloudfront/ 신규 모듈
resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1
  scope    = "CLOUDFRONT"

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }
  }

  rule {
    name     = "IPRateLimitCloudFront"
    priority = 30
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
  }
}
```

**API Gateway WAF (ap-northeast-2):**

```hcl
# infra/terraform/modules/waf_apigw/ 신규 모듈 (또는 waf_cloudfront에 scope 파라미터 추가)
resource "aws_wafv2_web_acl" "apigw" {
  scope = "REGIONAL"  # ap-northeast-2

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10
    # ... (CloudFront와 동일)
  }

  rule {
    name     = "IPRateLimitAPIGW"
    priority = 20
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 1000  # CloudFront보다 엄격
        aggregate_key_type = "IP"
      }
    }
  }
}

resource "aws_wafv2_web_acl_association" "apigw" {
  count        = var.enable_waf ? 1 : 0
  resource_arn = module.api_lambda.api_stage_arn
  web_acl_arn  = aws_wafv2_web_acl.apigw.arn
}
```

**WAF 로깅 설정:**

```hcl
resource "aws_wafv2_web_acl_logging_configuration" "cloudfront" {
  log_destination_configs = [aws_cloudwatch_log_group.waf_cloudfront.arn]
  resource_arn            = aws_wafv2_web_acl.cloudfront.arn
}

resource "aws_cloudwatch_log_group" "waf_cloudfront" {
  name              = "aws-waf-logs-${local.name_prefix}-cloudfront"
  retention_in_days = 30
}
```

**신규 Terraform 변수:**

```hcl
variable "enable_waf" {
  description = "WAF WebACL 리소스 생성 활성화 여부"
  type        = bool
  default     = false
}
```

---

### 3. ElastiCache Redis 캐시 레이어

**Terraform 모듈:** `infra/terraform/modules/elasticache/` 신규 생성

```hcl
resource "aws_elasticache_subnet_group" "main" {
  count      = var.enabled ? 1 : 0
  name       = "${var.name_prefix}-redis-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_elasticache_cluster" "main" {
  count                = var.enabled ? 1 : 0
  cluster_id           = "${var.name_prefix}-redis"
  engine               = "redis"
  node_type            = var.node_type          # default: "cache.t4g.micro"
  num_cache_nodes      = 1
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main[0].name
  security_group_ids   = [aws_security_group.redis[0].id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
}
```

**Lambda 보안 그룹 규칙 추가:**

```hcl
resource "aws_security_group_rule" "lambda_redis_egress" {
  count                    = local.managed_networking_enabled && var.enable_elasticache ? 1 : 0
  type                     = "egress"
  security_group_id        = aws_security_group.lambda[0].id
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = module.elasticache.redis_security_group_id
}
```

**신규 Terraform 변수:**

```hcl
variable "enable_elasticache" {
  description = "ElastiCache Redis 클러스터 생성 활성화 여부"
  type        = bool
  default     = false
}

variable "elasticache_node_type" {
  description = "ElastiCache Redis 노드 타입"
  type        = string
  default     = "cache.t4g.micro"
}
```

**api_lambda 모듈 환경 변수 추가:**

```hcl
environment_variables = {
  # ... 기존 변수들
  REDIS_URL     = var.enable_elasticache ? module.elasticache.redis_endpoint_url : ""
  CACHE_BACKEND = var.enable_elasticache ? "redis" : "db"
}
```

---

### 4. ExternalApiCacheService 개선 (DB-based + Redis)

현재 `app/services/external/cache.py`를 다음과 같이 개선한다.

#### 4.1 캐시 백엔드 인터페이스

```python
# app/services/external/cache.py

from __future__ import annotations

import hashlib
import json
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Any, Protocol

from sqlalchemy import text
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)


class CacheBackend(Protocol):
    def get(self, *, provider: str, cache_key: str) -> dict[str, Any] | None: ...
    def set(
        self,
        *,
        provider: str,
        cache_key: str,
        response_payload: dict[str, Any],
        status_code: int | None,
        ttl_seconds: int = 1800,
    ) -> None: ...
```

#### 4.2 Redis 백엔드

```python
class RedisCacheBackend:
    def __init__(self, redis_url: str) -> None:
        import redis as redis_lib
        self._client = redis_lib.from_url(redis_url, decode_responses=True)

    def get(self, *, provider: str, cache_key: str) -> dict[str, Any] | None:
        key = _redis_key(provider, cache_key)
        value = self._client.get(key)
        if value is None:
            return None
        return json.loads(value)

    def set(
        self,
        *,
        provider: str,
        cache_key: str,
        response_payload: dict[str, Any],
        status_code: int | None,
        ttl_seconds: int = 1800,
    ) -> None:
        key = _redis_key(provider, cache_key)
        # TTL 만료를 Redis 네이티브 EXPIRE에 위임 — expires_at 컬럼 기반 Python 만료 검사 제거
        self._client.setex(key, ttl_seconds, json.dumps(response_payload, ensure_ascii=False))
```

#### 4.3 DB 백엔드 개선 (upsert 단일 쿼리)

```python
class DbCacheBackend:
    def __init__(self, session: Session) -> None:
        self.session = session

    def get(self, *, provider: str, cache_key: str) -> dict[str, Any] | None:
        from app.orm import ApiCacheEntry
        from sqlalchemy import select
        entry = self.session.scalars(
            select(ApiCacheEntry).where(
                ApiCacheEntry.provider == provider,
                ApiCacheEntry.cache_key == cache_key,
            )
        ).first()
        if entry is None:
            return None
        # 만료된 항목은 DELETE 없이 None 반환 — 읽기 경로의 쓰기 부하 제거
        if entry.expires_at and _as_utc(entry.expires_at) <= datetime.now(timezone.utc):
            return None
        return dict(entry.response_payload)

    def set(
        self,
        *,
        provider: str,
        cache_key: str,
        response_payload: dict[str, Any],
        status_code: int | None,
        ttl_seconds: int = 1800,
    ) -> None:
        # SELECT + INSERT/UPDATE 2회 쿼리를 단일 upsert로 대체
        # session.commit() 호출 제거 — 호출 측이 트랜잭션 경계를 관리
        expires_at = datetime.now(timezone.utc) + timedelta(seconds=ttl_seconds)
        request_hash = _hash_payload({"provider": provider, "cache_key": cache_key})
        self.session.execute(
            text("""
                INSERT INTO api_cache_entries
                    (provider, cache_key, request_hash, response_payload,
                     status_code, expires_at)
                VALUES
                    (:provider, :cache_key, :request_hash, :response_payload::jsonb,
                     :status_code, :expires_at)
                ON CONFLICT (provider, cache_key)
                DO UPDATE SET
                    request_hash     = EXCLUDED.request_hash,
                    response_payload = EXCLUDED.response_payload,
                    status_code      = EXCLUDED.status_code,
                    expires_at       = EXCLUDED.expires_at
            """),
            {
                "provider": provider,
                "cache_key": cache_key,
                "request_hash": request_hash,
                "response_payload": json.dumps(response_payload, ensure_ascii=False),
                "status_code": status_code,
                "expires_at": expires_at,
            },
        )
```

#### 4.4 ExternalApiCacheService 팩토리 (폴백 로직 포함)

```python
class ExternalApiCacheService:
    """REDIS_URL 설정 시 Redis 백엔드, 실패 시 DB 백엔드로 폴백."""

    def __init__(self, session: Session) -> None:
        self._session = session
        self._backend: CacheBackend = self._resolve_backend()

    def _resolve_backend(self) -> CacheBackend:
        redis_url = os.environ.get("REDIS_URL", "").strip()
        if not redis_url:
            return DbCacheBackend(self._session)
        try:
            backend = RedisCacheBackend(redis_url)
            backend._client.ping()  # 연결 확인
            return backend
        except Exception as exc:
            logger.warning(
                "Redis 연결 실패, DB 캐시 백엔드로 폴백합니다: %s", exc
            )
            return DbCacheBackend(self._session)

    def get(self, *, provider: str, cache_key: str) -> dict[str, Any] | None:
        return self._backend.get(provider=provider, cache_key=cache_key)

    def set(
        self,
        *,
        provider: str,
        cache_key: str,
        response_payload: dict[str, Any],
        status_code: int | None,
        ttl_seconds: int = 1800,
    ) -> None:
        self._backend.set(
            provider=provider,
            cache_key=cache_key,
            response_payload=response_payload,
            status_code=status_code,
            ttl_seconds=ttl_seconds,
        )


def _redis_key(provider: str, cache_key: str) -> str:
    return f"cache:{provider}:{cache_key}"


def _hash_payload(payload: dict[str, Any]) -> str:
    encoded = json.dumps(payload, sort_keys=True, ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
```

**api_cache_entries 테이블 제약 조건:**
`(provider, cache_key)` 컬럼에 UNIQUE 제약 조건이 없는 경우 마이그레이션 추가:

```sql
ALTER TABLE api_cache_entries
    ADD CONSTRAINT uq_api_cache_entries_provider_cache_key
    UNIQUE (provider, cache_key);
```

---

### 5. DB 쿼리 최적화

#### 5.1 CandidateService._candidate_evidence_summaries() — GROUP BY 집계

현재 구현: 전체 `(EvidenceChunk, SourceDocument)` 행을 Python으로 로드 후 루프 집계.
개선 구현: DB 레벨 `GROUP BY` 집계 단일 쿼리.

```python
def _candidate_evidence_summaries(
    self,
    tickers: list[str],
) -> dict[str, CandidateEvidenceSummaryContract]:
    if not tickers:
        return {}
    rows = self.session.execute(
        select(
            EvidenceChunk.ticker,
            SourceDocument.source_type,
            func.count(EvidenceChunk.id).label("cnt"),
            func.max(
                func.coalesce(EvidenceChunk.published_at, SourceDocument.published_at)
            ).label("latest_at"),
        )
        .join(SourceDocument, SourceDocument.id == EvidenceChunk.source_document_id)
        .where(
            EvidenceChunk.ticker.in_(tickers),
            SourceDocument.source_type.in_(["news", "disclosure"]),
        )
        .group_by(EvidenceChunk.ticker, SourceDocument.source_type)
    ).all()

    summaries: dict[str, dict[str, object]] = {
        ticker: {"news": 0, "disclosure": 0, "latest": None}
        for ticker in tickers
    }
    for ticker, source_type, cnt, latest_at in rows:
        summary = summaries.setdefault(
            ticker, {"news": 0, "disclosure": 0, "latest": None}
        )
        if source_type == "news":
            summary["news"] = int(cnt)
        elif source_type == "disclosure":
            summary["disclosure"] = int(cnt)
        current_latest = summary["latest"]
        if latest_at is not None and (current_latest is None or latest_at > current_latest):
            summary["latest"] = latest_at

    return {
        ticker: CandidateEvidenceSummaryContract(
            news_count=int(summary["news"]),
            disclosure_count=int(summary["disclosure"]),
            latest_at=summary["latest"],
        )
        for ticker, summary in summaries.items()
    }
```

**성능 영향:** N개 종목 요청 시 전체 행 로드(O(N*M)) → 집계 결과만 반환(O(N)).

#### 5.2 CandidateService._latest_price_contracts() — DISTINCT ON

현재 구현: 모든 `PriceMetric` 행 로드 후 Python에서 ticker당 첫 번째 행만 사용.
개선 구현: `DISTINCT ON (ticker)` 단일 쿼리.

```python
def _latest_price_contracts(self, tickers: list[str]) -> dict[str, StockPriceContract]:
    if not tickers:
        return {}
    from sqlalchemy.dialects.postgresql import dialect as pg_dialect
    # SQLAlchemy로 DISTINCT ON 표현: text() 사용 또는 PostgreSQL 전용 컴파일
    rows = self.session.scalars(
        select(PriceMetric)
        .where(PriceMetric.ticker.in_(tickers))
        .distinct(PriceMetric.ticker)              # DISTINCT ON (ticker)
        .order_by(PriceMetric.ticker.asc(), PriceMetric.trade_date.desc())
    ).all()
    return {
        row.ticker: StockPriceContract(
            close=_optional_float(row.close_price),
            change_rate=_optional_float(row.change_rate),
            volume=_optional_float(row.volume),
            trade_date=row.trade_date,
        )
        for row in rows
    }
```

**필요 인덱스 마이그레이션:**

```sql
-- DISTINCT ON 쿼리 플랜이 인덱스 스캔을 활용할 수 있도록
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_price_metrics_ticker_trade_date_desc
    ON price_metrics (ticker ASC, trade_date DESC);
```

#### 5.3 StockService.search() — COUNT 쿼리 서브쿼리 재사용

현재 구현: WHERE 조건을 두 번 평가(COUNT 쿼리 + 데이터 쿼리).
개선 구현: 동일 서브쿼리를 공유하는 방식은 현재 코드와 동일한 패턴 유지.
추가 개선: 빈 q + 필터 없는 경우 `lru_cache` 기반 전체 COUNT 캐싱.

```python
from functools import lru_cache

@lru_cache(maxsize=1)
def _total_stock_count(session_factory) -> int:
    """필터 없는 전체 Stock 수 캐싱 (Lambda warm 인스턴스 재사용)."""
    session = session_factory()
    try:
        return session.scalar(select(func.count()).select_from(Stock)) or 0
    finally:
        session.close()
```

**복합 인덱스 마이그레이션:**

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stocks_ticker_company_name
    ON stocks (ticker, company_name);
```

---

### 6. Lambda Cold Start 최적화

#### 6.1 lru_cache 싱글턴 (현재 유지)

`app/db.py`의 `get_engine()`, `get_session_factory()`, `resolve_database_url()`은 이미
`@lru_cache`로 감싸져 있다. Lambda warm 인스턴스에서 모듈 수준 초기화 비용을 제거한다.

`app/config.py`의 `get_settings()`도 동일하게 `@lru_cache` 적용 완료.

#### 6.2 RDS Proxy (enable_rds_proxy=true)

현재 `infra/terraform/modules/rds_proxy/` 모듈이 존재한다.
`enable_rds_proxy = true`로 설정 시 `module.api_lambda`의 `database_host`가
RDS 직접 엔드포인트 대신 RDS Proxy 엔드포인트를 사용한다.

```hcl
# main.tf (기존 코드, 이미 구현됨)
database_host = var.enable_rds_proxy ? module.rds_proxy.proxy_endpoint : module.rds.db_endpoint
```

**RDS Proxy 활성화 권장 조건:**
- Lambda 최대 동시 실행 수 ≥ 20
- RDS 인스턴스 최대 연결 수의 80% 이상 사용 시
- `db.t4g.micro`의 경우 max_connections ≈ 90 → Lambda 동시 실행 15개 이상 시 Proxy 권장

**Lambda 권장 DB 풀 설정 (RDS Proxy 활성화 시):**

```hcl
# Terraform 변수 권장 값 문서화
# enable_rds_proxy = true 시:
#   DATABASE_POOL_SIZE    = 2   (Proxy가 풀링하므로 Lambda당 소수 연결)
#   DATABASE_MAX_OVERFLOW = 0   (Proxy 연결 한도 초과 방지)
# enable_rds_proxy = false 시:
#   DATABASE_POOL_SIZE    = 5
#   DATABASE_MAX_OVERFLOW = 10
```

#### 6.3 Provisioned Concurrency (선택적)

```hcl
variable "enable_provisioned_concurrency" {
  description = "Lambda Provisioned Concurrency 활성화 여부"
  type        = bool
  default     = false
}

variable "provisioned_concurrency_count" {
  description = "Provisioned Concurrency 수. Cold Start 제거가 필요한 경우에만 활성화."
  type        = number
  default     = 2
}
```

Lambda 모듈에서 `aws_lambda_provisioned_concurrency_config` 리소스를 조건부 생성.

#### 6.4 Secrets Manager 타임아웃 처리

`app/services/external/aws_secrets.py`에서 타임아웃 예외 처리:

```python
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

def load_secret_json(secret_arn: str) -> dict:
    try:
        # ... 기존 Secrets Manager 호출
    except Exception as exc:
        logger.error("Secrets Manager 호출 실패 (arn=%s): %s", secret_arn, exc)
        raise  # 503으로 변환은 FastAPI exception handler에서 처리
```

---

### 7. CloudWatch 경보 확장

기존 `infra/terraform/alarms.tf`에 다음 경보를 추가한다.

```hcl
# CloudFront 5xx 오류율 경보
resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx" {
  count = var.enable_operational_alarms && var.enable_frontend_cloudfront ? 1 : 0

  alarm_name          = "${local.name_prefix}-cloudfront-5xx-rate"
  alarm_description   = "CloudFront 5xx 오류율이 5%를 초과합니다."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.operational_alarm_actions

  metric_query {
    id = "error_rate"
    expression  = "IF(total > 0, errors5xx * 100 / total, 0)"
    return_data = true
  }
  metric_query {
    id = "errors5xx"
    metric {
      namespace   = "AWS/CloudFront"
      metric_name = "5xxErrorRate"
      period      = 60
      stat        = "Average"
      dimensions  = { DistributionId = module.frontend_cloudfront[0].distribution_id }
    }
  }
  # ... total 메트릭 쿼리
}

# WAF 차단 수 경보
resource "aws_cloudwatch_metric_alarm" "waf_blocked_requests" {
  count = var.enable_operational_alarms && var.enable_waf ? 1 : 0

  alarm_name          = "${local.name_prefix}-waf-blocked-requests"
  alarm_description   = "WAF에서 1분 동안 차단 건수가 100회를 초과합니다."
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  period              = 60
  statistic           = "Sum"
  threshold           = 100
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.operational_alarm_actions
}

# ElastiCache 메모리 사용률 경보
resource "aws_cloudwatch_metric_alarm" "elasticache_memory_high" {
  count = var.enable_operational_alarms && var.enable_elasticache ? 1 : 0

  alarm_name          = "${local.name_prefix}-elasticache-memory-high"
  alarm_description   = "ElastiCache Redis 메모리 사용률이 80%를 초과합니다."
  namespace           = "AWS/ElastiCache"
  metric_name         = "DatabaseMemoryUsagePercentage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.operational_alarm_actions

  dimensions = {
    CacheClusterId = module.elasticache[0].cluster_id
  }
}
```

---

### 8. VPC 엔드포인트 및 네트워크 보완

현재 `infra/terraform/main.tf`에 Secrets Manager Interface VPC Endpoint와
S3 Gateway VPC Endpoint가 이미 구현되어 있다.

**현재 구현 확인:**
- `aws_vpc_endpoint.secretsmanager`: Interface 타입, `lambda_subnet_ids`에 배치, `private_dns_enabled = true` ✓
- `aws_vpc_endpoint.s3`: Gateway 타입, `s3_gateway_endpoint_enabled` 조건부 생성 ✓
- `aws_security_group_rule.secretsmanager_endpoint_from_lambda`: HTTPS(443) inbound from Lambda ✓

**추가 보완 사항:**

```hcl
# Terraform outputs 추가 (infra/terraform/outputs.tf)
output "secretsmanager_vpc_endpoint_id" {
  description = "Secrets Manager VPC Interface Endpoint ID (네트워크 감사용)"
  value       = try(aws_vpc_endpoint.secretsmanager[0].id, "")
}

output "s3_vpc_endpoint_id" {
  description = "S3 VPC Gateway Endpoint ID (네트워크 감사용)"
  value       = try(aws_vpc_endpoint.s3[0].id, "")
}

output "lambda_security_group_id" {
  description = "Lambda 보안 그룹 ID (네트워크 감사용)"
  value       = try(aws_security_group.lambda[0].id, "")
}
```

**Lambda 보안 그룹 이그레스 정책:**
현재 `aws_security_group_rule.lambda_https_egress`는 `0.0.0.0/0`으로 설정되어 있다.
VPC 엔드포인트 활성화 후 Secrets Manager 트래픽은 엔드포인트를 통해 라우팅되므로
추가 이그레스 규칙 없이도 VPC 내에서 처리된다.
RDS 이그레스는 `aws_security_group_rule.lambda_database_egress`로 별도 관리된다.

---

## Data Models

### ExternalApiCacheService 캐시 백엔드 선택 흐름

```
Settings.redis_url (REDIS_URL 환경 변수)
    │
    ├── 비어 있음 → DbCacheBackend
    │
    └── 설정됨 → RedisCacheBackend.ping() 시도
                    │
                    ├── 성공 → RedisCacheBackend
                    │
                    └── 실패 → WARNING 로그 → DbCacheBackend
```

### api_cache_entries 테이블 스키마 (UNIQUE 제약 필요)

```sql
CREATE TABLE api_cache_entries (
    id               BIGSERIAL PRIMARY KEY,
    provider         TEXT NOT NULL,
    cache_key        TEXT NOT NULL,
    request_hash     TEXT NOT NULL,
    response_payload JSONB NOT NULL,
    status_code      INTEGER,
    expires_at       TIMESTAMPTZ,
    created_at       TIMESTAMPTZ DEFAULT NOW(),
    updated_at       TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_api_cache_entries_provider_cache_key UNIQUE (provider, cache_key)
);
```

---

## Error Handling

### Redis 연결 실패 폴백

```python
# ExternalApiCacheService._resolve_backend()
try:
    backend = RedisCacheBackend(redis_url)
    backend._client.ping()
    return backend
except Exception as exc:
    logger.warning("Redis 연결 실패, DB 캐시 백엔드로 폴백합니다: %s", exc)
    return DbCacheBackend(self._session)
```

개별 Redis 작업 실패 시에도 WARNING 로그를 남기고 조용히 실패한다 (캐시 레이어 실패가
서비스 중단으로 이어지지 않도록).

### Secrets Manager 타임아웃

Lambda 초기화 중 Secrets Manager 호출이 타임아웃될 경우 예외가 전파되어
FastAPI의 글로벌 예외 핸들러가 503 응답을 반환한다. 오류는 CloudWatch Logs에 기록된다.

### DB Cache upsert 충돌

`ON CONFLICT DO UPDATE` 패턴으로 동시 Lambda 인스턴스가 동일 키에 대해 경쟁 시
마지막 writer가 이기는 방식으로 처리된다. 캐시 특성상 일관성보다 가용성을 우선한다.

### WAF 차단 응답

WAF가 요청을 차단할 경우 AWS WAF가 자동으로 403 응답을 반환한다.
차단 이벤트는 CloudWatch Logs WAF 로그 그룹에 기록된다.

---

### 8. GitHub Actions CI/CD 프론트엔드 배포 워크플로우 (신규)

`.github/workflows/frontend-deploy.yml` (신규 파일):

```yaml
- name: Build Next.js static export
  run: npm run build
  working-directory: frontend

- name: Upload to S3
  run: |
    aws s3 sync frontend/out/ s3://${{ steps.tf-outputs.outputs.frontend_s3_bucket_name }}/ \
      --delete --cache-control "public, max-age=31536000, immutable"

- name: CloudFront cache invalidation
  run: |
    aws cloudfront create-invalidation \
      --distribution-id ${{ steps.tf-outputs.outputs.cloudfront_distribution_id }} \
      --paths "/*"
```

`s3 sync` 완료 후 반드시 `cloudfront create-invalidation`을 실행하여 엣지 캐시를 무효화한다.

### Config.py 신규 설정 항목

```python
class Settings(BaseSettings):
    # ... 기존 설정
    redis_url: str = Field(default="", validation_alias="REDIS_URL")
    cache_backend: str = Field(default="db", validation_alias="CACHE_BACKEND")
    provisioned_concurrency_enabled: bool = Field(
        default=False, validation_alias="PROVISIONED_CONCURRENCY_ENABLED"
    )
```

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions
of a system — essentially, a formal statement about what the system should do. Properties
serve as the bridge between human-readable specifications and machine-verifiable correctness
guarantees.*

### Property 1: 캐시 백엔드 라우팅 정확성

*For any* `ExternalApiCacheService` 인스턴스에서, `REDIS_URL` 환경 변수가 유효한 Redis
URL로 설정되고 연결이 성공하면 반드시 Redis 백엔드를 사용하고, 환경 변수가 비어 있거나
Redis 연결이 실패하면 반드시 DB 백엔드를 사용해야 한다.

**Validates: Requirements 5.4, 5.5, 5.7**

### Property 2: DB 캐시 upsert 멱등성

*For any* `(provider, cache_key)` 쌍과 임의의 `response_payload`에 대해, `DbCacheBackend.set()`을
동일한 키로 두 번 호출한 후 `get()`을 호출하면 반드시 두 번째 `set()`의 `response_payload`를
반환해야 한다 (덮어쓰기 보장).

**Validates: Requirements 6.1**

### Property 3: 만료된 캐시 항목은 None 반환

*For any* `DbCacheBackend` 인스턴스에서, 이미 만료된 `expires_at`을 가진 캐시 항목에 대해
`get()`을 호출하면 반드시 `None`을 반환해야 하며, DELETE 쿼리를 실행하지 않아야 한다.

**Validates: Requirements 6.3**

### Property 4: EvidenceChunk GROUP BY 집계 정확성

*For any* ticker 집합과 해당 `EvidenceChunk`/`SourceDocument` 데이터에 대해,
개선된 `_candidate_evidence_summaries()`의 GROUP BY 집계 결과는 이전 Python 루프 집계
결과와 동일한 `news_count`, `disclosure_count`, `latest_at` 값을 반환해야 한다.

**Validates: Requirements 7.1, 7.2, 7.3**

### Property 5: DISTINCT ON 쿼리 — ticker당 최신 가격 1건

*For any* ticker 목록에 대해, `_latest_price_contracts()`는 각 ticker당 정확히 1개의
`StockPriceContract`를 반환해야 하며, 해당 가격의 `trade_date`는 그 ticker의 모든
`PriceMetric` 행 중 최신 날짜여야 한다.

**Validates: Requirements 9.1, 9.2**

### Property 6: lru_cache 싱글턴 동일성

*For any* Lambda warm 인스턴스에서, `get_engine()` 또는 `get_session_factory()`를 여러 번
호출하면 반드시 동일한 Python 객체(`is` 비교)를 반환해야 한다.

**Validates: Requirements 10.1**

---

## Testing Strategy

### 단위 테스트 (example-based)

- `DbCacheBackend.set()` 호출 후 `session.commit()`이 호출되지 않음을 mock으로 확인
- `RedisCacheBackend.set()` 호출 시 올바른 TTL로 `SETEX` 명령이 실행되는지 확인
- Secrets Manager 타임아웃 mock 시 503 응답 반환 확인
- `StockService.search(q="", market=None)` 반복 호출 시 COUNT 캐시 동작 확인

### 통합 테스트 (infrastructure)

- 파일 업로드 후 CloudFront URL 접근 확인 (1-2 예시)
- WAF 차단 요청 후 CloudWatch Logs 이벤트 확인 (1-2 예시)
- GitHub Actions 워크플로우 S3 sync → CloudFront invalidation 순서 확인

### 스모크 테스트 (infrastructure configuration)

- Terraform plan 결과에서 S3 버킷, CloudFront 배포 리소스 존재 확인
- WAF WebACL 규칙 그룹 구성 확인 (us-east-1 CloudFront용, ap-northeast-2 API GW용)
- ElastiCache 암호화 설정, Lambda 보안 그룹 6379 포트 확인
- CloudWatch 경보 임계값 설정 확인 (CloudFront 5xx, WAF 차단, ElastiCache 메모리)
- VPC 엔드포인트 존재 및 Terraform output 확인

### 속성 기반 테스트 (property-based)

각 Property는 `pytest` + `hypothesis` 라이브러리로 구현한다.
최소 100회 이상 반복 실행하여 경계 조건을 탐색한다.

**Property 2 (upsert 멱등성) 테스트 예시:**

```python
from hypothesis import given, settings
from hypothesis import strategies as st

@given(
    provider=st.text(min_size=1, max_size=50),
    cache_key=st.text(min_size=1, max_size=100),
    payload_v1=st.dictionaries(st.text(), st.text()),
    payload_v2=st.dictionaries(st.text(), st.text()),
)
@settings(max_examples=100)
def test_db_cache_upsert_overwrites(provider, cache_key, payload_v1, payload_v2):
    """
    Feature: aws-deployment-architecture-improvement,
    Property 2: DB 캐시 upsert 멱등성
    """
    # DB 백엔드 mock 세션으로 set() 두 번 호출 후 두 번째 값 반환 확인
    ...
```
