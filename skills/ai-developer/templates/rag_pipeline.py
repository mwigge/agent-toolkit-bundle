"""
rag_pipeline.py — Production RAG pipeline template.

Responsibilities:
  1. chunk_document()  — Split a document into overlapping text chunks with metadata
  2. embed_chunks()    — Embed chunks via the OpenAI Embeddings API (or local Ollama)
  3. retrieve()        — Find the top-k most relevant chunks for a query
  4. generate()        — Produce a grounded answer using the retrieved context

Dependencies:
  - httpx         (HTTP client — pip install httpx)
  - Standard library: json, os, logging, math, hashlib, dataclasses, typing

Environment variables:
  OPENAI_API_KEY         — Required when using OpenAI embeddings/completions
  ANTHROPIC_API_KEY      — Required when using Anthropic completions
  EMBEDDING_MODEL        — Default: text-embedding-3-small
  COMPLETION_MODEL       — Default: claude-sonnet-4-5
  OLLAMA_BASE_URL        — Optional; enables local embedding fallback (default: http://localhost:11434)
  MAX_CHUNK_TOKENS       — Default: 512
  CHUNK_OVERLAP_TOKENS   — Default: 64
"""

from __future__ import annotations

import hashlib
import json
import logging
import math
import os
import time
from dataclasses import dataclass, field
from typing import Any

import httpx

# ── Logging ───────────────────────────────────────────────────────────────────
# Use structured logging; never log prompt content containing PII.
logging.basicConfig(
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    level=logging.INFO,
)
log = logging.getLogger("rag_pipeline")


# ── Configuration ─────────────────────────────────────────────────────────────

EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "text-embedding-3-small")
COMPLETION_MODEL = os.environ.get("COMPLETION_MODEL", "claude-sonnet-4-5")
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
MAX_CHUNK_TOKENS = int(os.environ.get("MAX_CHUNK_TOKENS", "512"))
CHUNK_OVERLAP_TOKENS = int(os.environ.get("CHUNK_OVERLAP_TOKENS", "64"))

# Approximate chars per token for English text
CHARS_PER_TOKEN = 4


# ── Data models ───────────────────────────────────────────────────────────────

@dataclass
class Chunk:
    chunk_id: str
    document_id: str
    text: str
    metadata: dict[str, Any]
    embedding: list[float] = field(default_factory=list)

    @classmethod
    def from_text(cls, text: str, document_id: str, chunk_index: int, metadata: dict[str, Any]) -> "Chunk":
        chunk_id = hashlib.sha256(f"{document_id}:{chunk_index}:{text[:64]}".encode()).hexdigest()[:16]
        return cls(
            chunk_id=chunk_id,
            document_id=document_id,
            text=text,
            metadata={**metadata, "chunk_index": chunk_index},
        )


@dataclass
class RetrievalResult:
    chunk: Chunk
    score: float


# ── In-memory vector store (replace with pgvector/Pinecone/Chroma in production) ──

class InMemoryVectorStore:
    """Minimal in-memory vector store using cosine similarity. Replace with a real store."""

    def __init__(self) -> None:
        self._chunks: list[Chunk] = []

    def upsert(self, chunks: list[Chunk]) -> None:
        existing_ids = {c.chunk_id for c in self._chunks}
        for chunk in chunks:
            if chunk.chunk_id in existing_ids:
                # Update in place
                for i, c in enumerate(self._chunks):
                    if c.chunk_id == chunk.chunk_id:
                        self._chunks[i] = chunk
                        break
            else:
                self._chunks.append(chunk)

    def search(self, query_embedding: list[float], top_k: int = 5) -> list[RetrievalResult]:
        if not self._chunks:
            return []

        scored = [
            RetrievalResult(
                chunk=chunk,
                score=cosine_similarity(query_embedding, chunk.embedding),
            )
            for chunk in self._chunks
            if chunk.embedding  # skip un-embedded chunks
        ]
        scored.sort(key=lambda r: r.score, reverse=True)
        return scored[:top_k]

    def __len__(self) -> int:
        return len(self._chunks)


def cosine_similarity(a: list[float], b: list[float]) -> float:
    if len(a) != len(b) or not a:
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(x * x for x in b))
    if norm_a == 0.0 or norm_b == 0.0:
        return 0.0
    return dot / (norm_a * norm_b)


# ── RAGPipeline ───────────────────────────────────────────────────────────────

class RAGPipeline:
    """
    Retrieval-Augmented Generation pipeline.

    Usage:
        pipeline = RAGPipeline()
        pipeline.index_document("doc-1", long_text, metadata={"source": "manual.pdf"})
        answer = pipeline.answer("What is the warranty period?")
    """

    def __init__(
        self,
        vector_store: InMemoryVectorStore | None = None,
        http_client: httpx.Client | None = None,
    ) -> None:
        self._store = vector_store or InMemoryVectorStore()
        self._http = http_client or httpx.Client(timeout=60.0)

    # ── Public API ────────────────────────────────────────────────────────────

    def index_document(
        self,
        document_id: str,
        text: str,
        metadata: dict[str, Any] | None = None,
    ) -> int:
        """Chunk, embed, and store a document. Returns the number of chunks created."""
        meta = metadata or {}
        chunks = self.chunk_document(text, document_id=document_id, metadata=meta)
        embedded = self.embed_chunks(chunks)
        self._store.upsert(embedded)
        log.info(
            "Indexed document",
            extra={"document_id": document_id, "chunks": len(embedded)},
        )
        return len(embedded)

    def answer(self, query: str, top_k: int = 5) -> str:
        """Retrieve relevant context and generate a grounded answer."""
        results = self.retrieve(query, top_k=top_k)
        context = "\n\n".join(
            f"[Source: {r.chunk.metadata.get('source', r.chunk.document_id)}, "
            f"chunk {r.chunk.metadata.get('chunk_index', '?')}]\n{r.chunk.text}"
            for r in results
        )
        return self.generate(query, context)

    # ── Chunking ──────────────────────────────────────────────────────────────

    def chunk_document(
        self,
        text: str,
        document_id: str = "doc",
        metadata: dict[str, Any] | None = None,
    ) -> list[Chunk]:
        """
        Split text into overlapping fixed-size chunks.

        Strategy: approximate token count via character count (4 chars ≈ 1 token).
        In production, replace with a tiktoken-based tokeniser for exact counts.
        """
        meta = metadata or {}
        max_chars = MAX_CHUNK_TOKENS * CHARS_PER_TOKEN
        overlap_chars = CHUNK_OVERLAP_TOKENS * CHARS_PER_TOKEN

        if len(text) <= max_chars:
            return [Chunk.from_text(text.strip(), document_id, 0, meta)]

        # Split on sentence boundaries where possible
        sentences = _split_sentences(text)
        chunks: list[Chunk] = []
        current_chars = 0
        current_sentences: list[str] = []
        chunk_index = 0

        for sentence in sentences:
            sentence_chars = len(sentence)

            if current_chars + sentence_chars > max_chars and current_sentences:
                # Emit current chunk
                chunk_text = " ".join(current_sentences).strip()
                if chunk_text:
                    chunks.append(Chunk.from_text(chunk_text, document_id, chunk_index, meta))
                    chunk_index += 1

                # Overlap: retain last N chars of the previous chunk
                overlap_text = chunk_text[-overlap_chars:] if len(chunk_text) > overlap_chars else chunk_text
                current_sentences = [overlap_text]
                current_chars = len(overlap_text)

            current_sentences.append(sentence)
            current_chars += sentence_chars

        # Emit final chunk
        if current_sentences:
            chunk_text = " ".join(current_sentences).strip()
            if chunk_text:
                chunks.append(Chunk.from_text(chunk_text, document_id, chunk_index, meta))

        log.debug("Chunked document", extra={"document_id": document_id, "chunks": len(chunks)})
        return chunks

    # ── Embedding ─────────────────────────────────────────────────────────────

    def embed_chunks(self, chunks: list[Chunk]) -> list[Chunk]:
        """
        Embed a list of chunks. Tries OpenAI first; falls back to Ollama if
        OPENAI_API_KEY is not set.
        """
        texts = [chunk.text for chunk in chunks]
        embeddings = self._embed_texts(texts)
        for chunk, embedding in zip(chunks, embeddings):
            chunk.embedding = embedding
        return chunks

    def _embed_texts(self, texts: list[str]) -> list[list[float]]:
        api_key = os.environ.get("OPENAI_API_KEY")
        if api_key:
            return self._openai_embed(texts, api_key)
        else:
            log.info("OPENAI_API_KEY not set — using Ollama for embeddings")
            return self._ollama_embed(texts)

    def _openai_embed(self, texts: list[str], api_key: str) -> list[list[float]]:
        # Batch in groups of 100 (OpenAI limit per request)
        results: list[list[float]] = []
        batch_size = 100
        for i in range(0, len(texts), batch_size):
            batch = texts[i : i + batch_size]
            response = self._http.post(
                "https://api.openai.com/v1/embeddings",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                content=json.dumps({"model": EMBEDDING_MODEL, "input": batch}),
            )
            response.raise_for_status()
            data = response.json()
            # Sort by index to maintain order (OpenAI may reorder)
            ordered = sorted(data["data"], key=lambda x: x["index"])
            results.extend(item["embedding"] for item in ordered)
            log.debug(
                "Embedded batch",
                extra={"batch_size": len(batch), "model": EMBEDDING_MODEL},
            )
        return results

    def _ollama_embed(self, texts: list[str]) -> list[list[float]]:
        results: list[list[float]] = []
        for text in texts:
            response = self._http.post(
                f"{OLLAMA_BASE_URL}/api/embeddings",
                content=json.dumps({"model": "nomic-embed-text", "prompt": text}),
                headers={"Content-Type": "application/json"},
            )
            response.raise_for_status()
            results.append(response.json()["embedding"])
        return results

    # ── Retrieval ─────────────────────────────────────────────────────────────

    def retrieve(self, query: str, top_k: int = 5) -> list[RetrievalResult]:
        """
        Embed the query and retrieve the top-k most similar chunks.
        In production, add BM25 sparse retrieval and RRF fusion here.
        """
        if len(self._store) == 0:
            log.warning("Vector store is empty — no documents indexed")
            return []

        query_embeddings = self._embed_texts([query])
        query_embedding = query_embeddings[0]

        results = self._store.search(query_embedding, top_k=top_k)

        log.info(
            "Retrieved chunks",
            extra={
                "query_hash": hashlib.sha256(query.encode()).hexdigest()[:8],
                "top_k": top_k,
                "results": len(results),
                "top_score": round(results[0].score, 4) if results else None,
            },
        )
        return results

    # ── Generation ────────────────────────────────────────────────────────────

    def generate(self, query: str, context: str) -> str:
        """
        Generate a grounded answer from the query and retrieved context.
        Uses Anthropic if ANTHROPIC_API_KEY is set, otherwise OpenAI.
        """
        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if api_key:
            return self._anthropic_generate(query, context, api_key)
        api_key = os.environ.get("OPENAI_API_KEY")
        if api_key:
            return self._openai_generate(query, context, api_key)
        raise EnvironmentError(
            "No LLM API key found. Set ANTHROPIC_API_KEY or OPENAI_API_KEY."
        )

    def _anthropic_generate(self, query: str, context: str, api_key: str) -> str:
        system = (
            "You are a precise assistant. Answer the question using ONLY the provided context. "
            "If the context does not contain the answer, say 'I don't have enough information to answer this.' "
            "Do not make up information. Cite the source label when quoting directly."
        )
        user_message = f"<context>\n{context}\n</context>\n\n<question>{query}</question>"

        response = self._http.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
            },
            content=json.dumps({
                "model": COMPLETION_MODEL,
                "max_tokens": 1024,
                "system": system,
                "messages": [{"role": "user", "content": user_message}],
            }),
        )
        response.raise_for_status()
        data = response.json()
        answer = data["content"][0]["text"]

        log.info(
            "Generated answer",
            extra={
                "model": COMPLETION_MODEL,
                "input_tokens": data.get("usage", {}).get("input_tokens"),
                "output_tokens": data.get("usage", {}).get("output_tokens"),
            },
        )
        return answer

    def _openai_generate(self, query: str, context: str, api_key: str) -> str:
        system = (
            "You are a precise assistant. Answer the question using ONLY the provided context. "
            "If the context does not contain the answer, say 'I don't have enough information to answer this.' "
            "Do not make up information."
        )
        user_message = f"Context:\n{context}\n\nQuestion: {query}"

        response = self._http.post(
            "https://api.openai.com/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            content=json.dumps({
                "model": "gpt-4o",
                "max_tokens": 1024,
                "temperature": 0.2,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": user_message},
                ],
            }),
        )
        response.raise_for_status()
        data = response.json()
        return data["choices"][0]["message"]["content"]

    def close(self) -> None:
        self._http.close()

    def __enter__(self) -> "RAGPipeline":
        return self

    def __exit__(self, *_: Any) -> None:
        self.close()


# ── Utilities ─────────────────────────────────────────────────────────────────

def _split_sentences(text: str) -> list[str]:
    """Naive sentence splitter. Replace with spaCy or NLTK in production."""
    import re
    sentences = re.split(r"(?<=[.!?])\s+", text)
    return [s.strip() for s in sentences if s.strip()]


# ── CLI demo ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import sys

    sample_doc = """
    Idempotency is a property of operations where applying the operation multiple times
    produces the same result as applying it once. In distributed systems, idempotency is
    critical for safe retries. For example, charging a credit card must be idempotent:
    retrying the same charge request should not result in double billing. This is typically
    achieved using an idempotency key — a unique identifier for each operation that the
    server uses to deduplicate repeated requests.

    Schema evolution refers to the process of changing the structure of a data schema
    over time while maintaining compatibility with existing data and consumers. Breaking
    changes include removing required fields or changing field types. Non-breaking changes
    include adding optional fields with default values.
    """

    print("RAG Pipeline Demo")
    print("=" * 50)

    with RAGPipeline() as pipeline:
        n = pipeline.index_document(
            document_id="demo-doc",
            text=sample_doc,
            metadata={"source": "demo.txt"},
        )
        print(f"Indexed {n} chunk(s).")

        query = "What is idempotency?"
        print(f"\nQuery: {query}")
        print("-" * 40)

        results = pipeline.retrieve(query, top_k=3)
        for i, r in enumerate(results):
            print(f"[{i+1}] score={r.score:.4f} chunk_id={r.chunk.chunk_id}")
            print(f"     {r.chunk.text[:120]}...")

        if os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("OPENAI_API_KEY"):
            answer = pipeline.answer(query)
            print(f"\nAnswer:\n{answer}")
        else:
            print("\n(Set ANTHROPIC_API_KEY or OPENAI_API_KEY to test generation)")
