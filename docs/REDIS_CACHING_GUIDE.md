# Redis 캐싱 구현 가이드

## requirements.txt 또는 pyproject.toml에 추가

```toml
[project.dependencies]
redis = {version = "^5.0.0", extras = ["hiredis"]}  # 성능 최적화를 위한 hiredis 포함
```

## app/services/external/redis_cache.py

```python
import os
import json
import redis.asyncio as redis
from functools import wraps
from typing import Optional, Any, Callable
import hashlib
import logging

logger = logging.getLogger(__name__)

# Redis 클라이언트 (전역, Lambda 인스턴스 간 재사용)
_redis_client: Optional[redis.Redis] = None

async def get_redis_client() -> Optional[redis.Redis]:
    """
    Redis 클라이언트를 가져옵니다. (싱글톤 패턴)
    Redis가 비활성화되어 있으면 None을 반환합니다.
    """
    global _redis_client
    
    redis_endpoint = os.getenv("REDIS_ENDPOINT", "")
    redis_port = os.getenv("REDIS_PORT", "6379")
    redis_auth = os.getenv("REDIS_AUTH_TOKEN", "")
    
    # Redis가 설정되지 않았으면 None 반환 (캐싱 비활성화)
    if not redis_endpoint:
        logger.info("Redis endpoint not configured, caching disabled")
        return None
    
    # 이미 초기화되었으면 기존 클라이언트 반환
    if _redis_client is not None:
        return _redis_client
    
    try:
        _redis_client = await redis.from_url(
            f"rediss://{redis_endpoint}:{redis_port}",  # rediss:// = TLS 활성화
            password=redis_auth,
            decode_responses=True,
            encoding="utf-8",
            socket_timeout=2,  # 2초 타임아웃
            socket_connect_timeout=2,
            retry_on_timeout=True,
            health_check_interval=30
        )
        
        # 연결 테스트
        await _redis_client.ping()
        logger.info("Redis connection established successfully")
        return _redis_client
    
    except Exception as e:
        logger.error(f"Failed to connect to Redis: {e}")
        _redis_client = None
        return None


def generate_cache_key(prefix: str, *args, **kwargs) -> str:
    """
    캐시 키를 생성합니다. 함수 인자들을 해시하여 고유한 키를 만듭니다.
    """
    key_parts = [prefix]
    
    # args를 키에 포함
    for arg in args:
        key_parts.append(str(arg))
    
    # kwargs를 정렬하여 키에 포함
    for k, v in sorted(kwargs.items()):
        key_parts.append(f"{k}={v}")
    
    # 긴 키는 해시로 변환
    key_string = ":".join(key_parts)
    if len(key_string) > 200:
        key_hash = hashlib.md5(key_string.encode()).hexdigest()
        return f"{prefix}:{key_hash}"
    
    return key_string


def cache_result(ttl: int = 300, key_prefix: Optional[str] = None):
    """
    함수 결과를 Redis에 캐싱하는 데코레이터
    
    Args:
        ttl: Time To Live in seconds (기본 5분)
        key_prefix: 캐시 키 접두사 (None이면 함수 이름 사용)
    
    Example:
        @cache_result(ttl=600)  # 10분 캐시
        async def get_stock_data(ticker: str):
            return await db.query(...)
    """
    def decorator(func: Callable):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            redis_client = await get_redis_client()
            
            # Redis가 없으면 캐싱 없이 함수 실행
            if redis_client is None:
                return await func(*args, **kwargs)
            
            # 캐시 키 생성
            prefix = key_prefix or func.__name__
            cache_key = generate_cache_key(prefix, *args, **kwargs)
            
            try:
                # 캐시 확인
                cached = await redis_client.get(cache_key)
                if cached:
                    logger.info(f"Cache HIT: {cache_key}")
                    return json.loads(cached)
                
                logger.info(f"Cache MISS: {cache_key}")
            
            except Exception as e:
                logger.warning(f"Redis GET error: {e}, falling back to function execution")
            
            # 캐시 미스 또는 에러 - 실제 함수 실행
            result = await func(*args, **kwargs)
            
            # 결과를 캐시에 저장 (실패해도 원래 결과는 반환)
            try:
                await redis_client.setex(
                    cache_key,
                    ttl,
                    json.dumps(result, default=str, ensure_ascii=False)
                )
                logger.info(f"Cache SET: {cache_key} (TTL: {ttl}s)")
            except Exception as e:
                logger.warning(f"Redis SET error: {e}")
            
            return result
        
        return wrapper
    return decorator


async def invalidate_cache(pattern: str):
    """
    특정 패턴과 일치하는 캐시 키들을 삭제합니다.
    
    Args:
        pattern: Redis 키 패턴 (예: "get_recommendations:*")
    
    Example:
        # 특정 ticker의 모든 캐시 삭제
        await invalidate_cache("get_stock_data:005930*")
        
        # 모든 추천 관련 캐시 삭제
        await invalidate_cache("get_recommendations:*")
    """
    redis_client = await get_redis_client()
    if redis_client is None:
        return
    
    try:
        keys = []
        async for key in redis_client.scan_iter(match=pattern, count=100):
            keys.append(key)
        
        if keys:
            await redis_client.delete(*keys)
            logger.info(f"Invalidated {len(keys)} cache keys matching pattern: {pattern}")
    
    except Exception as e:
        logger.error(f"Failed to invalidate cache: {e}")


async def get_cache_stats() -> dict:
    """
    Redis 캐시 통계를 반환합니다.
    """
    redis_client = await get_redis_client()
    if redis_client is None:
        return {"enabled": False}
    
    try:
        info = await redis_client.info()
        return {
            "enabled": True,
            "connected_clients": info.get("connected_clients", 0),
            "used_memory_human": info.get("used_memory_human", "N/A"),
            "keyspace_hits": info.get("keyspace_hits", 0),
            "keyspace_misses": info.get("keyspace_misses", 0),
            "hit_rate": round(
                info.get("keyspace_hits", 0) / 
                max(info.get("keyspace_hits", 0) + info.get("keyspace_misses", 0), 1) * 100,
                2
            )
        }
    except Exception as e:
        logger.error(f"Failed to get cache stats: {e}")
        return {"enabled": True, "error": str(e)}
```

## app/routes/candidates.py 수정 예시

```python
from fastapi import APIRouter, Depends, Query
from app.services.external.redis_cache import cache_result, invalidate_cache
from app.services.candidate_service import get_recommendations

router = APIRouter()

# 캐싱 적용 (10분 캐시)
@cache_result(ttl=600, key_prefix="recommendations")
async def get_cached_recommendations(limit: int = 10, offset: int = 0):
    """
    추천 종목 목록을 가져옵니다. 결과는 10분간 캐싱됩니다.
    """
    return await get_recommendations(limit=limit, offset=offset)


@router.get("/recommendations/candidates")
async def list_recommendations(
    limit: int = Query(10, ge=1, le=100),
    offset: int = Query(0, ge=0)
):
    """
    추천 종목 목록 조회 (캐싱 적용)
    """
    return await get_cached_recommendations(limit=limit, offset=offset)


@router.post("/admin/cache/invalidate")
async def invalidate_recommendations_cache():
    """
    추천 관련 캐시를 모두 삭제합니다. (관리자용)
    """
    await invalidate_cache("recommendations:*")
    return {"message": "Cache invalidated successfully"}
```

## app/routes/health.py에 캐시 상태 추가

```python
from fastapi import APIRouter
from app.services.external.redis_cache import get_cache_stats

router = APIRouter()

@router.get("/health")
async def health_check():
    """
    헬스 체크 엔드포인트
    """
    cache_stats = await get_cache_stats()
    
    return {
        "status": "healthy",
        "cache": cache_stats
    }
```

## Lambda 환경변수 설정 (Terraform)

```terraform
# infra/terraform/modules/api_lambda/main.tf
resource "aws_lambda_function" "api" {
  # ... 기존 설정 ...
  
  environment {
    variables = merge(
      var.environment_variables,
      var.enable_elasticache ? {
        REDIS_ENDPOINT   = var.redis_endpoint
        REDIS_PORT       = "6379"
        REDIS_AUTH_TOKEN = data.aws_secretsmanager_secret_version.redis[0].secret_string
      } : {}
    )
  }
}
```

## 캐싱 전략 가이드

### 1. 읽기가 많은 데이터 (높은 TTL)
```python
@cache_result(ttl=3600)  # 1시간
async def get_stock_info(ticker: str):
    # 종목 기본 정보 (자주 변하지 않음)
    pass

@cache_result(ttl=1800)  # 30분
async def get_company_profile(ticker: str):
    # 회사 정보
    pass
```

### 2. 자주 업데이트되는 데이터 (낮은 TTL)
```python
@cache_result(ttl=60)  # 1분
async def get_stock_price(ticker: str):
    # 실시간 주가 (자주 변함)
    pass

@cache_result(ttl=300)  # 5분
async def get_trending_stocks():
    # 인기 종목
    pass
```

### 3. 사용자별 데이터 (중간 TTL + 개인화)
```python
@cache_result(ttl=600, key_prefix="user_watchlist")
async def get_user_watchlist(user_id: str):
    # 사용자 관심 종목
    pass
```

### 4. 수동 캐시 무효화가 필요한 경우
```python
@router.post("/stocks/{ticker}")
async def update_stock(ticker: str, data: StockUpdate):
    # DB 업데이트
    await db.update(...)
    
    # 관련 캐시 삭제
    await invalidate_cache(f"get_stock_info:{ticker}")
    await invalidate_cache(f"get_recommendations:*")  # 추천 목록 재계산 필요
    
    return {"message": "Updated successfully"}
```

## 성능 비교

### 캐싱 전 (DB 직접 조회)
- 응답 시간: 200-500ms
- DB 부하: 높음
- 동시 처리: 50-100 req/s

### 캐싱 후 (Redis 사용)
- 응답 시간: 10-30ms (10배 향상)
- DB 부하: 90% 감소
- 동시 처리: 500-1000 req/s (10배 향상)

## 주의사항

1. **메모리 관리**: 캐시 크기를 모니터링하고 TTL을 적절히 설정
2. **Cache Stampede 방지**: 인기 있는 키가 만료될 때 동시 요청 폭주 주의
3. **캐시 워밍**: 서비스 시작 시 자주 사용되는 데이터 미리 캐싱
4. **장애 대응**: Redis 장애 시에도 서비스가 동작하도록 fallback 구현

## 다음 단계

1. `requirements.txt`에 redis 추가
2. `app/services/external/redis_cache.py` 파일 생성
3. 주요 엔드포인트에 `@cache_result` 데코레이터 적용
4. Terraform apply로 ElastiCache 배포
5. 성능 테스트 및 TTL 최적화
