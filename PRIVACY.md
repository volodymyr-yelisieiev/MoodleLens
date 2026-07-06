# Privacy Policy for MoodleLens

## Introduction

This Privacy Policy explains how MoodleLens ("the Application") handles your data. The Application is designed with privacy in mind and operates primarily on your local device.

## Data Collection and Usage

### What We Collect

The Application collects and processes the following data:

1. **OpenAI API Key**: Stored locally in macOS Keychain when the OpenAI API provider is used.
2. **Screenshots**: Temporarily stored on your device during the analysis process.
3. **User Settings**: Preferences like AI provider selection and custom AI context instructions.
4. **Conversation History**: Chat messages between you and the AI assistant during your session.
5. **AI Provider Selection**: Stored locally in app preferences.

### How We Use Your Data

- **OpenAI API Key**: Used exclusively to authenticate requests to OpenAI's API services.
- **Codex CLI Session**: When selected, MoodleLens runs the local `codex` executable and uses Codex's own authentication state. MoodleLens does not read, parse, copy, or store Codex OAuth tokens.
- **Screenshots**: Used only for local processing and analysis through the selected AI provider.
- **User Settings**: Used to customize the application experience.
- **Conversation History**: Used to maintain context during your session. History is not preserved between application restarts unless explicitly saved by you.

### Data Sharing

The Application does not share your data with any third parties except:

- **OpenAI**: When you use the OpenAI API provider, the necessary data (text and screenshots) is transmitted to OpenAI for processing according to their [privacy policy](https://openai.com/privacy).
- **Codex CLI**: When you use the Codex CLI provider, text prompts and optional screenshot images are passed to `codex exec --ephemeral --sandbox read-only` for processing by your authenticated Codex session.

## Data Storage

All data collected by the Application is stored locally on your device, with the exception of:

- Data sent to OpenAI for processing, which is subject to OpenAI's data retention policies.

Local storage locations:

- **OpenAI API key**: macOS Keychain, under the app's internal bundle-id service.
- **Codex authentication**: Managed by Codex CLI. MoodleLens does not store or inspect Codex OAuth tokens.
- **Settings**: App preferences/UserDefaults for non-secret settings such as provider selection and custom context prompts.
- **Temporary screenshots**: macOS temporary directory, in an app-specific folder.
- **Conversation history**: In memory only for the current app session.

## Your Rights

As the Application operates locally on your device, you have complete control over your data:

- You can delete temporary files created by the Application.
- You can press **⌥C** to clear Ask history and local temporary artifacts.
- You can reset your settings at any time.
- You can choose not to provide your OpenAI API key, though this will limit functionality.

## Security

We take reasonable measures to protect your data:

- Your OpenAI API key is stored in macOS Keychain.
- Codex OAuth tokens are not read or stored by MoodleLens.
- Temporary screenshot files are deleted after successful analysis, after errors, on app quit, and when clearing local data.
- Console logging is intended to avoid API keys, Authorization headers, base64 image data, raw prompts, and response dumps.
- The Application does not transmit any data except through the selected OpenAI-backed provider when needed for processing.
- No analytics or telemetry data is collected.

## Changes to This Policy

We may update this Privacy Policy from time to time. Changes will be reflected in the application's repository.

## Contact

For privacy questions, use the support path provided with your shared build.

Last updated: June 28, 2026
