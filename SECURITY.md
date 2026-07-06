# Security Policy

## Reporting a Vulnerability

Please do not open public issues for security-sensitive reports, API keys, private screenshots, prompts, signing material, or OAuth details.

Email the maintainer or use GitHub private vulnerability reporting if it is enabled for this repository. Include the affected version, macOS version, reproduction steps, and the smallest safe evidence needed to understand the issue.

## Supported Versions

Only the latest public release is supported for security fixes.

## Secret Handling

MoodleLens release signing material, Sparkle private keys, OpenAI keys, Codex OAuth state, Apple notarization credentials, and GitHub tokens must never be committed. Use macOS Keychain locally and GitHub Actions secrets for CI release credentials.
