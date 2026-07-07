# 🚀 Camp Project - Backend

> **Lambda Web Adapter 기반 서버리스 풀스택 프로젝트**

개인 학습 및 포트폴리오 목적의 프로젝트로, FastAPI 백엔드와 Next.js 프론트엔드를 AWS Lambda로 서버리스 배포하는 현대적인 아키텍처를 구현했습니다.

## ✨ 주요 특징

- 🐍 **FastAPI** - 현대적이고 빠른 Python 웹 프레임워크
- 🗄️ **PostgreSQL + Alembic** - 체계적인 데이터베이스 마이그레이션
- ☁️ **AWS Lambda** - 비용 효율적인 서버리스 컴퓨팅
- 🌐 **Lambda Web Adapter** - 컨테이너 앱을 Lambda에서 실행
- 🏗️ **Terraform** - Infrastructure as Code로 AWS 리소스 관리
- 🔐 **AWS Cognito** - 사용자 인증 및 권한 관리
- 🤖 **Amazon Bedrock** - AI 기반 채팅 기능
- 📊 **CloudWatch** - 로그 및 모니터링

## 🎯 프로젝트 목표

1. **서버리스 아키텍처 실습**: ECS → Lambda Web Adapter 전환 경험
2. **IaC 실무 경험**: Terraform으로 프로덕션급 인프라 구축
3. **비용 최적화**: 트래픽에 따른 탄력적인 비용 구조 구현
4. **풀스택 개발**: 백엔드 API부터 프론트엔드 배포까지 전체 파이프라인 구축

## 📁 프로젝트 구조

```
camp-be/
├── app/                          # FastAPI 애플리케이션
│   ├── routes/                   # API 엔드포인트
│   ├── services/                 # 비즈니스 로직
│   │   ├── recommendation/       # 추천 알고리즘 엔진
│   │   ├── chat/                 # AI 채팅 서비스
│   │   └── external/             # 외부 API 어댑터
│   ├── models.py                 # Pydantic 모델
│   ├── orm.py                    # SQLAlchemy ORM
│   └── main.py                   # FastAPI 앱 진입점
├── infra/terraform/              # Infrastructure as Code
│   ├── modules/                  # 재사용 가능한 Terraform 모듈
│   │   ├── api_lambda/           # FastAPI Lambda 모듈
│   │   ├── frontend_lambda/      # Next.js Lambda 모듈
│   │   ├── frontend_cloudfront_lambda/  # CloudFront 배포
│   │   ├── rds/                  # PostgreSQL RDS
│   │   └── cognito/              # 사용자 인증
│   └── envs/dev/                 # 환경별 설정
├── migrations/                   # Alembic DB 마이그레이션
├── tests/                        # pytest 테스트 스위트
├── scripts/                      # 배포 자동화 스크립트
├── docs/                         # 프로젝트 문서
│   ├── FRONTEND_LAMBDA_DEPLOYMENT.md
│   └── LAMBDA_WEB_ADAPTER_MIGRATION.md
└── Dockerfile.frontend-lambda    # Lambda Web Adapter Dockerfile
```

## 🛠️ 기술 스택

### Backend
- **Python 3.13** - 최신 Python 버전
- **FastAPI** - 고성능 비동기 웹 프레임워크
- **SQLAlchemy** - ORM
- **Alembic** - 데이터베이스 마이그레이션
- **Pydantic** - 데이터 검증
- **Mangum** - ASGI → Lambda 어댑터

### Frontend
- **Next.js 14** - React 프레임워크 (SSR)
- **TypeScript** - 타입 안전성
- **Tailwind CSS** - 유틸리티 기반 스타일링
- **Lambda Web Adapter** - 컨테이너 → Lambda 변환

### Infrastructure
- **AWS Lambda** - 서버리스 컴퓨팅
- **API Gateway** - HTTP API 관리
- **CloudFront** - CDN
- **RDS PostgreSQL** - 관계형 데이터베이스
- **Cognito** - 사용자 인증
- **Amazon Bedrock** - AI 모델 (Nova)
- **CloudWatch** - 로그 및 모니터링
- **Terraform** - Infrastructure as Code

### DevOps
- **Docker** - 컨테이너화
- **ECR** - 컨테이너 레지스트리
- **GitHub Actions** - CI/CD (optional)
- **AWS CLI** - 배포 자동화

## 🚀 빠른 시작

### 1. 로컬 개발 환경 설정

```bash
# Python 런타임 설치 (mise 사용)
mise install

# 의존성 설치 (uv 사용)
uv sync --extra dev

# 환경변수 설정
cp .env.example .env
# .env 파일을 열어 필요한 값들을 설정하세요

# 로컬 PostgreSQL 시작
docker compose up -d postgres

# 데이터베이스 마이그레이션
uv run alembic upgrade head

# 시드 데이터 입력
uv run python -m app.seed.seed_mock_data
```

### 2. 로컬 서버 실행

```bash
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

서버가 시작되면 다음 URL에서 확인할 수 있습니다:
- API: http://127.0.0.1:8000/v1/health
- API 문서: http://127.0.0.1:8000/docs

### 3. 테스트 실행

```bash
# 전체 테스트
uv run pytest

# 특정 테스트만
uv run pytest tests/test_api.py

# 커버리지 포함
uv run pytest --cov=app
```

## ☁️ AWS 배포

### 아키텍처 개요

```
사용자
  ↓
CloudFront (CDN)
  ↓
Lambda Function URL
  ↓
Lambda + Web Adapter ──→ Next.js (Frontend)
                      ──→ FastAPI (Backend)
  ↓
RDS PostgreSQL
```

### Lambda Web Adapter의 장점

| 항목 | 기존 (ECS) | Lambda Web Adapter |
|------|-----------|-------------------|
| 💰 **고정 비용** | ~$30/월 | $0/월 |
| 📈 **스케일링** | 수동 설정 | 자동 (무제한) |
| ⚡ **Cold Start** | 없음 | 3-5초 |
| 🔧 **유지보수** | 복잡 | 간단 |
| 💵 **트래픽 비용** | 고정 | 사용량 기반 |

**결론**: 월 10만 페이지뷰 이하에서 약 70% 비용 절감!

### 배포 가이드

자세한 배포 방법은 다음 문서를 참고하세요:
- 📘 [프론트엔드 Lambda 배포 가이드](./docs/FRONTEND_LAMBDA_DEPLOYMENT.md)
- 📗 [Lambda Web Adapter 마이그레이션](./docs/LAMBDA_WEB_ADAPTER_MIGRATION.md)

### 빠른 배포 (Windows)

```powershell
# 1. ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | `
  docker login --username AWS --password-stdin `
  560271561793.dkr.ecr.ap-northeast-2.amazonaws.com

# 2. Docker 이미지 빌드 및 푸시
cd ../camp-fe
docker build -f ../camp-be/Dockerfile.frontend-lambda `
  -t stockbrief-dev-frontend:latest .
docker tag stockbrief-dev-frontend:latest `
  560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest
docker push `
  560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest

# 3. Terraform 배포
cd ../camp-be/infra/terraform/envs/dev
terraform init -backend-config=../../backends/dev.hcl
terraform apply

# 4. CloudFront URL 확인
terraform output frontend_hosted_url
```

## 📡 API 엔드포인트

### Public Endpoints
- `GET /v1/health` - 헬스 체크
- `GET /v1/meta/service-policy` - 서비스 정책

### Recommendation API
- `GET /v1/recommendations/candidates` - 추천 종목 목록
- `GET /v1/recommendations/candidates/{ticker}` - 종목 상세 정보
- `GET /v1/stocks/candidates` - 추천 종목 목록 (alias)

### Chat API
- `POST /v1/chat` - AI 채팅 (Amazon Bedrock Nova)

### User API (인증 필요)
- `GET /v1/me` - 내 정보 조회
- `PATCH /v1/me` - 내 정보 수정
- `GET /v1/me/watchlist` - 관심 종목 조회
- `POST /v1/me/watchlist` - 관심 종목 추가
- `POST /v1/me/watchlist/import` - 관심 종목 일괄 등록

### API 문서

로컬 서버 실행 후:
- **Swagger UI**: http://127.0.0.1:8000/docs
- **ReDoc**: http://127.0.0.1:8000/redoc

## 🧪 테스트

```bash
# 전체 테스트
uv run pytest

# 특정 테스트 파일
uv run pytest tests/test_api.py

# 카테고리별 테스트
uv run pytest tests/test_api_contract_snapshot.py      # API 계약
uv run pytest tests/test_recommendation_score_engine.py # 추천 엔진
uv run pytest tests/test_chat_api.py                    # AI 채팅
uv run pytest tests/test_external_adapters.py           # 외부 API

# 커버리지 리포트
uv run pytest --cov=app --cov-report=html
```

## 🗄️ 데이터베이스

```bash
# 마이그레이션 적용
uv run alembic upgrade head

# 마이그레이션 롤백
uv run alembic downgrade -1

# 새 마이그레이션 생성
uv run alembic revision --autogenerate -m "description"

# 시드 데이터 입력
uv run python -m app.seed.seed_mock_data
```

## 📊 모니터링

### CloudWatch Logs

```bash
# Lambda 로그 확인
aws logs tail /aws/lambda/stockbrief-dev-api --follow
aws logs tail /aws/lambda/stockbrief-dev-frontend-lambda --follow

# 특정 기간 로그
aws logs filter-log-events \
  --log-group-name /aws/lambda/stockbrief-dev-api \
  --start-time 1609459200000
```

### Lambda 메트릭

AWS Console → Lambda → 함수 선택 → Monitoring

주요 메트릭:
- **Invocations**: 호출 횟수
- **Duration**: 실행 시간
- **Errors**: 에러 발생률
- **Throttles**: 제한 발생
- **Concurrent Executions**: 동시 실행 수

## 💰 비용 예상 (월 기준)

### 시나리오별 비용

| 트래픽 | Lambda | CloudFront | RDS (t4g.micro) | 총 비용 |
|--------|--------|------------|-----------------|--------|
| 1만 PV | $0.17 | $0.86 | $12.50 | **$13.53** |
| 10만 PV | $1.67 | $8.63 | $12.50 | **$22.80** |
| 100만 PV | $16.67 | $86.25 | $12.50 | **$115.42** |

> 💡 **참고**: ECS 방식은 트래픽 무관하게 최소 $42/월 (ECS + RDS)

### 비용 최적화 팁

1. **Lambda 메모리**: 2048MB → 1024MB로 줄이면 비용 50% 절감 (성능 저하)
2. **RDS**: Aurora Serverless v2로 전환하면 트래픽 없을 때 자동 스케일 다운
3. **CloudFront**: 캐싱 전략 최적화로 Lambda 호출 감소
4. **예약 용량**: 안정적인 트래픽이 생기면 Savings Plans 활용

## 🛠️ 개발 가이드

### 코드 스타일

```bash
# 린팅
uv run ruff check app/

# 포맷팅
uv run ruff format app/

# 타입 체크
uv run mypy app/
```

### 커밋 컨벤션

```
feat: 새로운 기능 추가
fix: 버그 수정
docs: 문서 수정
test: 테스트 코드 추가/수정
refactor: 코드 리팩토링
chore: 기타 변경사항
```

### 브랜치 전략

```
main                    # 프로덕션 배포
  └── feat/feature-name  # 기능 개발
  └── fix/bug-name       # 버그 수정
  └── docs/doc-name      # 문서 작업
```

## 📚 학습 자료

### 공식 문서
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [AWS Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Amazon Bedrock User Guide](https://docs.aws.amazon.com/bedrock/)

### 관련 블로그
- [Lambda Web Adapter로 컨테이너 앱 서버리스로 전환하기](https://aws.amazon.com/ko/blogs/compute/)
- [Terraform으로 AWS 인프라 관리하기](https://developer.hashicorp.com/terraform/tutorials/aws-get-started)

## 🤝 기여 및 문의

이 프로젝트는 개인 학습 목적으로 개발되었습니다.

질문이나 제안사항이 있으시면 이슈를 등록해주세요!

## 📄 라이선스

MIT License

## 🙏 감사의 말

이 프로젝트는 다음 오픈소스 프로젝트들을 참고했습니다:
- FastAPI
- Next.js
- AWS Lambda Web Adapter
- Terraform AWS Modules

---

⭐ 이 프로젝트가 도움이 되었다면 Star를 눌러주세요!
