# 🎊 프론트엔드 배포 완료 가이드

**축하합니다!** 프론트엔드 수동 배포를 위한 모든 가이드와 스크립트가 준비되었습니다! 🚀

---

## 📁 생성된 파일

### ⚡ 빠른 시작
- **`FRONTEND_QUICK_START.md`** - 5분 안에 배포하기

### 🔧 배포 스크립트
- **`scripts/deploy-frontend-manual.ps1`** - 자동 배포 PowerShell 스크립트

### 📚 상세 가이드
- **`docs/FRONTEND_DEPLOYMENT_CHECKLIST.md`** - 단계별 체크리스트
- **`docs/MANUAL_FRONTEND_DEPLOYMENT.md`** - 수동 배포 상세 가이드
- **`docs/FRONTEND_LAMBDA_DEPLOYMENT.md`** - 기술 문서 (이미 존재)
- **`docs/LAMBDA_WEB_ADAPTER_MIGRATION.md`** - 마이그레이션 가이드 (이미 존재)

### 📖 README 업데이트
- **`README.md`** - 프론트엔드 배포 섹션 추가

---

## 🚀 지금 바로 시작하기!

### Option 1: 자동 스크립트 (가장 빠름!) ⭐

```powershell
cd camp-be
.\scripts\deploy-frontend-manual.ps1
```

이 스크립트는:
1. ✅ AWS 계정 ID 자동 감지
2. ✅ ECR Repository 확인/생성
3. ✅ Docker 이미지 빌드 및 푸시
4. ✅ Lambda 함수 업데이트
5. ✅ 다음 단계 안내

### Option 2: 빠른 시작 가이드 (5분)

```powershell
# 가이드 열기
notepad FRONTEND_QUICK_START.md

# 또는 VS Code에서
code FRONTEND_QUICK_START.md
```

### Option 3: 체크리스트 방식 (안전함)

```powershell
# 체크리스트 열기
notepad docs\FRONTEND_DEPLOYMENT_CHECKLIST.md

# 하나씩 체크하며 진행
```

### Option 4: 완전 수동 (최대 제어)

```powershell
# 상세 가이드 열기
notepad docs\MANUAL_FRONTEND_DEPLOYMENT.md

# 모든 단계를 수동으로 진행
```

---

## 📋 배포 순서

### 1단계: Docker 이미지 준비 (5분)

```powershell
# 자동 스크립트 사용
.\scripts\deploy-frontend-manual.ps1

# 또는 수동 실행
cd ..\camp-fe
docker build -f ..\camp-be\Dockerfile.frontend-lambda -t stockbrief-dev-frontend:latest .
```

### 2단계: Terraform 배포 (3분)

```powershell
cd infra\terraform\envs\dev
terraform init -backend-config=..\..\backends\dev.hcl
terraform apply  # "yes" 입력
```

### 3단계: URL 확인

```powershell
terraform output frontend_hosted_url
```

**출력 예시:** `https://d1234567890abc.cloudfront.net`

### 4단계: Cognito 설정 ⚠️ **필수!**

1. AWS Console → Cognito → User Pools → `stockbrief-dev-userpool`
2. App Integration → App Clients → 클라이언트 선택
3. Hosted UI → Edit
4. Callback URLs에 추가:
   ```
   https://[cloudfront-url]/auth/callback
   ```
5. Sign-out URLs에 추가:
   ```
   https://[cloudfront-url]/account
   ```

---

## 🎯 예상 배포 시간

| 방법 | 시간 | 난이도 |
|------|------|--------|
| **자동 스크립트** | 5-8분 | ⭐☆☆☆☆ |
| **빠른 시작 가이드** | 5-10분 | ⭐⭐☆☆☆ |
| **체크리스트** | 10-15분 | ⭐⭐⭐☆☆ |
| **완전 수동** | 15-20분 | ⭐⭐⭐⭐☆ |

---

## 💰 예상 비용

### 개발 환경 (낮은 트래픽)
- **Lambda**: 무료 티어 내 (~$0/월)
- **CloudFront**: ~$1-5/월
- **ECR**: ~$0.10/월
- **총 예상**: **~$1-5/월**

### 프로덕션 (월 100만 페이지뷰)
- **Lambda**: ~$17/월
- **CloudFront**: ~$85/월
- **ECR**: ~$0.10/월
- **총 예상**: **~$102/월**

**💡 비교**: ECS 기반 ($133/월) 대비 약 **23% 절감**

---

## ✅ 테스트 방법

### 1. 브라우저 테스트

```powershell
# CloudFront URL 복사
terraform output frontend_hosted_url

# 브라우저에서 열기
# https://d1234567890abc.cloudfront.net
```

### 2. Lambda 로그 확인

```powershell
aws logs tail /aws/lambda/stockbrief-dev-frontend-lambda --follow
```

### 3. 로그인 테스트

1. 프론트엔드에서 "로그인" 클릭
2. Cognito Hosted UI로 리다이렉트 확인
3. 로그인 후 `/auth/callback`으로 돌아오는지 확인

---

## 🔄 코드 업데이트 배포 (2분)

프론트엔드 코드를 수정한 후:

```powershell
# 자동 업데이트
.\scripts\deploy-frontend-manual.ps1

# 또는 수동 업데이트
cd ..\camp-fe
docker build -f ..\camp-be\Dockerfile.frontend-lambda -t stockbrief-dev-frontend:latest .
docker tag stockbrief-dev-frontend:latest 389998437416.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest
docker push 389998437416.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest

cd ..\camp-be
aws lambda update-function-code `
    --function-name stockbrief-dev-frontend-lambda `
    --image-uri 389998437416.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest `
    --region ap-northeast-2
```

---

## 🐛 문제 해결

### ❌ "ECR repository not found"

```powershell
aws ecr create-repository `
    --repository-name stockbrief-dev-frontend `
    --region ap-northeast-2
```

### ❌ Docker 빌드 실패

```powershell
cd ..\camp-fe
npm install
# 또는
pnpm install
```

### ❌ 로그인 실패 (redirect_uri_mismatch)

→ Cognito Callback URL 재확인 (Step 4)

### ❌ 504 Gateway Timeout

→ Lambda 메모리 증가:

`infra/terraform/envs/dev/deploy.auto.tfvars.json`:
```json
{
  "frontend_lambda_memory_mb": 3008,
  "frontend_lambda_timeout_seconds": 60
}
```

그리고 `terraform apply` 재실행.

---

## 📊 모니터링

### CloudWatch Dashboard

```
AWS Console → CloudWatch → Dashboards → stockbrief-dev-main-dashboard
```

### Lambda 메트릭

```
AWS Console → Lambda → stockbrief-dev-frontend-lambda → Monitoring
```

주요 지표:
- **Invocations** (호출 횟수)
- **Duration** (실행 시간)
- **Errors** (에러 발생)
- **Concurrent Executions** (동시 실행)

### CloudFront 통계

```
AWS Console → CloudFront → 배포 선택 → Monitoring
```

주요 지표:
- **Requests** (요청 수)
- **Bytes Downloaded** (데이터 전송량)
- **Error Rate** (에러율)

---

## 🎓 다음 단계

배포가 완료되면:

### 1. 실제 사용자 테스트
- [ ] 회원가입/로그인
- [ ] 주요 기능 동작 확인
- [ ] 모바일 반응형 테스트

### 2. 성능 최적화
- [ ] CloudFront 캐싱 설정 확인
- [ ] Lambda Cold Start 모니터링
- [ ] 이미지 최적화 검토

### 3. 모니터링 설정
- [ ] CloudWatch 알람 설정
- [ ] SNS 이메일 알림 설정
- [ ] 로그 보관 기간 설정

### 4. 비용 최적화
- [ ] CloudWatch 비용 모니터링 설정
- [ ] Lambda 메모리 최적화
- [ ] CloudFront 캐싱 최적화

### 5. 보안 강화
- [ ] WAF 규칙 검토
- [ ] Cognito 설정 검토
- [ ] HTTPS 강제 확인

---

## 📚 참고 문서

### 빠른 참조
- 📋 [배포 체크리스트](./docs/FRONTEND_DEPLOYMENT_CHECKLIST.md)
- ⚡ [빠른 시작](./FRONTEND_QUICK_START.md)

### 상세 가이드
- 📘 [수동 배포 가이드](./docs/MANUAL_FRONTEND_DEPLOYMENT.md)
- 📗 [Lambda 배포 기술 문서](./docs/FRONTEND_LAMBDA_DEPLOYMENT.md)
- 📕 [Lambda Web Adapter 마이그레이션](./docs/LAMBDA_WEB_ADAPTER_MIGRATION.md)

### 아키텍처
- 🏗️ [프로덕션 준비 평가](./docs/PRODUCTION_READINESS_ASSESSMENT.md)
- 🚀 [프로덕션 업그레이드 완료](./docs/PRODUCTION_UPGRADE_COMPLETE.md)
- ⚡ [CloudFront & ECS 최적화](./docs/CLOUDFRONT_ECS_OPTIMIZATION.md)
- 🔥 [Redis 캐싱 가이드](./docs/REDIS_CACHING_GUIDE.md)

---

## 🎉 성공적인 배포를 기원합니다!

이 가이드가 도움이 되었다면:
- ⭐ GitHub 저장소에 Star 눌러주기
- 📢 팀원들과 공유하기
- 💬 피드백 남기기

**Happy Deploying!** 🚀

---

## 📞 지원

문제가 발생하면:

1. **CloudWatch Logs 확인**
   ```powershell
   aws logs tail /aws/lambda/stockbrief-dev-frontend-lambda --follow
   ```

2. **트러블슈팅 가이드 참고**
   - [FRONTEND_QUICK_START.md](./FRONTEND_QUICK_START.md#-문제-해결)
   - [MANUAL_FRONTEND_DEPLOYMENT.md](./docs/MANUAL_FRONTEND_DEPLOYMENT.md#-트러블슈팅)

3. **GitHub Issues 등록**
   - 에러 메시지 첨부
   - 실행한 명령어 기록
   - 환경 정보 (Windows/Mac, AWS Region 등)

---

**Last Updated**: 2024-01-15  
**Version**: 1.0.0
