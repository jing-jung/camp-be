# ✅ 프론트엔드 배포 체크리스트

이 체크리스트를 단계별로 따라 진행하세요! 🚀

---

## 📋 사전 준비 체크

- [ ] AWS CLI 설치 및 로그인 완료
  ```powershell
  aws sts get-caller-identity
  ```

- [ ] Docker Desktop 설치 및 실행 중
  ```powershell
  docker version
  ```

- [ ] camp-fe 프로젝트 존재 확인
  ```powershell
  ls ..\camp-fe
  ```

- [ ] Next.js standalone 설정 확인
  - `camp-fe/next.config.ts`에 `output: 'standalone'` 있는지 확인

---

## 🚀 배포 단계 체크

### ⭐ Option A: 자동 스크립트 (권장)

- [ ] 스크립트 실행
  ```powershell
  cd camp-be
  .\scripts\deploy-frontend-manual.ps1
  ```

### 📝 Option B: 수동 배포

#### Step 1: ECR Repository 생성

- [ ] ECR Repository 존재 확인
  ```powershell
  aws ecr describe-repositories --repository-names stockbrief-dev-frontend --region ap-northeast-2
  ```

- [ ] 없으면 생성
  ```powershell
  aws ecr create-repository `
      --repository-name stockbrief-dev-frontend `
      --region ap-northeast-2 `
      --image-scanning-configuration scanOnPush=true
  ```

#### Step 2: Docker 이미지 빌드 및 푸시

- [ ] ECR 로그인
  ```powershell
  aws ecr get-login-password --region ap-northeast-2 | `
      docker login --username AWS --password-stdin `
      "560271561793.dkr.ecr.ap-northeast-2.amazonaws.com"
  ```

- [ ] Docker 이미지 빌드
  ```powershell
  cd ..\camp-fe
  docker build -f ..\camp-be\Dockerfile.frontend-lambda `
      -t stockbrief-dev-frontend:latest .
  ```

- [ ] 이미지 태그 및 푸시
  ```powershell
  docker tag stockbrief-dev-frontend:latest `
      560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest
  docker push `
      560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest
  ```

- [ ] 프로젝트 루트로 복귀
  ```powershell
  cd ..\camp-be
  ```

#### Step 3: Terraform 배포

- [ ] Terraform 설정 확인
  - `infra/terraform/envs/dev/deploy.auto.tfvars.json` 확인
  - `enable_frontend_lambda: true` 확인
  - `enable_frontend_cloudfront_lambda: true` 확인

- [ ] Terraform 초기화 (최초 1회)
  ```powershell
  cd infra\terraform\envs\dev
  terraform init -backend-config=..\..\backends\dev.hcl
  ```

- [ ] Terraform 배포
  ```powershell
  terraform plan  # 변경사항 미리보기
  terraform apply  # yes 입력
  ```

#### Step 4: 배포 확인

- [ ] Lambda 함수 확인
  ```powershell
  aws lambda get-function `
      --function-name stockbrief-dev-frontend-lambda `
      --region ap-northeast-2
  ```

- [ ] Lambda Function URL 확인
  ```powershell
  terraform output frontend_lambda_function_url
  ```

- [ ] CloudFront URL 확인
  ```powershell
  terraform output frontend_hosted_url
  ```

#### Step 5: Cognito Callback URL 업데이트 ⚠️

- [ ] CloudFront URL 복사
  ```powershell
  terraform output frontend_hosted_url
  ```

- [ ] AWS Console에서 Cognito 설정
  - Cognito → User Pools → `stockbrief-dev-userpool`
  - App Integration → App Clients → 클라이언트 선택
  - Hosted UI → Edit

- [ ] Callback URLs 추가
  ```
  https://[cloudfront-url]/auth/callback
  ```

- [ ] Sign-out URLs 추가
  ```
  https://[cloudfront-url]/account
  ```

---

## ✅ 테스트 체크

- [ ] 브라우저에서 CloudFront URL 접속
  ```
  https://d1234567890abc.cloudfront.net
  ```

- [ ] 메인 페이지 로딩 확인

- [ ] 로그인 기능 테스트
  - 로그인 버튼 클릭
  - Cognito Hosted UI 리다이렉트 확인
  - 로그인 후 콜백 성공 확인

- [ ] Lambda 로그 확인
  ```powershell
  aws logs tail /aws/lambda/stockbrief-dev-frontend-lambda `
      --follow --region ap-northeast-2
  ```

---

## 📊 모니터링 체크

- [ ] CloudWatch 대시보드 확인
  ```
  AWS Console → CloudWatch → Dashboards
  ```

- [ ] Lambda 메트릭 확인
  - Invocations (호출 횟수)
  - Duration (실행 시간)
  - Errors (에러 발생)

- [ ] CloudFront 통계 확인
  - Requests
  - Data Transfer
  - Error Rate

---

## 🔄 업데이트 배포 체크 (코드 변경 시)

- [ ] Docker 이미지 재빌드
  ```powershell
  cd ..\camp-fe
  docker build -f ..\camp-be\Dockerfile.frontend-lambda `
      -t stockbrief-dev-frontend:latest .
  ```

- [ ] ECR에 푸시
  ```powershell
  docker tag stockbrief-dev-frontend:latest `
      560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest
  docker push `
      560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest
  ```

- [ ] Lambda 함수 업데이트
  ```powershell
  cd ..\camp-be
  aws lambda update-function-code `
      --function-name stockbrief-dev-frontend-lambda `
      --image-uri 560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest `
      --region ap-northeast-2
  ```

- [ ] 업데이트 완료 확인
  ```powershell
  aws lambda get-function `
      --function-name stockbrief-dev-frontend-lambda `
      --region ap-northeast-2 `
      --query 'Configuration.LastUpdateStatus'
  ```
  출력: `"Successful"`

- [ ] CloudFront 캐시 무효화 (필요 시)
  ```powershell
  $DISTRIBUTION_ID = (terraform output -raw frontend_cloudfront_distribution_id)
  aws cloudfront create-invalidation `
      --distribution-id $DISTRIBUTION_ID `
      --paths "/*"
  ```

---

## 🐛 문제 해결 체크

### Docker 빌드 실패

- [ ] Node.js 의존성 설치
  ```powershell
  cd ..\camp-fe
  npm install
  ```

- [ ] Docker Desktop 실행 확인

### Lambda 함수 없음

- [ ] Terraform 배포 상태 확인
  ```powershell
  cd infra\terraform\envs\dev
  terraform plan
  ```

- [ ] Terraform 재배포
  ```powershell
  terraform apply
  ```

### 로그인 실패 (redirect_uri_mismatch)

- [ ] Cognito Callback URL 재확인
- [ ] CloudFront URL이 정확한지 확인
- [ ] `/auth/callback` 경로 포함 확인

### 504 Gateway Timeout

- [ ] Lambda 메모리 증가 (deploy.auto.tfvars.json)
  ```json
  {
    "frontend_lambda_memory_mb": 3008,
    "frontend_lambda_timeout_seconds": 60
  }
  ```

- [ ] Terraform 재배포
  ```powershell
  terraform apply
  ```

---

## 📝 배포 정보 기록

배포 후 아래 정보를 기록해두세요:

- **배포 일시:** ____________________
- **ECR 이미지 URI:** 
  ```
  560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest
  ```
- **Lambda Function URL:** ____________________
- **CloudFront URL:** ____________________
- **Cognito User Pool ID:** `ap-northeast-2_MT59vnjQg`
- **Cognito Client ID:** `3vhl76s71q3r4r53t05ms29m5f`

---

## 📚 참고 문서

- [ ] [수동 배포 상세 가이드](./MANUAL_FRONTEND_DEPLOYMENT.md)
- [ ] [프론트엔드 Lambda 배포 가이드](./FRONTEND_LAMBDA_DEPLOYMENT.md)
- [ ] [전체 배포 가이드](./DEPLOYMENT_GUIDE.md)

---

## 🎉 완료!

모든 단계를 완료했다면 프론트엔드 배포가 성공적으로 완료되었습니다! 🚀

**다음 단계:**
- 실제 사용자 테스트 진행
- 성능 모니터링 설정
- 알림 설정 (CloudWatch Alarms)
- 백업 전략 수립

Happy Deploying! 🎊
