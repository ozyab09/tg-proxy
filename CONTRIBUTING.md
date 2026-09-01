# Contributing to tg-proxy

Thank you for your interest in contributing to tg-proxy!

## Getting Started

1. Fork the repository
2. Clone your fork with submodules:
   ```bash
   git clone --recursive https://github.com/<your-username>/tg-proxy.git
   cd tg-proxy
   ```
3. Install pre-commit hooks:
   ```bash
   pip install pre-commit
   pre-commit install --install-hooks
   ```

## Development Workflow

### Making Changes

1. Create a feature branch:
   ```bash
   git checkout -b feat/my-feature
   ```

2. Make your changes following the conventions below

3. Commit using [Conventional Commits](https://www.conventionalcommits.org/):
   ```bash
   git commit -m "feat: add new feature"
   git commit -m "fix: correct bug in install.sh"
   git commit -m "docs: update README"
   ```

4. Push and create a Pull Request:
   ```bash
   git push origin feat/my-feature
   ```

### Commit Message Format

We use [Conventional Commits](https://www.conventionalcommits.org/) for automatic versioning:

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

Types:
- `feat:` — new feature (triggers minor version bump)
- `fix:` — bug fix (triggers patch version bump)
- `docs:` — documentation only changes
- `style:` — code style changes (formatting, missing semi-colons, etc.)
- `refactor:` — code refactoring without functionality changes
- `test:` — adding or correcting tests
- `chore:` — build process or auxiliary tool changes
- `ci:` — CI configuration changes
- `perf:` — performance improvements

Breaking changes: add `!` after type or `BREAKING CHANGE:` in footer:
```
feat!: drop support for TLS 1.0
```

### Code Style

#### Shell Scripts
- Use `shellcheck` to validate scripts
- Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- Use `shellcheck -x -s bash <script>` to check

#### YAML
- Use `yamllint` to validate YAML files
- Max line length: 200 characters

#### Go (tproxy-server submodule)
- Follow standard Go conventions
- Run `go vet ./...` and `go test ./...` before committing

### Testing

#### Local Testing

```bash
# Lint shell scripts
shellcheck -x -s bash install.sh renew-cert.sh

# Lint YAML
yamllint docker-compose.yml .github/workflows/*.yml

# Test Docker builds
docker build -t tg-proxy-relay:test .
docker build -t tg-proxy-mtproto:test mtproxy/

# Smoke test relay
docker run --rm -u 0 tg-proxy-relay:test --help
```

#### CI Testing

All PRs automatically run:
- **Shellcheck** — validates shell scripts
- **Yamllint** — validates YAML syntax
- **Trivy** — scans Docker images for vulnerabilities
- **Conventional Commits** — validates commit message format

### Pre-commit Hooks

Install pre-commit to automatically check commits:

```bash
pip install pre-commit
pre-commit install --install-hooks
```

This will run:
- ShellCheck on shell scripts
- YAML linting
- Conventional commit message validation
- Trailing whitespace removal
- Private key detection

### Pull Request Guidelines

1. **One PR = One feature/fix** — keep PRs focused
2. **Write descriptive titles** — use conventional commit format
3. **Add tests** if applicable
4. **Update documentation** if adding new features
5. **Keep PRs small** — easier to review

### Review Process

1. All PRs require at least one review
2. CI must pass (lint, security scan, build)
3. Squash and merge to keep history clean

## Reporting Issues

### Bug Reports

Include:
- Steps to reproduce
- Expected behavior
- Actual behavior
- Environment (OS, Docker version, etc.)
- Logs (if applicable)

### Feature Requests

Include:
- Use case description
- Proposed solution
- Alternatives considered

## Security

If you discover a security vulnerability, please **do not** open a public issue.

Instead, please email security concerns to the maintainers directly.

See [SECURITY.md](SECURITY.md) for more information.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
