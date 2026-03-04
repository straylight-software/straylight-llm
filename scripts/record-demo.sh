#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                     // straylight-llm recorded demo //
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Records a demo of straylight-llm with wf-recorder
#
# Usage: ./scripts/record-demo.sh
#
# Output: demo-YYYYMMDD-HHMMSS.mp4 in project root
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FILE="$PROJECT_DIR/demo-$(date +%Y%m%d-%H%M%S).mp4"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}                    // Recording straylight-llm Demo //${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Output: $OUTPUT_FILE${NC}"
echo -e "${YELLOW}Recording starts in 3 seconds...${NC}"
sleep 3

# Start wf-recorder in background
wf-recorder -f "$OUTPUT_FILE" &
RECORDER_PID=$!
sleep 1

# Run the demo
cd "$PROJECT_DIR"

# Start server
echo -e "${GREEN}Starting server with io_uring...${NC}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}" USE_URING=1 \
	./gateway/dist-newstyle/build/x86_64-linux/ghc-9.12.2/straylight-llm-0.1.0.0/x/straylight-llm/build/straylight-llm/straylight-llm &
SERVER_PID=$!
sleep 4

clear
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}                         // straylight-llm //${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  OpenAI-compatible LLM gateway with:"
echo "    • io_uring backend (evring-wai)"
echo "    • Provider fallback chain"
echo "    • Discharge proofs (ed25519)"
echo "    • Effect tracking (GatewayM)"
echo ""
sleep 3

# Health check
echo -e "${GREEN}▶ Health Check${NC}"
curl -s http://localhost:8080/health | jq '.'
sleep 2

# Demo 1
echo ""
echo -e "${GREEN}▶ Demo 1: Fast Model (google/gemini-2.5-flash-lite)${NC}"
echo "  Prompt: \"What is io_uring?\""
echo ""
START=$(date +%s%3N)
RESPONSE=$(curl -s -X POST http://localhost:8080/v1/chat/completions \
	-H "Content-Type: application/json" \
	-d '{
    "model": "google/gemini-2.5-flash-lite",
    "messages": [{"role": "user", "content": "What is io_uring? Answer in one sentence."}],
    "max_tokens": 50
  }')
END=$(date +%s%3N)
echo "  Response: $(echo "$RESPONSE" | jq -r '.choices[0].message.content')"
echo "  Latency: $((END - START))ms"
sleep 3

# Demo 2
echo ""
echo -e "${GREEN}▶ Demo 2: DeepSeek (cost-effective)${NC}"
echo "  Prompt: \"Explain monads simply.\""
echo ""
START=$(date +%s%3N)
RESPONSE=$(curl -s -X POST http://localhost:8080/v1/chat/completions \
	-H "Content-Type: application/json" \
	-d '{
    "model": "deepseek/deepseek-chat",
    "messages": [{"role": "user", "content": "Explain monads in one sentence."}],
    "max_tokens": 50
  }')
END=$(date +%s%3N)
echo "  Response: $(echo "$RESPONSE" | jq -r '.choices[0].message.content')"
echo "  Latency: $((END - START))ms"
sleep 3

# Benchmark
echo ""
echo -e "${GREEN}▶ Quick Benchmark (5 requests)${NC}"
TOTAL=0
for i in 1 2 3 4 5; do
	START=$(date +%s%3N)
	curl -s -X POST http://localhost:8080/v1/chat/completions \
		-H "Content-Type: application/json" \
		-d "{\"model\": \"google/gemini-2.5-flash-lite\", \"messages\": [{\"role\": \"user\", \"content\": \"$i\"}], \"max_tokens\": 5}" >/dev/null
	END=$(date +%s%3N)
	LATENCY=$((END - START))
	TOTAL=$((TOTAL + LATENCY))
	echo "  Request $i: ${LATENCY}ms"
done
echo "  ─────────────"
echo "  Average: $((TOTAL / 5))ms"
sleep 2

# Summary
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}                         // Demo Complete //${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  github.com/justinfleek/straylight-llm"
echo ""
sleep 3

# Cleanup
kill $SERVER_PID 2>/dev/null || true
sleep 1
kill $RECORDER_PID 2>/dev/null || true

echo ""
echo -e "${GREEN}Recording saved to: $OUTPUT_FILE${NC}"
