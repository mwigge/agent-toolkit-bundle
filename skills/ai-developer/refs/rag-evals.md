# RAG Architecture & Evaluation Frameworks

Full patterns for retrieval-augmented generation (chunking, embeddings, vector stores, hybrid retrieval, reranking) and for building evaluation frameworks (deterministic checks, LLM-judge grading, datasets, regression tracking). The SKILL.md body keeps the quick-reference tables; this file holds the complete code and detail.

---

## RAG Architecture

### Chunking Strategies

| Strategy | Chunk size | Best for |
|----------|-----------|----------|
| Fixed-size | 512–1024 tokens with 10% overlap | Homogeneous text, quick iteration |
| Semantic (sentence boundary) | Variable ~200-800 tokens | Prose, articles |
| Hierarchical (parent/child) | Parent: 1024, Child: 128 | When both precision and context matter |
| Document structure | Section-based | Technical docs with headers |

**Rules**:
- Include chunk metadata in the embedded text: `[Source: {filename}, Section: {heading}]`
- Overlap 10–15% between adjacent fixed-size chunks to avoid splitting concepts
- Never chunk in the middle of code blocks or JSON

### Embedding Models

| Provider | Model | Dimensions | Notes |
|----------|-------|-----------|-------|
| OpenAI | `text-embedding-3-large` | 3072 | Best quality |
| OpenAI | `text-embedding-3-small` | 1536 | Cost-efficient |
| Cohere | `embed-english-v3.0` | 1024 | Strong for retrieval |
| Local | `nomic-embed-text` (Ollama) | 768 | No API cost |

Always normalise vectors before storage (most clients do this automatically).

### Vector Stores

| Store | Best for | Notes |
|-------|----------|-------|
| pgvector | Existing Postgres infra | `CREATE EXTENSION vector;` |
| Pinecone | Managed, high scale | Serverless tier for dev |
| Chroma | Local development | In-memory or persistent |
| Weaviate | Multi-modal, graph-linked | Self-hosted |

### Retrieval: Dense + Sparse Hybrid

```python
# Dense retrieval: semantic similarity (embedding cosine distance)
dense_results = vector_store.similarity_search(query_embedding, k=20)

# Sparse retrieval: keyword matching (BM25)
sparse_results = bm25_index.search(query_text, k=20)

# Reciprocal Rank Fusion (RRF) to merge results
def rrf_merge(dense: list, sparse: list, k: int = 60) -> list:
    scores: dict[str, float] = {}
    for rank, doc in enumerate(dense):
        scores[doc.id] = scores.get(doc.id, 0) + 1 / (k + rank + 1)
    for rank, doc in enumerate(sparse):
        scores[doc.id] = scores.get(doc.id, 0) + 1 / (k + rank + 1)
    return sorted(scores.items(), key=lambda x: x[1], reverse=True)
```

### Reranking

After hybrid retrieval, rerank the top-20 candidates to select the top-5 context chunks:

```python
# Cohere Rerank API
import cohere
co = cohere.Client(os.environ["COHERE_API_KEY"])
results = co.rerank(model="rerank-english-v3.0", query=query, documents=candidates, top_n=5)
```

Reranking reliably improves answer quality by 10–20% at the cost of one additional API call.

---

## Evals Framework

### Deterministic Evals

```python
def exact_match(actual: str, expected: str) -> bool:
    return actual.strip().lower() == expected.strip().lower()

def contains_match(actual: str, expected: str) -> bool:
    return expected.strip().lower() in actual.strip().lower()

def regex_match(actual: str, pattern: str) -> bool:
    import re
    return bool(re.search(pattern, actual, re.IGNORECASE))
```

Use for: classification outputs, structured extraction, JSON format validation.

### Model-Graded Evals (LLM Judge)

```python
JUDGE_PROMPT = """
You are an impartial evaluator. Rate the following response on a scale of 1-5.

Criteria:
- Factual accuracy (Does it match the reference?)
- Completeness (Does it cover the key points?)
- Conciseness (Is it appropriately brief?)

<reference>{expected}</reference>
<response>{actual}</response>

Respond with JSON: {{"score": <1-5>, "reasoning": "<one sentence>"}}
"""
```

Use 3+ different LLM judges and average scores to reduce individual model bias.

### Eval Dataset

```jsonl
{"id": "q001", "input": "What is idempotency?", "expected": "An operation that produces the same result regardless of how many times it is applied.", "tags": ["definitions"]}
{"id": "q002", "input": "List three NoSQL database types.", "expected": "document, key-value, column-family", "tags": ["databases"], "match_type": "contains"}
```

- Version your eval datasets alongside your code
- Minimum 100 examples for a meaningful eval set; 500+ for production confidence
- Include regression cases: every production bug should become an eval case

### Regression Tracking

Store eval results in a structured log:

```python
{
    "eval_run_id": "2026-04-05T06:00:00Z",
    "model": "claude-sonnet-4-5",
    "prompt_version": "v2.3",
    "total": 500,
    "exact_match_pass_rate": 0.87,
    "contains_match_pass_rate": 0.94,
    "mean_judge_score": 4.1,
    "p50_latency_ms": 420,
    "p99_latency_ms": 1850,
}
```

Alert if pass rate drops > 2% from the previous release.
