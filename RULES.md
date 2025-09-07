# Voice Learning System - 테스트용 백엔드 기능 명세

## 📋 프로젝트 목적
데이터 구조 효율성 검증을 위한 최소 기능 구현 테스트

## 🗄️ 데이터베이스 구조

### 1. words 테이블 (단어 사전)
```sql
CREATE TABLE words (
    word_id INT PRIMARY KEY AUTO_INCREMENT,
    word: VARCHAR(50) NOT NULL,
    lemma VARCHAR(50) NOT NULL UNIQUE,
    word_type ENUM('noun', 'verb', 'adj', 'adv') NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

lemma에는 해당 단어의 원형이 들어감. 해당 단어가 원형이라면 그대로 들어감.

### 2. user_words 테이블 (사용자별 단어 사용 기록)
```sql
CREATE TABLE words_used (
    id INT,
    user_id BIGINT NOT NULL,
    history JSON,
);
```

### 3. user_word_count 테이블 (일별 통계)
```sql
CREATE TABLE user_counts (
    user_id BIGINT NOT NULL,
    date DATE NOT NULL,
    total_words INT DEFAULT 0,      -- 중복 포함 총 단어수
    unique_words INT DEFAULT 0,     -- 중복 제거 단어수  
);
```

## 🔧 API 설계

### 1. 단어 목록 전달 (POST)
```
POST /api/users/:user_id/words

Request Body:
{
  "words": ["running", "worked", "better", "hello", "running"]
}

Response:
{
  "success": true,
  "processed": {
    "total_words": 5,
    "unique_words": 4, 
    "new_words": 2
  },
  "top_words_with_duplicates": [
    {"word": "running", "count": 2},
    {"word": "worked", "count": 1},
    {"word": "better", "count": 1}
  ],
  "top_words_unique": [
    {"word": "running", "total_count": 15},
    {"word": "hello", "total_count": 8},
    {"word": "worked", "total_count": 3}
  ]
}
```

### 2. 기록 확인하기 (GET)
```
GET /api/users/:user_id/stats?days=5

Response:
{
  "user_id": 12345,
  "unique_history": [
    {
      "date": "2024-01-15",
      "unique_words": 23,
    },
    {
      "date": "2024-01-14", 
      "unique_words": 19,
    }
  ],
  "total_history": [
    {
      "date": "2024-01-15",
      "total_words": 45,
    },
    {
      "date": "2024-01-14", 
      "total_words": 38,
    }
  ]
}
```

## ⚙️ 핵심 처리 로직

### 1. 단어 처리 플로우
```
1. 입력 단어 배열 받기
2. Python 모듈 호출하여 원형 추출
3. words 테이블에서 원형 조회/생성
4. user_words 테이블에서 사용자 기록 조회/갱신  
5. 새로운 단어 개수 계산
6. user_daily_stats 테이블 업데이트
7. 결과 응답
```

### 2. Python 모듈 연동
```python
# lib/python/word_processor.py 
def process_words(words_array):
    return [
        {
            "original": "running",
            "lemma": "run", 
            "pos": "VERB"
        }
    ]
```

### 3. Ruby 서비스 클래스
```ruby
# app/services/word_processor.rb
class WordProcessor
  def process_user_words(user_id, words)
    # 1. Python 모듈 호출
    # 2. 단어 사전 조회/생성
    # 3. 사용자 기록 갱신
    # 4. 통계 계산
  end
end
```

## 테스트 해야하는 환경

- docker을 활용하여 mysql 및 redis 환경 구성
- redis에 word 정보가 올라가 비교 과정에서 이점을 취해야함.

## 🧪 테스트 시나리오

### 시나리오 1: 신규 사용자
- 입력: ["hello", "world", "running"]
- 예상: 모든 단어가 새로운 단어로 기록

### 시나리오 2: 기존 사용자 + 새 단어
- 입력: ["hello", "new", "word"]
- 예상: "hello"는 기존, "new", "word"는 신규

### 시나리오 3: 원형 변환 테스트
- 입력: ["running", "ran", "runs"]
- 예상: 모두 "run"으로 원형 변환되어 하나의 단어로 처리

## 📊 성능 목표
- 100개 단어 처리: < 500ms
- Python 모듈 응답: < 200ms
- DB 쿼리 응답: < 100ms

## 🔍 검증 포인트

1. **데이터 중복 방지**: 원형 기반 저장이 제대로 작동하는가?
2. **성능 효율성**: 배치 처리가 개별 처리보다 빠른가?
3. **정확성**: 새로운 단어 계산이 정확한가?
4. **확장성**: 사용자/단어 증가에 따른 성능 변화는?