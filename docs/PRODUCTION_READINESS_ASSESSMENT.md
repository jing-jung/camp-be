# 🏭 프로덕션 준비도 평가 및 개선 로드맵

## 📊 현재 상태 평가

### 등급: **C+ (개발/테스트 환경 적합, 프로덕션 부족)**

| 영역 | 현재 점수 | 목표 점수 | 우선순위 |
|------|----------|----------|---------|
| 🔐 보안 | 4/10 | 9/10 | 🔴 HIGH |
| 📈 스케일링 | 6/10 | 9/10 | 🟡 MEDIUM |
| 👁️ 옵저버빌리티 | 3/10 | 9/10 | 🔴 HIGH |
| 🛡️ 가용성 | 4/10 | 9/10 | 🟡 MEDIUM |
| ⚡ 성능 | 5/10 | 9/10 | 🟡 MEDIUM |
| 🔄 DevOps | 3/10 | 8/10 | 🟢 LOW |

---

## 🔴 크리티컬 이슈 (즉시 해결 필요)

### 1. 보안 취약점

#### 1.1 Lambda Function URL이 인증 없이 Public
**현재 문제:**
```terraform
# frontend_lambda/main.tf
resource "aws_lambda_function_url" "frontend" {
  authorization_type = "NONE"  # ⚠️ 위험!
}
```

**위험도:**
- DDoS 공격에 노출
- 비용 폭탄 가능성
- 악의적인 요청 차단 불가

**해결 방안:**
```terraform
# Option 1: WAF 추가
resource "aws_wafv2_web_acl" "frontend" {
  name  = "${var.name_prefix}-frontend-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rate Limiting
  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000  # 5분당 2000 요청
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # SQL Injection 방어
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # 지리적 차단 (필요시)
  rule {
    name     = "GeoBlockRule"
    priority = 3

    action {
      block {}
    }

    statement {
      not_statement {
        statement {
          geo_match_statement {
            country_codes = ["KR", "US"]  # 한국/미국만 허용
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "GeoBlockRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "frontend-waf"
    sampled_requests_enabled   = true
  }
}

# CloudFront에 WAF 연결
resource "aws_cloudfront_distribution" "frontend" {
  # ... 기존 설정 ...
  
  web_acl_id = aws_wafv2_web_acl.frontend.arn
}
```

**예상 비용:**
- WAF: $5/월 (기본) + $1/100만 요청
- 월 100만 요청: 약 $6/월 추가

#### 1.2 API Gateway에 Rate Limiting 없음
**해결 방안:**
```terraform
# api_lambda/main.tf
resource "aws_apigatewayv2_stage" "api" {
  # ... 기존 설정 ...
  
  throttle_settings {
    burst_limit = 5000   # 동시 요청 제한
    rate_limit  = 10000  # 초당 요청 제한
  }
}

# 사용량 플랜 추가 (더 세밀한 제어)
resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.name_prefix}-usage-plan"

  api_stages {
    api_id = aws_apigatewayv2_api.main.id
    stage  = aws_apigatewayv2_stage.api.name

    throttle {
      path        = "/*"
      burst_limit = 1000
      rate_limit  = 500
    }

    throttle {
      path        = "/chat"  # AI 엔드포인트는 더 제한적으로
      burst_limit = 100
      rate_limit  = 50
    }
  }

  quota_settings {
    limit  = 1000000  # 월간 100만 요청
    period = "MONTH"
  }

  throttle_settings {
    burst_limit = 5000
    rate_limit  = 2000
  }
}
```

#### 1.3 민감 정보 보호 강화
**현재 문제:**
- 환경변수에 민감 정보 노출 가능
- Secrets Manager 사용하지만 로테이션 없음

**해결 방안:**
```terraform
# Secrets Manager 자동 로테이션
resource "aws_secretsmanager_secret_rotation" "database" {
  secret_id           = module.secrets.database_secret_arn
  rotation_lambda_arn = aws_lambda_function.rotate_secret.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

# Lambda에서 Secrets 주입 (환경변수 대신)
resource "aws_lambda_function" "api" {
  # environment 블록에서 민감정보 제거
  
  # Lambda Extension으로 Secrets 주입
  layers = [
    "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:layer:AWS-Parameters-and-Secrets-Lambda-Extension:4"
  ]
}
```

---

### 2. 데이터베이스 스케일링 한계

#### 2.1 단일 RDS 인스턴스 (SPOF)
**현재 문제:**
- 읽기/쓰기가 하나의 인스턴스에 집중
- 트래픽 증가 시 병목 발생
- 장애 시 전체 서비스 다운

**해결 방안 A: Aurora Serverless v2 (권장)**
```terraform
# modules/aurora_serverless/main.tf
resource "aws_rds_cluster" "main" {
  cluster_identifier = "${var.name_prefix}-aurora-cluster"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "15.4"
  
  database_name   = var.db_name
  master_username = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)["username"]
  master_password = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)["password"]
  
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = var.security_group_ids
  
  # Serverless v2 스케일링
  serverlessv2_scaling_configuration {
    min_capacity = 0.5  # 최소 0.5 ACU (약 1GB RAM)
    max_capacity = 4.0  # 최대 4 ACU (약 8GB RAM)
  }
  
  # 자동 백업
  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"
  
  # 고가용성
  enabled_cloudwatch_logs_exports = ["postgresql"]
  
  # 암호화
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn
  
  deletion_protection = true
  
  tags = {
    Name = "${var.name_prefix}-aurora-cluster"
  }
}

# Writer 인스턴스
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.name_prefix}-aurora-writer"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version
}

# Reader 인스턴스 (읽기 전용 복제본)
resource "aws_rds_cluster_instance" "reader" {
  count = var.reader_count  # 기본 1개, 트래픽 많으면 2-3개
  
  identifier         = "${var.name_prefix}-aurora-reader-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version
}

# Reader 엔드포인트 출력
output "reader_endpoint" {
  value = aws_rds_cluster.main.reader_endpoint
}
```

**비용 비교:**
| 옵션 | 최소 비용 | 최대 비용 | 특징 |
|------|----------|----------|------|
| RDS t4g.micro | $12.50/월 | $12.50/월 | 고정, 스케일링 불가 |
| Aurora Serverless v2 | $43.80/월 (0.5 ACU) | $350/월 (4 ACU) | 자동 스케일링, 고가용성 |

**해결 방안 B: RDS Proxy + Read Replicas**
```terraform
# 현재 RDS 유지하면서 개선
resource "aws_db_instance" "replica" {
  count = 2  # 읽기 전용 복제본 2개
  
  identifier             = "${var.name_prefix}-rds-read-${count.index + 1}"
  replicate_source_db    = aws_db_instance.main.identifier
  instance_class         = var.db_instance_class
  publicly_accessible    = false
  vpc_security_group_ids = var.security_group_ids
  
  # 모니터링
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn
}

# 애플리케이션 코드에서 읽기/쓰기 분리
# app/db.py
WRITE_DB_URL = os.getenv("DATABASE_URL")  # Writer
READ_DB_URL = os.getenv("DATABASE_READ_URL")  # Reader

async def get_db():
    # 읽기 작업
    if is_read_only_query():
        engine = create_async_engine(READ_DB_URL)
    else:
        engine = create_async_engine(WRITE_DB_URL)
```

#### 2.2 Connection Pool 부족
**해결 방안:**
```terraform
# RDS Proxy 활성화
variable "enable_rds_proxy" {
  default = true  # false → true로 변경
}

# RDS Proxy 설정 최적화
resource "aws_db_proxy" "main" {
  # ... 기존 설정 ...
  
  # Connection Pool 설정
  engine_family = "POSTGRESQL"
  
  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = var.secret_arn
  }
  
  # 타임아웃 설정
  idle_client_timeout    = 1800  # 30분
  max_connections_percent = 100
  max_idle_connections_percent = 50
  
  require_tls = true
}
```

---

### 3. 캐싱 레이어 없음

#### 3.1 Redis/ElastiCache 추가
**왜 필요한가?**
- 데이터베이스 부하 70% 감소
- API 응답 속도 10배 향상
- 동시 접속자 처리 능력 증가

**구현:**
```terraform
# modules/elasticache/main.tf
resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "${var.name_prefix}-redis"
  replication_group_description = "Redis cluster for ${var.name_prefix}"
  
  engine               = "redis"
  engine_version       = "7.0"
  port                 = 6379
  parameter_group_name = "default.redis7"
  node_type            = "cache.t4g.micro"  # 시작은 작게
  
  # 고가용성
  num_cache_clusters         = 2  # Primary + Replica
  automatic_failover_enabled = true
  multi_az_enabled          = true
  
  # 네트워크
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]
  
  # 백업
  snapshot_retention_limit = 5
  snapshot_window         = "03:00-05:00"
  
  # 유지보수
  maintenance_window = "sun:05:00-sun:07:00"
  
  # 암호화
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                = random_password.redis.result
  
  tags = {
    Name = "${var.name_prefix}-redis"
  }
}

# Lambda에서 Redis 연결
resource "aws_lambda_function" "api" {
  environment {
    variables = {
      REDIS_ENDPOINT = aws_elasticache_replication_group.main.primary_endpoint_address
      REDIS_PORT     = "6379"
      REDIS_AUTH     = data.aws_secretsmanager_secret_version.redis.secret_string
    }
  }
  
  # VPC 설정 (Redis는 VPC 내부에만 존재)
  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = var.lambda_security_group_ids
  }
}
```

**애플리케이션 코드:**
```python
# app/services/external/cache.py
import redis.asyncio as redis
import json
from functools import wraps

redis_client = redis.from_url(
    f"redis://{os.getenv('REDIS_ENDPOINT')}:{os.getenv('REDIS_PORT')}",
    password=os.getenv('REDIS_AUTH'),
    decode_responses=True
)

def cache_result(ttl: int = 300):  # 5분 캐시
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            cache_key = f"{func.__name__}:{args}:{kwargs}"
            
            # 캐시 확인
            cached = await redis_client.get(cache_key)
            if cached:
                return json.loads(cached)
            
            # 캐시 미스 - 실제 함수 실행
            result = await func(*args, **kwargs)
            
            # 결과 캐시
            await redis_client.setex(
                cache_key, 
                ttl, 
                json.dumps(result, default=str)
            )
            
            return result
        return wrapper
    return decorator

# 사용 예시
@cache_result(ttl=600)  # 10분 캐시
async def get_stock_candidates(limit: int = 10):
    # DB 쿼리 (캐시 미스 시에만 실행)
    return await db.query(...)
```

**비용:**
- cache.t4g.micro (2 노드): 약 $24/월
- 데이터베이스 부하 70% 감소로 RDS 비용 절감 가능

---

## 👁️ 옵저버빌리티 강화

### 현재 문제:
- CloudWatch Logs만 있음 → 문제 발생 시 원인 파악 어려움
- 구조화된 로깅 부족
- 분산 추적 없음
- 실시간 대시보드 없음

### 해결 방안:

#### 1. AWS X-Ray 분산 추적
```terraform
# Lambda X-Ray 활성화
resource "aws_lambda_function" "api" {
  # ... 기존 설정 ...
  
  tracing_config {
    mode = "Active"  # X-Ray 추적 활성화
  }
}

# API Gateway X-Ray
resource "aws_apigatewayv2_stage" "api" {
  # ... 기존 설정 ...
  
  default_route_settings {
    # ... 기존 설정 ...
    
    throttling_burst_limit = 5000
    throttling_rate_limit  = 10000
  }
  
  # X-Ray 추적
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }
}
```

**애플리케이션 코드:**
```python
# app/main.py
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.ext.fastapi.middleware import XRayMiddleware

app = FastAPI()

# X-Ray 미들웨어 추가
app.add_middleware(XRayMiddleware, recorder=xray_recorder)

# 함수별 추적
@xray_recorder.capture('get_recommendations')
async def get_recommendations(limit: int = 10):
    # 세그먼트 생성
    subsegment = xray_recorder.begin_subsegment('database_query')
    try:
        result = await db.query(...)
        subsegment.put_metadata('query_result_count', len(result))
        return result
    finally:
        xray_recorder.end_subsegment()
```

#### 2. 구조화된 로깅 (Structured Logging)
```python
# app/services/external/logger.py
import structlog
import json

# 구조화된 로거 설정
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.JSONRenderer()
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# 사용 예시
@app.get("/recommendations/candidates")
async def get_candidates(limit: int = 10):
    logger.info(
        "recommendations_requested",
        limit=limit,
        user_id=current_user.id,
        request_id=request.headers.get("x-request-id")
    )
    
    try:
        results = await get_recommendations(limit)
        
        logger.info(
            "recommendations_success",
            result_count=len(results),
            duration_ms=elapsed_time,
            cache_hit=was_cached
        )
        
        return results
    except Exception as e:
        logger.error(
            "recommendations_failed",
            error=str(e),
            error_type=type(e).__name__,
            stack_trace=traceback.format_exc()
        )
        raise
```

#### 3. CloudWatch 대시보드
```terraform
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-main-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # API 요청 수
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", { stat = "Sum", label = "Total Requests" }],
            [".", "4XXError", { stat = "Sum", label = "Client Errors" }],
            [".", "5XXError", { stat = "Sum", label = "Server Errors" }]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "API Gateway Requests"
        }
      },
      
      # Lambda 성능
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", { stat = "Average", label = "Avg Duration" }],
            [".", "Duration", { stat = "Maximum", label = "Max Duration" }],
            [".", "ConcurrentExecutions", { stat = "Maximum", label = "Concurrent" }]
          ]
          period = 300
          region = var.aws_region
          title  = "Lambda Performance"
        }
      },
      
      # RDS 성능
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", { stat = "Average" }],
            [".", "DatabaseConnections", { stat = "Average" }],
            [".", "ReadLatency", { stat = "Average" }],
            [".", "WriteLatency", { stat = "Average" }]
          ]
          period = 300
          region = var.aws_region
          title  = "RDS Performance"
        }
      },
      
      # 비용 추정
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", {
              stat = "Maximum",
              label = "Estimated Charges"
            }]
          ]
          period = 86400  # 1일
          region = "us-east-1"  # Billing은 us-east-1만 지원
          title  = "Estimated Cost"
        }
      }
    ]
  })
}
```

#### 4. 알람 강화
```terraform
# CPU 알람
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.name_prefix}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "RDS CPU exceeds 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

# Lambda 에러율 알람
resource "aws_cloudwatch_metric_alarm" "lambda_errors_high" {
  alarm_name          = "${var.name_prefix}-lambda-errors-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Lambda errors exceed 10 per minute"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    FunctionName = aws_lambda_function.api.function_name
  }
}

# API Gateway 5xx 알람
resource "aws_cloudwatch_metric_alarm" "api_5xx_high" {
  alarm_name          = "${var.name_prefix}-api-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "API Gateway 5xx errors exceed 5 per minute"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

# SNS 토픽 (이메일 알림)
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email  # 실제 이메일 주소
}

# Slack 통합 (선택사항)
resource "aws_sns_topic_subscription" "slack" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}
```

---

## 🛡️ 고가용성 (High Availability)

### Multi-AZ 배포
```terraform
# RDS Multi-AZ
resource "aws_db_instance" "main" {
  # ... 기존 설정 ...
  
  multi_az = true  # false → true
  
  # 자동 백업
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # 자동 minor 버전 업그레이드
  auto_minor_version_upgrade = true
  
  # 삭제 방지
  deletion_protection = true
  
  # 스냅샷
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
}

# Lambda Reserved Concurrency (Cold Start 방지)
resource "aws_lambda_function" "api" {
  # ... 기존 설정 ...
  
  # 예약 동시성 (항상 워밍된 인스턴스 유지)
  reserved_concurrent_executions = 10  # 10개 인스턴스 항상 대기
}

# 또는 Provisioned Concurrency
resource "aws_lambda_provisioned_concurrency_config" "api" {
  function_name                     = aws_lambda_function.api.function_name
  provisioned_concurrent_executions = 5  # 5개 인스턴스 항상 실행
  qualifier                         = aws_lambda_alias.live.name
}
```

**비용:**
- Multi-AZ RDS: 기존 비용의 2배 (약 $25/월)
- Provisioned Concurrency: $0.015/GB-hour + 실행 비용
  - 512MB, 24시간: 약 $5.4/월

---

## ⚡ 성능 최적화

### 1. CloudFront 캐싱 전략
```terraform
resource "aws_cloudfront_distribution" "frontend" {
  # ... 기존 설정 ...
  
  # 정적 자산 캐싱
  ordered_cache_behavior {
    path_pattern     = "/_next/static/*"
    target_origin_id = "lambda-function-url"
    
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    
    min_ttl     = 31536000  # 1년
    default_ttl = 31536000
    max_ttl     = 31536000
    
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }
  
  # API 요청은 캐싱하지 않음
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    target_origin_id = "lambda-function-url"
    
    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]
    
    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
      headers = ["Authorization", "Accept", "Content-Type"]
    }
    
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
    
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }
}
```

### 2. Lambda 성능 최적화
```python
# app/main.py
from mangum import Mangum
import asyncio

app = FastAPI()

# Connection Pool 재사용 (Lambda 인스턴스 간 유지)
_db_engine = None
_redis_client = None

async def get_db_engine():
    global _db_engine
    if _db_engine is None:
        _db_engine = create_async_engine(
            DATABASE_URL,
            pool_size=5,
            max_overflow=10,
            pool_pre_ping=True,  # 연결 유효성 검사
            pool_recycle=3600    # 1시간마다 재연결
        )
    return _db_engine

async def get_redis():
    global _redis_client
    if _redis_client is None:
        _redis_client = await redis.from_url(REDIS_URL)
    return _redis_client

# Cold Start 최적화
@app.on_event("startup")
async def startup():
    # 미리 연결 초기화
    await get_db_engine()
    await get_redis()
    
    # 필요한 데이터 미리 로드
    await preload_cache()

handler = Mangum(app)
```

### 3. 데이터베이스 쿼리 최적화
```python
# 인덱스 추가
# migrations/versions/0006_performance_indexes.py
def upgrade():
    # 자주 조회되는 컬럼에 인덱스
    op.create_index(
        'idx_recommendations_created_at',
        'recommendations',
        ['created_at'],
        postgresql_using='btree'
    )
    
    op.create_index(
        'idx_recommendations_ticker_score',
        'recommendations',
        ['ticker', 'score'],
        postgresql_using='btree'
    )
    
    # 복합 인덱스
    op.create_index(
        'idx_user_watchlist_user_ticker',
        'user_watchlist',
        ['user_id', 'ticker'],
        unique=True
    )

# N+1 쿼리 방지
from sqlalchemy.orm import selectinload

async def get_recommendations_with_details(limit: int):
    stmt = (
        select(Recommendation)
        .options(
            selectinload(Recommendation.stock),  # JOIN으로 한 번에 로드
            selectinload(Recommendation.evidences)
        )
        .order_by(Recommendation.score.desc())
        .limit(limit)
    )
    result = await db.execute(stmt)
    return result.scalars().all()
```

---

## 🔄 CI/CD 파이프라인

### GitHub Actions 워크플로우
```yaml
# .github/workflows/deploy.yml
name: Deploy to AWS

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  AWS_REGION: ap-northeast-2

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.13'
      
      - name: Install dependencies
        run: |
          pip install uv
          uv sync --extra dev
      
      - name: Run tests
        run: uv run pytest --cov=app --cov-report=xml
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3

  build-and-push:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
      
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1
      
      - name: Build and push frontend image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: stockbrief-dev-frontend
          IMAGE_TAG: ${{ github.sha }}
        run: |
          cd ../camp-fe
          docker build -f ../camp-be/Dockerfile.frontend-lambda \
            -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG \
            -t $ECR_REGISTRY/$ECR_REPOSITORY:latest .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
      
      - name: Update Lambda function
        run: |
          aws lambda update-function-code \
            --function-name stockbrief-dev-frontend-lambda \
            --image-uri $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          
          aws lambda wait function-updated \
            --function-name stockbrief-dev-frontend-lambda

  deploy-terraform:
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
      
      - name: Terraform Init
        run: |
          cd infra/terraform/envs/dev
          terraform init -backend-config=../../backends/dev.hcl
      
      - name: Terraform Plan
        run: |
          cd infra/terraform/envs/dev
          terraform plan -out=tfplan
      
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: |
          cd infra/terraform/envs/dev
          terraform apply -auto-approve tfplan
```

---

## 💰 개선 시 예상 비용

| 항목 | 현재 | 개선 후 | 증가분 |
|------|------|---------|--------|
| **Lambda** | ~$2/월 | ~$7/월 (Provisioned) | +$5 |
| **RDS** | $12.50/월 | $30/월 (Multi-AZ Aurora) | +$17.50 |
| **ElastiCache** | $0 | $24/월 | +$24 |
| **WAF** | $0 | $6/월 | +$6 |
| **CloudWatch/X-Ray** | ~$3/월 | ~$10/월 | +$7 |
| **데이터 전송** | ~$10/월 | ~$15/월 | +$5 |
| **총계** | **~$27.50/월** | **~$92/월** | **+$64.50** |

**월 100만 PV 기준 최종 비용: ~$195/월**

---

## 🎯 우선순위별 구현 로드맵

### Phase 1: 보안 강화 (1-2주) 🔴
1. ✅ WAF 추가 (DDoS, SQL Injection 방어)
2. ✅ API Rate Limiting 구현
3. ✅ Secrets 로테이션 설정
4. ✅ HTTPS 강제 + TLS 1.2 이상

**예상 비용**: +$6/월
**효과**: 보안 취약점 80% 해결

### Phase 2: 옵저버빌리티 (1주) 🔴
1. ✅ X-Ray 분산 추적
2. ✅ 구조화된 로깅
3. ✅ CloudWatch 대시보드
4. ✅ 알람 강화 (CPU, 에러율, 응답시간)

**예상 비용**: +$7/월
**효과**: 장애 발견 시간 90% 단축

### Phase 3: 데이터베이스 스케일링 (2-3주) 🟡
1. ✅ Aurora Serverless v2 마이그레이션
2. ✅ Read Replica 추가
3. ✅ RDS Proxy 활성화
4. ✅ 쿼리 최적화 + 인덱스

**예상 비용**: +$30/월
**효과**: DB 병목 제거, 동시 접속 10배 증가

### Phase 4: 캐싱 레이어 (1주) 🟡
1. ✅ ElastiCache (Redis) 추가
2. ✅ 애플리케이션 캐싱 로직 구현
3. ✅ CloudFront 캐싱 최적화

**예상 비용**: +$24/월
**효과**: API 응답속도 10배 향상, DB 부하 70% 감소

### Phase 5: 고가용성 (1주) 🟡
1. ✅ Multi-AZ 활성화
2. ✅ Auto Scaling 정책
3. ✅ 재해 복구 계획 수립

**예상 비용**: +$5/월
**효과**: 99.9% → 99.99% 가용성

### Phase 6: CI/CD (1-2주) 🟢
1. ✅ GitHub Actions 워크플로우
2. ✅ Blue/Green 배포
3. ✅ Canary 배포 (1% → 10% → 100%)
4. ✅ 자동 롤백

**예상 비용**: $0 (GitHub Actions Free Tier)
**효과**: 배포 시간 단축, 장애 최소화

---

## 📈 트래픽별 권장 아키텍처

### 소규모 (<10만 PV/월)
**현재 아키텍처 + Phase 1,2만 구현**
- Lambda + CloudFront + RDS t4g.micro
- WAF + 기본 모니터링
- **예상 비용**: ~$40/월

### 중규모 (10만~100만 PV/월)
**Phase 1~4 구현**
- Lambda + CloudFront + Aurora Serverless v2
- ElastiCache 추가
- X-Ray + 구조화된 로깅
- **예상 비용**: ~$95/월

### 대규모 (100만+ PV/월)
**모든 Phase 구현**
- Multi-AZ Aurora + Read Replicas
- ElastiCache Cluster
- Provisioned Concurrency
- 전체 옵저버빌리티 스택
- **예상 비용**: ~$195/월 (100만 PV 기준)

---

## ✅ 최종 체크리스트

### 프로덕션 Go-Live 전 필수 확인사항

- [ ] **보안**
  - [ ] WAF 설정 완료
  - [ ] API Rate Limiting 테스트
  - [ ] Secrets 로테이션 자동화
  - [ ] 침투 테스트 (Penetration Testing)
  
- [ ] **성능**
  - [ ] 부하 테스트 (Locust, JMeter)
  - [ ] 동시 접속자 1,000명 테스트 통과
  - [ ] API 응답 시간 < 500ms (P95)
  - [ ] 데이터베이스 인덱스 최적화
  
- [ ] **가용성**
  - [ ] Multi-AZ 활성화
  - [ ] 자동 백업 확인
  - [ ] 재해 복구 계획 수립 및 테스트
  - [ ] Health Check 구현
  
- [ ] **모니터링**
  - [ ] 모든 알람 테스트
  - [ ] 대시보드 검증
  - [ ] On-call 로테이션 설정
  - [ ] PagerDuty/Slack 연동
  
- [ ] **비용**
  - [ ] 예산 알람 설정
  - [ ] 비용 최적화 검토
  - [ ] Reserved Instance 검토 (장기 운영 시)
  
- [ ] **법적 요구사항**
  - [ ] GDPR/개인정보보호법 준수
  - [ ] 이용약관/개인정보처리방침
  - [ ] 로그 보관 정책
  
- [ ] **문서화**
  - [ ] 운영 매뉴얼 작성
  - [ ] 장애 대응 플레이북
  - [ ] API 문서 최신화
  - [ ] 아키텍처 다이어그램 업데이트

---

## 🎓 참고 자료

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [AWS Serverless Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [The Twelve-Factor App](https://12factor.net/)
- [Site Reliability Engineering (SRE) Book](https://sre.google/books/)

---

**작성일**: 2024
**버전**: 1.0
**담당자**: 개인 프로젝트
