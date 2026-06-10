# API Contract

## 1. Overview

StockBrief backend APIs provide a 근거 기반 국내 주식 종목 후보 추천 서비스 contract. Recommendation means `검토 후보 추천`, not trading advice.

- Backend canonical base path: `/v1`
- Next.js proxy base path: `/api/v1`
- Response format: JSON
- Ticker format: 6-digit Korean stock ticker string, for example `"005930"`
- Date format: ISO 8601 date or timestamp

Frontend code should call `/api/v1` when using Next.js proxy routes. Backend services and tests should use `/v1`.

## 2. Common Terms

| Term | Definition |
| --- | --- |
| `ticker` | 6-digit Korean stock ticker. |
| `recommendation` | Review candidate recommendation, not a trading instruction. |
| `score.total` | Deterministic total score from 0 to 100. |
| `score.components` | 8 component scores with fixed weights. |
| `evidence_level` | One of `strong`, `medium`, `weak`. |
| `missing_data` | Array of missing or stale data fields. Must be present. |
| `data_freshness` | Required object containing data basis dates. |
| `risk_tags` | Normalized risk labels such as `data_gap`, `high_volatility`, `sector_cycle`. |

## 3. Common Response Shapes

### Error Response

```json
{
  "error": {
    "code": "stock_not_found",
    "message": "Ticker was not found.",
    "details": {
      "ticker": "000000"
    }
  }
}
```

### Data Freshness

```json
{
  "as_of": "2026-06-09",
  "price_as_of": "2026-06-09",
  "financials_as_of": "2026-03-31",
  "disclosures_fetched_at": "2026-06-09T08:00:00Z",
  "news_fetched_at": "2026-06-09T08:30:00Z"
}
```

### Evidence Item

```json
{
  "evidence_id": "ev_20260609_005930_001",
  "ticker": "005930",
  "source_type": "disclosure",
  "source_name": "OpenDART",
  "source_url": "https://dart.fss.or.kr/example",
  "document_id": "doc_20260609_005930_001",
  "published_at": "2026-06-08T09:00:00Z",
  "fetched_at": "2026-06-09T08:00:00Z",
  "title": "분기보고서",
  "excerpt": "재무 안정성 판단에 사용된 공개 공시 요약입니다.",
  "evidence_type": "financial_stability",
  "confidence": 0.82
}
```

## 4. Endpoints

### Public vs Protected API Boundary

Public MVP endpoints remain available without authentication:

- `GET /v1/health`
- `GET /v1/meta/service-policy`
- `GET /v1/stocks/search`
- `GET /v1/recommendations/candidates`
- `GET /v1/recommendations/candidates/{ticker}`
- `GET /v1/stocks/{ticker}`
- `GET /v1/stocks/{ticker}/evidence`
- `GET /v1/stocks/{ticker}/score`
- `POST /v1/chat`

P1 account endpoints are protected by API Gateway HTTP API JWT authorizer. Backend code must identify the current user from Cognito JWT claims, especially `sub`, and must not trust `user_id` from request body, query parameters, or path parameters.

Protected endpoints:

- `GET /v1/me`
- `PATCH /v1/me`
- `GET /v1/me/preferences`
- `PUT /v1/me/preferences`
- `GET /v1/me/watchlist`
- `POST /v1/me/watchlist`
- `PATCH /v1/me/watchlist/{ticker}`
- `DELETE /v1/me/watchlist/{ticker}`
- `POST /v1/me/watchlist/import`
- `GET /v1/me/chat-sessions`
- `POST /v1/me/chat-sessions`

Protected request header:

```http
Authorization: Bearer <cognito-access-token>
```

In Lambda deployment, API Gateway validates the token and forwards claims to FastAPI through the Mangum event scope.

### GET /v1/health

Returns service health.

Response `200`:

```json
{
  "status": "ok",
  "service": "stockbrief-api",
  "version": "0.1.0",
  "time": "2026-06-09T09:00:00Z"
}
```

### GET /v1/stocks/search

Search stocks by ticker or company name.

Query parameters:

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| `q` | string | no | Ticker or Korean company name search text. Empty query returns the first page. |
| `market` | string | no | `KOSPI` or `KOSDAQ`. |
| `limit` | integer | no | Default `20`, max `50`. |

Response `200`:

```json
{
  "query": "삼성",
  "count": 1,
  "items": [
    {
      "ticker": "005930",
      "name": "삼성전자",
      "market": "KOSPI",
      "sector": "반도체",
      "industry": "전자부품 제조업"
    }
  ]
}
```

### GET /v1/recommendations/candidates

Returns recommendation candidates that pass the evidence gate.

Query parameters:

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| `risk_profile` | string | no | `conservative`, `balanced`, or `aggressive`. Default `balanced`. |
| `market` | string | no | `KOSPI` or `KOSDAQ`. |
| `sector` | string | no | Exact sector filter. |
| `limit` | integer | no | Default `10`, max `100`. |

Response `200`:

```json
{
  "items": [
    {
      "ticker": "005930",
      "name": "삼성전자",
      "market": "KOSPI",
      "sector": "반도체",
      "recommendation_score": 78.5,
      "score_components": [
        {
          "name": "financial_stability",
          "weight": 20,
          "raw_score": 82,
          "weighted_score": 16.4,
          "reason": "재무 안정성 항목은 공개 데이터 기준으로 계산했습니다.",
          "input_refs": ["financials.total_liabilities", "financials.total_equity"],
          "evidence_ids": ["ev_20260609_005930_001"]
        }
      ],
      "recommendation_reasons": [
        {
          "reason_id": "rsn_20260609_005930_001",
          "component": "financial_stability",
          "summary": "공개 데이터 기준 검토 포인트가 확인됩니다.",
          "evidence_ids": ["ev_20260609_005930_001"],
          "source_document_ids": ["doc_20260609_005930_001"]
        }
      ],
      "risk_tags": ["high_volatility", "sector_cycle"],
      "evidence_level": "strong",
      "evidence_count": 4,
      "missing_data": [],
      "data_freshness": {
        "as_of": "2026-06-09",
        "price_as_of": "2026-06-09",
        "financials_as_of": "2026-03-31",
        "disclosures_fetched_at": "2026-06-09T08:00:00Z",
        "news_fetched_at": "2026-06-09T08:30:00Z"
      },
      "disclaimer": "공개 데이터 기반 검토 후보이며 최종 투자 판단은 사용자에게 있습니다."
    }
  ],
  "count": 1,
  "risk_profile": "balanced",
  "disclaimer": "공개 데이터 기반 검토 후보이며 최종 투자 판단은 사용자에게 있습니다."
}
```

### GET /v1/recommendations/candidates/{ticker}

Returns full recommendation detail for one ticker.

Path parameters:

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| `ticker` | string | yes | 6-digit Korean stock ticker. |

Response `200`:

```json
{
  "ticker": "005930",
  "company_name": "삼성전자",
  "market": "KOSPI",
  "sector": "반도체",
  "is_candidate_eligible": true,
  "evidence_gate": {
    "passed": true,
    "checks": {
      "min_evidence_count": true,
      "min_risk_count": true,
      "has_data_basis_date": true,
      "has_missing_data_field": true
    },
    "fail_reasons": []
  },
  "score": {
    "total": 78.5,
    "evidence_level": "strong",
    "components": [
      {
        "name": "financial_stability",
        "weight": 20,
        "raw_score": 82,
        "weighted_score": 16.4,
        "reason": "부채비율과 유동성 지표가 기준 대비 양호합니다."
      },
      {
        "name": "profitability",
        "weight": 15,
        "raw_score": 76,
        "weighted_score": 11.4,
        "reason": "영업이익률이 최근 기준에서 안정적으로 확인됩니다."
      }
    ]
  },
  "reasons": [
    {
      "reason_id": "rsn_20260609_005930_001",
      "component": "financial_stability",
      "summary": "재무 안정성 지표가 기준 대비 양호합니다.",
      "evidence_ids": ["ev_20260609_005930_001"]
    }
  ],
  "evidence": [
    {
      "evidence_id": "ev_20260609_005930_001",
      "ticker": "005930",
      "source_type": "disclosure",
      "source_name": "OpenDART",
      "source_url": "https://dart.fss.or.kr/example",
      "document_id": "doc_20260609_005930_001",
      "published_at": "2026-06-08T09:00:00Z",
      "fetched_at": "2026-06-09T08:00:00Z",
      "title": "분기보고서",
      "excerpt": "재무 안정성 판단에 사용된 공개 공시 요약입니다.",
      "evidence_type": "financial_stability",
      "confidence": 0.82
    }
  ],
  "missing_data": [],
  "data_freshness": {
    "as_of": "2026-06-09",
    "price_as_of": "2026-06-09",
    "financials_as_of": "2026-03-31",
    "disclosures_fetched_at": "2026-06-09T08:00:00Z",
    "news_fetched_at": "2026-06-09T08:30:00Z"
  },
  "risk_tags": ["high_volatility", "sector_cycle"]
}
```

### GET /v1/stocks/{ticker}

Returns stock master and latest summary data.

Response `200`:

```json
{
  "ticker": "005930",
  "name": "삼성전자",
  "name_en": "Samsung Electronics",
  "market": "KOSPI",
  "sector": "반도체",
  "industry": "전자부품 제조업",
  "listing_date": "1975-06-11",
  "is_active": true,
  "identifiers": [
    {
      "provider": "OpenDART",
      "identifier_type": "corp_code",
      "identifier_value": "00126380",
      "is_primary": true
    }
  ]
}
```

### GET /v1/stocks/{ticker}/evidence

Returns evidence for one ticker.

Query parameters:

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| `types` | string | no | Comma-separated `financial`, `news`, `disclosure`, `price`. |
| `limit` | integer | no | Default `20`, max `100`. |

Response `200`:

```json
{
  "ticker": "005930",
  "evidence": [
    {
      "id": "ev_20260609_005930_001",
      "type": "disclosure",
      "title": "분기보고서",
      "summary": "공개 공시 형식의 mock 데이터에서 재무 안정성 검토 포인트가 확인됩니다.",
      "source_name": "OpenDART",
      "source_url": "https://dart.fss.or.kr/example",
      "source_identifier": "doc_20260609_005930_001",
      "published_at": "2026-06-08T09:00:00Z",
      "as_of_date": "2026-06-08",
      "data_status": "available"
    }
  ],
  "message": null
}
```

If evidence is insufficient for the requested filters:

```json
{
  "ticker": "005930",
  "evidence": [],
  "message": "요청한 조건에서 확인 가능한 근거 데이터가 충분하지 않습니다."
}
```

### GET /v1/stocks/{ticker}/score

Returns deterministic score detail for one ticker.

Response `200`:

```json
{
  "ticker": "005930",
  "as_of_date": "2026-06-09",
  "recommendation_score": 78.5,
  "score_components": [
    {
      "name": "financial_stability",
      "weight": 20,
      "raw_score": 82,
      "weighted_score": 16.4,
      "reason": "재무 안정성 항목은 공개 데이터 기준으로 계산했습니다.",
      "input_refs": ["financials.total_liabilities", "financials.total_equity"],
      "evidence_ids": ["ev_20260609_005930_001"]
    }
  ],
  "risk_tags": ["high_volatility"],
  "evidence_level": "strong",
  "evidence_count": 4,
  "missing_data": [],
  "data_freshness": {
    "as_of": "2026-06-09",
    "price_as_of": "2026-06-09",
    "financials_as_of": "2026-03-31"
  },
  "disclaimer": "공개 데이터 기반 검토 후보이며 최종 투자 판단은 사용자에게 있습니다."
}
```

### POST /v1/chat

Explains precomputed recommendation candidates and evidence. It must not produce trading advice or its own score.

Request body:

```json
{
  "session_id": "chat_20260609_001",
  "ticker": "005930",
  "message": "005930이 추천 후보에 포함된 이유를 설명해줘.",
  "title": "삼성전자 설명"
}
```

Response `200`:

```json
{
  "session_id": "chat_20260609_001",
  "message_id": "msg_20260609_002",
  "answer": "005930은 공개 데이터 기준으로 재무 안정성과 공시 근거가 확인되어 검토해볼 수 있습니다. 다만 업종 사이클과 변동성 리스크는 확인이 필요합니다.",
  "citations": [
    {
      "evidence_id": "ev_20260609_005930_001",
      "source_url": "https://dart.fss.or.kr/example",
      "title": "분기보고서"
    }
  ],
  "policy_status": "allowed",
  "used_evidence_ids": ["ev_20260609_005930_001"]
}
```

Refusal response example:

```json
{
  "session_id": "chat_20260609_001",
  "message_id": "msg_20260609_003",
  "answer": "StockBrief는 매매 판단이나 가격 기준을 제공하지 않습니다. 공개 데이터와 근거를 바탕으로 검토 후보에 포함된 이유만 설명할 수 있습니다.",
  "citations": [],
  "policy_status": "redirected",
  "used_evidence_ids": []
}
```

## 5. Evidence Gate Contract

Candidate list inclusion requires:

- `evidence_count >= 2`
- `risk_tags.length >= 1`
- `data_freshness.as_of` is present
- `missing_data` is present, even when empty

If any check fails, the ticker is excluded from `GET /v1/recommendations/candidates` and its detail response must show `is_candidate_eligible: false`.

## 6. Score Components

| Component | Weight |
| --- | ---: |
| `financial_stability` | 20 |
| `profitability` | 15 |
| `growth` | 15 |
| `valuation` | 10 |
| `news_attention` | 10 |
| `disclosure_event` | 10 |
| `liquidity` | 10 |
| `momentum_volatility` | 10 |

`score.total` is the sum of component weighted scores and must be rounded to one decimal place.

## 7. P1 Account API Examples

### GET /v1/me

Response `200`:

```json
{
  "id": "5d5b8c9f-4c44-4bbf-95fb-3a646d29b53d",
  "cognito_sub": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "email": "user@example.com",
  "email_verified": true,
  "nickname": "researcher"
}
```

### PUT /v1/me/preferences

Request:

```json
{
  "preferences": {
    "risk_profile": "balanced",
    "markets": ["KOSPI"],
    "sectors": ["반도체"]
  }
}
```

Response `200`:

```json
{
  "preferences": {
    "risk_profile": "balanced",
    "markets": ["KOSPI"],
    "sectors": ["반도체"]
  }
}
```

### POST /v1/me/watchlist/import

Used after Cognito login to migrate guest `localStorage` key `stockbrief_watchlist_v1`.

Client flow:

1. Read local `stockbrief_watchlist_v1`.
2. Call `GET /v1/me/watchlist`.
3. Remove duplicate tickers already present on the server.
4. Call `POST /v1/me/watchlist/import` with only missing items.
5. Write sync state to local `stockbrief_watchlist_v1_sync_state`.

Request:

```json
{
  "items": [
    {
      "ticker": "005930",
      "name": "삼성전자",
      "market": "KOSPI",
      "sector": "반도체",
      "memo": "공개 데이터 기준 검토 메모"
    }
  ]
}
```

### PATCH /v1/me/watchlist/{ticker}

Updates server-side watchlist metadata for the authenticated user. The backend identifies the user from Cognito claims and never from request body fields.

Request:

```json
{
  "memo": "공개 데이터 기준 추가 확인 메모"
}
```

Response `200`:

```json
{
  "ticker": "005930",
  "name": "삼성전자",
  "market": "KOSPI",
  "sector": "반도체",
  "memo": "공개 데이터 기준 추가 확인 메모",
  "saved_at": "2026-06-09T09:00:00Z"
}
```

### Authenticated POST /v1/chat Persistence

`POST /v1/chat` remains public. When called with a valid Cognito Bearer token, the backend stores both user and assistant messages in `chat_messages` and returns `session_id`/`message_id`.

Authenticated response additions:

```json
{
  "session_id": "chat_2a0d...",
  "message_id": "msg_f3c1...",
  "answer": "...",
  "citations": [],
  "policy_status": "allowed",
  "used_evidence_ids": []
}
```

Response `200`:

```json
{
  "imported_count": 1,
  "skipped_existing_count": 0,
  "items": [
    {
      "ticker": "005930",
      "name": "삼성전자",
      "market": "KOSPI",
      "sector": "반도체",
      "memo": "공개 데이터 기준 검토 메모",
      "saved_at": "2026-06-09T09:00:00Z"
    }
  ]
}
```
