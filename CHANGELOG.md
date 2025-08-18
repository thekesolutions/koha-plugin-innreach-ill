# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [5.4.5] - 2025-08-18

### Fixed
- GitHub Actions workflow now runs bootstrap script before tests
- Enhanced bootstrap script to create necessary patron categories (ILLLIBS, ILL, LIBSTAFF, etc.)
- Resolved "categorycode=ILLLIBS does not exist" test failure
- Fixed test environment setup to match Rapido plugin approach
- Fixed bootstrap script to use relative path for config.yaml (resolves "No such file or directory" error)
- Fixed CI badge URL to point to correct repository (thekesolutions/koha-plugin-innreach-ill)

### Added
- Comprehensive patron category creation in bootstrap script
- GitHub Actions workflow guide for monitoring and troubleshooting

## [5.4.4] - 2025-08-18

### Added
- GitHub Actions CI/CD pipeline for automated testing and releases
- CI badge in README.md

### Changed
- Improved development workflow with automated testing

## [5.4.3] - Previous releases

See Git history for previous changes.
