# Contributing to morbac_pg

Thank you for your interest in contributing to morbac_pg!

## How to Contribute

### Reporting Bugs

If you find a bug, please open an issue with:
- A clear description of the bug
- Steps to reproduce
- Expected vs actual behavior
- PostgreSQL version
- Relevant logs or error messages

### Suggesting Features

Feature requests are welcome! Please open an issue describing:
- The use case or problem you're trying to solve
- How the feature would work
- Whether it aligns with Multi-OrBAC model principles

### Code Contributions

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/my-feature`
3. **Make your changes**:
   - Follow the existing code style (SQL formatting, naming conventions)
   - Add tests in `test_morbac.sql` for new features
   - Update `DOCUMENTATION.md` if adding new functionality
4. **Test your changes**: `make test`
5. **Commit with clear messages**: `git commit -m "Add feature: description"`
6. **Push to your fork**: `git push origin feature/my-feature`
7. **Open a Pull Request** with a description of your changes

### Code Style Guidelines

- **SQL**: Use uppercase for keywords, lowercase for identifiers
- **Naming**: Use snake_case for tables, columns, functions
- **Schema**: All objects must be in the `morbac` schema
- **Comments**: Add comments for complex logic
- **Functions**: Include COMMENT ON statements for public functions

### Testing

All changes must include tests:
- Add test cases to `test_morbac.sql`
- Ensure all existing tests still pass
- Test against PostgreSQL 12+ (mention version in PR)

### Documentation

- Update `DOCUMENTATION.md` for API changes
- Update `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format
- Keep `README.md` simple (link to docs instead of expanding it)

## Development Setup

```bash
# Install PostgreSQL (if not already installed)
brew install postgresql  # macOS
# or use your package manager

# Clone your fork
git clone https://github.com/your-username/morbac_pg.git
cd morbac_pg

# Install the extension
make install

# Run tests
make test
```

## Questions?

Feel free to open an issue for questions or discussion.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
