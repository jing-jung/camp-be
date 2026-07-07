# CloudFront 캐싱 & ECS Auto Scaling 최적화 가이드

## 📋 개요

이 문서는 프로덕션 환경에서 성능과 비용 최적화를 위해 구현된 CloudFront 캐싱 전략과 ECS Auto Scaling 설정에 대해 설명합니다.

---

## 🚀 CloudFront 캐싱 최적화

### 구현된 캐싱 전략

#### 1. **정적 자산 (/_next/static/\*)**
- **캐싱 기간**: 1년 (31,536,000초)
- **대상**: Next.js 빌드 시 생성된 JS, CSS 파일
- **특징**: 
  - 파일명에 해시 포함으로 안전한 장기 캐싱
  - 쿠키 전달 안 함 (성능 향상)
  - 쿼리 스트링 무시

```hcl
ordered_cache_behavior {
  path_pattern = "/_next/static/*"
  default_ttl  = 31536000  # 1 year
  max_ttl      = 31536000
}
```

#### 2. **공용 정적 자산 (/static/\*)**
- **캐싱 기간**: 24시간 (기본), 최대 1년
- **대상**: 이미지, 폰트, 기타 정적 파일
- **특징**: 
  - 자주 변경되지 않는 파일 장기 캐싱
  - 압축 활성화

```hcl
ordered_cache_behavior {
  path_pattern = "/static/*"
  default_ttl  = 86400      # 24 hours
  max_ttl      = 31536000   # 1 year
}
```

#### 3. **API 경로 (/api/\*)**
- **캐싱**: 비활성화
- **대상**: 백엔드 API 요청
- **특징**:
  - 모든 헤더/쿠키 전달
  - 실시간 데이터 보장

```hcl
ordered_cache_behavior {
  path_pattern = "/api/*"
  default_ttl  = 0  # No caching
  max_ttl      = 0
}
```

#### 4. **기본 동작 (HTML 페이지)**
- **캐싱 기간**: 1시간 (설정 가능)
- **대상**: 모든 HTML 페이지
- **특징**:
  - Cache-Control 헤더 존중
  - 사용자 인증 정보 전달

```hcl
default_cache_behavior {
  min_ttl     = 0
  default_ttl = 3600   # 1 hour (configurable)
  max_ttl     = 86400  # 24 hours
}
```

---

## 📊 기대 효과

### 성능 개선
- ⚡ **응답 속도**: 50-200ms → 5-20ms (10배 향상)
- 🌍 **글로벌 접근**: 전 세계 엣지 로케이션에서 캐시 제공
- 📉 **서버 부하**: 오리진 요청 70-90% 감소

### 비용 절감
- 💰 **CloudFront 비용**: Origin 요청 비용 70% 절감
- 💸 **ALB/ECS 비용**: 트래픽 처리 감소로 리소스 효율 증가
- 📦 **데이터 전송**: 반복 요청 시 캐시 히트로 비용 감소

---

## 🔧 설정 방법

### Terraform 변수 설정

`infra/terraform/envs/dev/deploy.auto.tfvars.json`에서 설정:

```json
{
  "enable_caching": true,
  "default_ttl": 3600,
  "min_ttl": 0,
  "max_ttl": 86400
}
```

### 변수 설명

| 변수 | 설명 | 기본값 | 추천값 |
|------|------|--------|--------|
| `enable_caching` | CloudFront 캐싱 활성화 | `true` | `true` |
| `default_ttl` | 기본 캐싱 시간 (초) | 3600 | 3600-7200 |
| `min_ttl` | 최소 캐싱 시간 (초) | 0 | 0 |
| `max_ttl` | 최대 캐싱 시간 (초) | 86400 | 86400 |

---

## 🎯 ECS Auto Scaling

### 구현된 스케일링 정책

#### 1. **CPU 기반 스케일링**
- **타겟**: CPU 사용률 70%
- **동작**: CPU가 70%를 넘으면 태스크 추가

```hcl
target_tracking_scaling_policy_configuration {
  target_value = 70
  predefined_metric_type = "ECSServiceAverageCPUUtilization"
}
```

#### 2. **메모리 기반 스케일링**
- **타겟**: 메모리 사용률 80%
- **동작**: 메모리가 80%를 넘으면 태스크 추가

```hcl
target_tracking_scaling_policy_configuration {
  target_value = 80
  predefined_metric_type = "ECSServiceAverageMemoryUtilization"
}
```

#### 3. **요청 수 기반 스케일링**
- **타겟**: 태스크당 분당 1,000 요청
- **동작**: 요청이 증가하면 자동으로 태스크 추가

```hcl
target_tracking_scaling_policy_configuration {
  target_value = 1000
  predefined_metric_type = "ALBRequestCountPerTarget"
}
```

---

## 📈 스케일링 시나리오

### 시나리오 1: 정상 트래픽
```
태스크 수: 1개
CPU: 30-40%
메모리: 50-60%
→ 스케일링 없음
```

### 시나리오 2: 트래픽 증가
```
시간 00:00 - 태스크 1개 (CPU 50%)
시간 00:05 - 트래픽 2배 증가 (CPU 80%)
시간 00:06 - 스케일 아웃 → 태스크 2개
시간 00:07 - CPU 45% (안정화)
```

### 시나리오 3: 트래픽 감소
```
시간 01:00 - 태스크 3개 (CPU 30%)
시간 01:05 - 트래픽 감소 지속 (CPU 20%)
시간 01:10 - 쿨다운 후 스케일 인 → 태스크 2개
```

---

## 🔧 설정 방법

### Terraform 변수 설정

`infra/terraform/envs/dev/deploy.auto.tfvars.json`에서 설정:

```json
{
  "enable_autoscaling": true,
  "min_capacity": 1,
  "max_capacity": 4,
  "cpu_target_value": 70,
  "memory_target_value": 80,
  "scale_in_cooldown": 300,
  "scale_out_cooldown": 60
}
```

### 변수 설명

| 변수 | 설명 | 기본값 | 추천값 (Dev) | 추천값 (Prod) |
|------|------|--------|--------------|---------------|
| `enable_autoscaling` | Auto Scaling 활성화 | `true` | `true` | `true` |
| `min_capacity` | 최소 태스크 수 | 1 | 1 | 2 |
| `max_capacity` | 최대 태스크 수 | 4 | 3 | 10 |
| `cpu_target_value` | CPU 목표 사용률 (%) | 70 | 70 | 60-70 |
| `memory_target_value` | 메모리 목표 사용률 (%) | 80 | 80 | 75-80 |
| `scale_in_cooldown` | 스케일 인 대기 시간 (초) | 300 | 300 | 300-600 |
| `scale_out_cooldown` | 스케일 아웃 대기 시간 (초) | 60 | 60 | 30-60 |

---

## 💰 비용 영향

### 개발 환경 (Dev)
- **기본 설정**: 1개 태스크 상시 실행
- **월 예상 비용**: ~$15-20 (Fargate 256 CPU / 512 MB)
- **피크 시**: 최대 3개 → ~$45-60 (일시적)

### 프로덕션 환경 (Prod)
- **기본 설정**: 2개 태스크 상시 실행 (고가용성)
- **월 예상 비용**: ~$30-40
- **피크 시**: 최대 10개 → ~$150-200 (일시적)

**💡 Tip**: CloudFront 캐싱으로 인해 ECS 스케일링 빈도가 줄어들어 실제 비용은 더 낮을 수 있습니다.

---

## 📊 모니터링

### CloudWatch 메트릭 확인

#### CloudFront 캐시 히트율
```bash
# AWS Console → CloudFront → Monitoring
- CacheHitRate: 목표 70% 이상
- OriginLatency: 목표 100ms 이하
```

#### ECS 스케일링 이벤트
```bash
# AWS Console → ECS → Cluster → Service → Events
- Scaling activities 확인
- Desired count 변화 추적
```

#### 비용 추적
```bash
# AWS Console → Cost Explorer
- Service: ECS, CloudFront, ALB
- Daily/Monthly 비용 추이 확인
```

---

## 🔍 트러블슈팅

### 문제 1: 캐시 히트율이 낮음 (<50%)

**원인**:
- 동적 콘텐츠 비율이 높음
- Cache-Control 헤더가 잘못 설정됨

**해결책**:
```javascript
// Next.js에서 정적 페이지 캐싱 헤더 추가
export async function getStaticProps() {
  return {
    props: { ... },
    revalidate: 3600, // 1 hour ISR
  }
}
```

### 문제 2: ECS 태스크가 너무 자주 스케일링됨

**원인**:
- 쿨다운 시간이 너무 짧음
- 타겟 값이 너무 낮음

**해결책**:
```json
{
  "cpu_target_value": 75,        // 70 → 75로 증가
  "scale_out_cooldown": 120,     // 60 → 120으로 증가
  "scale_in_cooldown": 600       // 300 → 600으로 증가
}
```

### 문제 3: 캐시 무효화가 필요함

**해결책**:
```bash
# CloudFront 캐시 무효화 (새 배포 시)
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/*"
```

---

## 📚 참고 자료

- [AWS CloudFront Caching Best Practices](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/ConfiguringCaching.html)
- [ECS Auto Scaling Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html)
- [Next.js Caching Strategies](https://nextjs.org/docs/app/building-your-application/caching)

---

## ✅ 체크리스트

### 배포 전
- [ ] CloudFront 캐싱 변수 설정 확인
- [ ] ECS Auto Scaling 변수 설정 확인
- [ ] 최소/최대 태스크 수 검토
- [ ] 예산 알림 설정

### 배포 후
- [ ] CloudFront 캐시 히트율 확인 (목표: 70%+)
- [ ] ECS 태스크 수 모니터링
- [ ] CloudWatch 알람 동작 확인
- [ ] 비용 추이 모니터링 (첫 1주)

### 최적화
- [ ] 1주 후 캐시 TTL 조정
- [ ] 2주 후 Auto Scaling 임계값 튜닝
- [ ] 1개월 후 비용 대비 성능 분석

---

**작성일**: 2025-01-XX  
**버전**: 1.0  
**작성자**: Infrastructure Team
