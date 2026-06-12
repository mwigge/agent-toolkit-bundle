#!/usr/bin/env bash
# scripts/test-skill-rules.sh
# Sanity check for skill-rules.json: asserts a representative phrase for each
# skill matches that skill's activation pattern. Catches regex typos (e.g. a
# missing letter, a duplicated alternative) that would otherwise silently
# disable a skill's activation hint.
#
# Usage: scripts/test-skill-rules.sh

set -euo pipefail
cd "$(dirname "$0")/.."

RULES_FILE="skill-rules.json"
FAIL=0

declare -A SAMPLES=(
  [ai-developer]="anthropic api and embeddings"
  [api-designer]="rest api design with openapi"
  [caveman]="run /caveman"
  [chaos-engineer]="chaos engineering fault injection"
  [ci-cd]="github actions pipeline deployment"
  [codegraph]="codegraph call graph"
  [compliance]="gdpr compliance audit"
  [confluence]="confluence page"
  [data-analyst]="exploratory data analysis"
  [data-engineer]="data pipeline etl with airflow"
  [data-visualisation]="chart visualization with matplotlib"
  [database]="postgres sql migration schema"
  [docker-expert]="dockerfile and container compose"
  [documentation]="update the readme documentation"
  [golang]="golang goroutine and channel"
  [golang-patterns]="idiomatic go pattern"
  [iac-patterns]="terraform infrastructure as code"
  [incident-response]="incident postmortem runbook"
  [kubernetes-patterns]="kubernetes helm deployment yaml"
  [mempalace]="mempalace memory store"
  [microservices-architect]="microservice grpc proto"
  [multi-tenancy]="multi-tenant isolation"
  [nodejs]="nodejs express npm"
  [oauth]="oauth jwt authentication"
  [observability]="opentelemetry tracing span"
  [openspec-apply-change]="openspec change proposal"
  [pr-review]="pr review of this pull request"
  [presentation]="presentation slide deck"
  [product-owner]="product backlog user story sprint"
  [prompt-engineer]="system prompt design for chain-of-thought"
  [python]="python pytest fixture"
  [refactoring-specialist]="refactor and extract method"
  [rust]="rust cargo lifetime"
  [security-review]="security owasp vulnerability"
  [sre]="sre reliability slo error budget"
  [statistical-analysis]="statistical regression hypothesis test"
  [tdd-workflow]="tdd red green test"
  [time-series]="time series forecast"
  [typescript]="typescript react vite"
  [verification-loop]="verify with a smoke test"
  [web-design-guidelines]="css design system accessibility"
)

while IFS= read -r row; do
  skill=$(jq -r '.skill' <<<"$row")
  pattern=$(jq -r '.pattern' <<<"$row")
  sample="${SAMPLES[$skill]:-}"

  if [[ -z "$sample" ]]; then
    echo "NO SAMPLE PHRASE: $skill — add one to scripts/test-skill-rules.sh" >&2
    FAIL=1
    continue
  fi

  if ! grep -qiE "$pattern" <<<"$sample"; then
    echo "FAIL: '$sample' does not match $skill pattern: $pattern" >&2
    FAIL=1
  fi
done < <(jq -c '.[]' "$RULES_FILE")

if [[ "$FAIL" -eq 0 ]]; then
  echo "OK: all $(jq 'length' "$RULES_FILE") skill-rules patterns matched their sample phrase"
fi

exit "$FAIL"
