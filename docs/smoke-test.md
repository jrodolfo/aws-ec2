# Smoke Test Checklist

## Bootstrap

□ Fresh Amazon Linux 2023
□ Bootstrap completed successfully

## Development Toolchain

Run `check-toolchain` and review the reported versions before checking the items below.

□ Java 21
□ Maven 3.9+
□ Node 24
□ Codex
□ GitHub CLI
□ Docker
□ Docker Compose
□ Trivy
□ Ollama (optional)

## Environment

□ AWS CLI login works

## Project Validation (optional)

□ Local GenAI Lab builds
□ Local GenAI Lab tests pass
□ Local GenAI Lab starts
□ Bedrock connectivity verified
