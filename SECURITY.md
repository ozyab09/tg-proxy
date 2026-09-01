# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |
| < latest | :x:                |

Only the latest version receives security updates.

## Reporting a Vulnerability

If you discover a security vulnerability, please follow these steps:

### 1. Do NOT open a public issue

Security vulnerabilities should be reported privately.

### 2. Contact the maintainers

Send an email to the repository owner with:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### 3. Response timeline

- **Acknowledgment**: within 48 hours
- **Initial assessment**: within 1 week
- **Fix release**: depends on severity

## Security Measures

### Infrastructure

- Firewall blocks ports 2398/8888 externally (MTProxy internal only)
- TLS encryption via Let's Encrypt certificates
- Secrets stored in `.env` (chmod 600) and `config/profiles.json` (chmod 0400)
- Relay accepts connections only from loopback interface

### CI/CD

- Trivy scanning for Docker image vulnerabilities
- ShellCheck for shell script security issues
- Private key detection in pre-commit hooks
- Dependabot for automated dependency updates

### Best Practices

- Never log URI/query parameters (contain bridge capabilities)
- Never log WebSocket headers (contain bearer tokens)
- Use `access_log off` on nginx
- Rotate MTProxy secret periodically
- Monitor health endpoints for anomalies

## Scope

This security policy applies to:

- The tg-proxy deployment scripts
- Docker images published to Docker Hub
- GitHub Actions workflows

It does NOT apply to:

- The upstream tproxy-server (report to [telegramdesktop/tproxy-server](https://github.com/telegramdesktop/tproxy-server))
- The upstream MTProxy (report to [TelegramMessenger/MTProxy](https://github.com/TelegramMessenger/MTProxy))
