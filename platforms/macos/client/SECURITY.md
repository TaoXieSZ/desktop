# Security Policy

## Reporting

Please do not open public issues for vulnerabilities, leaked credentials, signing problems, or hardware command risks.

Report security-sensitive issues privately to the project maintainers. If no private contact is published yet, open a minimal public issue that says you need a private security contact, without including exploit details.

## Sensitive Data

Never include these in issues, PRs, logs, screenshots, or commits:

- API keys
- Feishu/Lark app secrets
- Keychain values
- Apple signing certificates or provisioning profiles
- Private hardware identifiers
- Personal chat/contact data

## Local Permissions

The macOS app uses privacy-sensitive permissions such as Input Monitoring, Accessibility, Microphone, and Speech Recognition. Changes touching these flows should explain user impact and include manual test notes.
