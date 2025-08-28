# Contributing Guide

## Contributing to Enterprise EKS Cluster Automation Platform

We welcome contributions to this award-winning platform! This guide outlines the process for contributing to the project.

## Code of Conduct

By participating in this project, you agree to abide by our code of conduct:

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Maintain professional communication

## Getting Started

### Prerequisites
- Terraform >= 1.5.0
- AWS CLI >= 2.0
- kubectl >= 1.29
- Docker >= 20.10
- Python >= 3.9

### Development Environment Setup

1. **Fork and Clone**
```bash
git clone https://github.com/deepak-kumar-biswal/aws-platform-audit.git
cd aws-platform-audit/eks-cluster-creation-updation/eks-cluster-provisioning
```

2. **Install Dependencies**
```bash
# Install Python dependencies
pip install -r requirements-dev.txt

# Setup pre-commit hooks
pre-commit install

# Configure AWS credentials
aws configure
```

3. **Run Tests**
```bash
# Run unit tests
pytest tests/

# Run integration tests
./scripts/run-integration-tests.sh

# Run chaos engineering tests
python tests/test_chaos_engineering.py
```

## Development Workflow

### Branch Strategy
- `main` - Production-ready code
- `develop` - Integration branch for features
- `feature/*` - Feature development branches
- `hotfix/*` - Emergency fixes

### Making Changes

1. **Create Feature Branch**
```bash
git checkout -b feature/your-feature-name
```

2. **Make Changes**
- Write clean, documented code
- Follow existing code style
- Add tests for new functionality
- Update documentation as needed

3. **Test Changes**
```bash
# Run all tests
pytest tests/
terraform validate terraform/
checkov -f terraform/
```

4. **Commit Changes**
```bash
git add .
git commit -m "feat: add new cluster management feature"
```

5. **Push and Create PR**
```bash
git push origin feature/your-feature-name
```

## Contribution Types

### Bug Fixes
- Include detailed description of the issue
- Add test cases that reproduce the bug
- Ensure fix doesn't break existing functionality

### New Features
- Discuss major changes in issues first
- Include comprehensive tests
- Update documentation
- Consider backward compatibility

### Documentation
- Keep documentation up-to-date
- Include examples and use cases
- Ensure clarity and accuracy

### Performance Improvements
- Include benchmarks showing improvement
- Ensure changes don't break existing functionality
- Document any breaking changes

## Code Style Guidelines

### Terraform
- Use consistent formatting (`terraform fmt`)
- Include proper variable descriptions
- Use meaningful resource names
- Include tags on all resources

### Python
- Follow PEP 8 style guide
- Use type hints
- Include docstrings for functions and classes
- Keep functions focused and small

### Documentation
- Use clear, concise language
- Include code examples
- Keep README files up-to-date
- Use proper Markdown formatting

## Testing Requirements

### Required Tests
- Unit tests for all new functions
- Integration tests for major features
- Chaos engineering tests for resilience
- Security tests for vulnerabilities

### Test Coverage
- Maintain minimum 80% code coverage
- Include edge cases and error conditions
- Test both success and failure scenarios

## Review Process

### Pull Request Requirements
- Clear description of changes
- All tests passing
- Code review approval from maintainers
- Documentation updates included

### Review Criteria
- Code quality and style
- Test coverage and quality
- Documentation completeness
- Security considerations
- Performance impact

## Release Process

### Version Strategy
- Semantic versioning (MAJOR.MINOR.PATCH)
- Tag releases in Git
- Maintain changelog

### Release Checklist
- All tests passing
- Documentation updated
- Security scan passed
- Performance benchmarks met
- Breaking changes documented

## Getting Help

- **Issues**: Create GitHub issue for bugs or questions
- **Discussions**: Use GitHub Discussions for general questions
- **Email**: Contact maintainers for security issues
- **Documentation**: Check existing docs and guides

## Recognition

Contributors will be recognized in:
- Release notes
- Contributors section
- Project documentation
- Annual contributor awards

Thank you for contributing to this award-winning platform! 🏆
