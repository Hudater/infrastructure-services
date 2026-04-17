# local-ai-stack: used to waste electricity

## General chat

```bash
docker exec -it ai-ollama ollama pull qwen2.5:7b
docker exec -it ai-ollama ollama pull mistral:7b
```

## Reasoning

```bash
docker exec -it ai-ollama ollama pull deepseek-r1:7b
```

## Coding

```bash
docker exec -it ai-ollama ollama pull qwen2.5-coder:7b
```

## Explicitly quantized (Q4 — kam VRAM, thoda quality tradeoff)

```bash
docker exec -it ai-ollama ollama pull qwen2.5:14b-instruct-q4_K_M
docker exec -it ai-ollama ollama pull deepseek-r1:14b-qwen-distill-q4_K_M
```

## Embedding (RAG ke liye, almost no VRAM)

```bash
docker exec -it ai-ollama ollama pull nomic-embed-text
```

## Misc

```bash
docker exec -it ai-ollama ollama pull hf.co/unsloth/Qwen3.5-9B-GGUF:Q4_K_M
```

## Meta

```bash
docker exec -it ai-ollama ollama pull llama3.2:3b
docker exec -it ai-ollama ollama pull llama3.1:8b-instruct-q4_K_M
```

## Google

```bash
docker exec -it ai-ollama ollama pull gemma3:4b
docker exec -it ai-ollama ollama pull gemma3:12b-it-q4_K_M
```

## Sabse recommended tere liye

```bash
docker exec -it ai-ollama ollama pull gemma4:e4b
```

## Ya specific quantized agar available ho

```bash
docker exec -it ai-ollama ollama pull gemma4:e4b-q4_K_M
```

## Super light version

```bash
docker exec -it ai-ollama ollama pull gemma4:e2b
```

```bash
docker exec -it ai-ollama ollama pull gemma4:26b-a4b-it-q4_K_M
```

