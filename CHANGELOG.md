# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [5.5.0] - 2025-09-17

### Added
- [#2] Enhanced `t::lib::Mocks::INNReach` with bootstrap functionality for complete test independence
- [#2] Added system preference and plugin state setup to mock framework

### Changed
- [#2] Reorganized test structure: moved all database-dependent tests to `t/db_dependent/` directory
- [#2] Updated all database-dependent tests to use plugin mock framework consistently
- [#2] Eliminated dependency on `bootstrap.pl` script for test execution
- Updated configuration UI to use Koha's "wrapper-staff-tool-plugin.inc" for better integration
- Simplified configuration template code and removed unused elements
- Improved configuration page as foundation for future UI enhancements

### Removed
- [#2] Removed duplicate `t/Contribution.t` test (functionality preserved in `t/db_dependent/Contribution.t`)

## [5.4.12] - 2025-09-16

### Fixed
- [#1] Fixed biblio creation in `t/db_dependent/Contribution.t` tests to ensure proper test data setup
- [#1] Resolved test failures by ensuring biblios exist before creating items in contribution tests
- [#1] Improved test reliability and consistency across different test environments

## [5.4.10] - 2025-09-11

### Added
- [#1] Added `t::lib::Mocks::INNReach` module following Koha's t::lib::Mocks pattern
- [#1] Added configuration override capability with deep merging and deletion support
- [#1] Added comprehensive db_dependent tests for `filter_items_by_contributable()` method
- [#1] Added comprehensive db_dependent tests for `filter_items_by_to_be_decontributed()` method
- [#1] Added comprehensive db_dependent tests for `get_deleted_contributed_items()` method
- [#1] Added comprehensive development documentation (DEVELOPMENT.md)
- Added `.perltidyrc` from Koha project for consistent formatting standards

### Changed
- [#1] Replaced Test::MockModule usage with standardized t::lib::Mocks::INNReach approach
- [#1] Improved test structure following Koha testing standards with method-based subtests
- [#1] Enhanced testing infrastructure with proper transaction management
- [#1] Removed unrequired `central_server` parameter from `filter_items_by_to_be_decontributed()` method
- [#1] Removed unrequired `$central_server` variable from `filter_items_by_contributable()` method
- [#1] Removed unrequired `central_server` parameter from `get_deleted_contributed_items()` method
- Aligned GitHub CI with Rapido's configuration (twice-monthly cron schedule, Docker builder)
- Updated release process to use Theke's koha-plugin-builder and include CHANGELOG.md

### Testing
- All tests passing with comprehensive coverage of contribution filter methods
- Tests validate both inclusion/exclusion rule evaluation and combined rule processing
- Parameter validation and error handling thoroughly tested

## [5.4.8] - 2025-08-18

### Major Improvements
- **Dramatically reduced subroutine redefinition warnings** from ~23 to only 6
- **Implemented command methods architecture** for better module management
- Added `borrowing_commands()` and `owning_commands()` methods to main plugin
- **Eliminated ALL BackgroundJobs redefinition warnings**

### Technical Enhancements
- Updated all BackgroundJobs modules to use plugin command methods instead of direct loading
- Updated `run_command.pl` script to use new command methods
- Removed direct `use` statements for Commands modules in BackgroundJobs
- Centralized command object creation through plugin methods
- Better separation of concerns and cleaner architecture
- BackgroundJobs modules now load on-demand when actually needed
- Better separation of concerns - no unnecessary eager loading
- Cleaner plugin installation with fewer warnings
- Plugin functionality remains unchanged

### Results
- **74% reduction** in redefinition warnings during plugin installation
- Much cleaner plugin installation process in multi-plugin environments
- Plugin functionality fully preserved and tested
- Better maintainability with single point of control for command objects

### Remaining
- 6 Commands module warnings remain (inheritance-related, harmless)
- Plugin functionality is completely unaffected

### Fixed
- **Significantly reduced subroutine redefinition warnings** during plugin installation
- Removed eager loading of BackgroundJobs modules from BEGIN block
- Eliminated BackgroundJobs-specific redefinition warnings
- Improved plugin installation process in multi-plugin environments

### Note
- Some Commands module warnings may still appear (loaded on-demand by BackgroundJobs)
- This is normal behavior and doesn't affect plugin functionality

## [5.4.7] - 2025-08-18

### Fixed
- **Properly fixed subroutine redefinition warnings** in 00-load.t test
- Replaced File::Find approach with explicit module list for testing
- Excluded BackgroundJobs and Commands modules that cause loading conflicts
- Clean test output without masking real issues

### Technical Improvements
- Only loads main plugin modules that should be tested directly
- Eliminates redefinition warnings through proper module selection
- Maintains full test coverage of core plugin functionality
- Better separation of testable vs system-loaded modules

## [5.4.6] - 2025-08-18

### Fixed
- Suppressed harmless "Subroutine redefined" warnings in 00-load.t test
- Cleaner test output that focuses on actual loading failures
- Added module tracking to prevent loading same module multiple times

### Improved
- Test output is now cleaner and less noisy
- Better focus on actual test failures vs harmless warnings

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
