# StockBrief API 테스트 가이드

## 📋 배포 정보

### API Endpoint
```
https://sgg6hmfaij.execute-api.ap-northeast-2.amazonaws.com
```

### Database
- **Endpoint**: stockbrief-dev-postgres.c5s4g8sm0q35.ap-northeast-2.rds.amazonaws.com:5432
- **Database**: stockbrief
- **Username**: stockbrief_admin
- **Password**: 1Bd8sB?obnD))zgMftsYVQN#fv)i

### Cognito
- **User Pool ID**: ap-northeast-2_MT59vnjQg
- **App Client ID**: 3vhl76s71q3r4r53t05ms29m5f
- **Hosted UI**: https://stockbrief-dev-389998437416.auth.ap-northeast-2.amazoncognito.com

### Redis
- **Endpoint**: master.stockbrief-dev-redis.swzrk3.apn2.cache.amazonaws.com

---

## 🔧 1. 데이터베이스 마이그레이션

### Windows (PowerShell)
```powershell
cd camp-be
.\scripts\migrate.ps1
```

### Linux/Mac
```bash
cd camp-be
chmod +x scripts/migrate.sh
./scripts/migrate.sh
```

### 또는 수동 실행
```bash
cd camp-be
export DATABASE_URL="postgresql+psycopg://stockbrief_admin:1Bd8sB?obnD))zgMftsYVQN#fv)i@stockbrief-dev-postgres.c5s4g8sm0q35.ap-northeast-2.rds.amazonaws.com:5432/stockbrief"
alembic upgrade head
```

---

## 🧪 2. API 테스트

### Health Check (인증 불필요)
```bash
curl https://sgg6hmfaij.execute-api.ap-northeast-2.amazonaws.com/v1/health
```

예상 응답:
```json
{
  "status": "healthy",
  "service": "stockbrief-api",
  "version": "0.1.0",
  "environment": "dev"
}
```

### 종목 검색 (인증 불필요)
```bash
curl https://sgg6hmfaij.execute-api.ap-northeast-2.amazonaws.com/v1/tickers/search?q=삼성
```

### 특정 종목 정보 조회 (인증 불필요)
```bash
curl https://sgg6hmfaij.execute-api.ap-northeast-2.amazonaws.com/v1/tickers/005930
```

---

## 🔐 3. 인증 테스트

### 3.1 Cognito에 사용자 생성

AWS Console 또는 CLI로 사용자 생성:
```bash
aws cognito-idp admin-create-user \
  --user-pool-id ap-northeast-2_MT59vnjQg \
  --username testuser \
  --user-attributes Name=email,Value=test@example.com \
  --temporary-password TempPassword123! \
  --region ap-northeast-2
```

### 3.2 JWT 토큰 받기

Cognito Hosted UI를 통해 로그인:
```
https://stockbrief-dev-389998437416.auth.ap-northeast-2.amazoncognito.com/login?client_id=3vhl76s71q3r4r53t05ms29m5f&response_type=code&redirect_uri=http://localhost:3000/auth/callback
```

또는 CLI로 직접 토큰 받기:
```bash
aws cognito-idp admin-initiate-auth \
  --user-pool-id ap-northeast-2_MT59vnjQg \
  --client-id 3vhl76s71q3r4r53t05ms29m5f \
  --auth-flow ADMIN_NO_SRP_AUTH \
  --auth-parameters USERNAME=testuser,PASSWORD=YourPassword123! \
  --region ap-northeast-2
```

### 3.3 인증이 필요한 API 테스트

```bash
# JWT 토큰을 변수에 저장
TOKEN="your_jwt_token_here"

# 내 정보 조회
curl -H "Authorization: Bearer $TOKEN" \
  https://sgg6hmfaij.execute-api.ap-northeast-2.amazonaws.com/v1/me

# 관심 종목 목록 조회
curl -H "Authorization: Bearer $TOKEN" \
  https://sgg6hmfaij.execute-api.ap-northeast-2.amazonaws.com/v1/me/watchlist

# 관심 종목 추가
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ticker":"005930"}' \
  https://sgg6hmfaij.execute-api.ap-northeast-2.amazonaws.com/v1/me/watchlist
```

---

## 📊 4. 모니터링

### CloudWatch Dashboard
```
https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-2#dashboards:name=stockbrief-dev-main-dashboard
```

### Lambda 로그 확인
```bash
aws logs tail /aws/lambda/stockbrief-dev-api --follow --region ap-northeast-2
```

### RDS 연결 확인
```bash
psql "postgresql://stockbrief_admin:1Bd8sB?obnD))zgMftsYVQN#fv)i@stockbrief-dev-postgres.c5s4g8sm0q35.ap-northeast-2.rds.amazonaws.com:5432/stockbrief" -c "\dt"
```

---

## 🐛 문제 해결

### Lambda가 응답하지 않는 경우
1. Lambda 함수 로그 확인
2. VPC 보안 그룹 확인
3. NAT Gateway 정상 작동 확인

### 데이터베이스 연결 실패
1. Security Group에서 Lambda에서 RDS로의 접근 허용 확인
2. RDS 인스턴스 상태 확인
3. 비밀번호 정확성 확인

### API Gateway 오류
1. API Gateway 로그 확인
2. Lambda 권한 확인
3. Lambda 배포 상태 확인

---

## 🚀 다음 단계

1. ✅ 데이터베이스 마이그레이션 완료
2. ✅ API 엔드포인트 테스트
3. ✅ 인증 흐름 테스트
4. 프론트엔드 배포
5. 실제 데이터 입력
6. 부하 테스트
