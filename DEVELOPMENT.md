# INNReach ILL Plugin - Development Guide

Comprehensive development documentation for the INNReach ILL plugin, including setup, testing, and architecture notes.

## Code Quality Standards

### Testing Standards

**Test File Organization:**
- Database-dependent tests for `a_method` in class `Some::Class` go in `t/db_dependent/Some/Class.t`
- Main subtest titled `'a_method() tests'` contains all tests for that method
- Inner subtests have descriptive titles for specific behaviors being tested

**Test File Structure:**
```perl
use Modern::Perl;
use Test::More tests => N;  # N = number of main subtests + use_ok
use Test::Exception;
use Test::MockModule;

use t::lib::TestBuilder;

BEGIN {
    use_ok('Some::Class');
}

# Global variables for entire test file
my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'a_method() tests' => sub {
    plan tests => 3;  # Number of individual tests
    
    $schema->storage->txn_begin;
    
    # Test implementation - all tests for this method
    
    $schema->storage->txn_rollback;
};

# OR if multiple behaviors need testing:

subtest 'a_method() tests' => sub {
    plan tests => 2;  # Number of inner subtests
    
    subtest 'Successful operations' => sub {
        plan tests => 3;  # Number of individual tests
        
        $schema->storage->txn_begin;
        
        # Test implementation
        
        $schema->storage->txn_rollback;
    };
    
    subtest 'Error conditions' => sub {
        plan tests => 2;
        
        $schema->storage->txn_begin;
        
        # Error test implementation
        
        $schema->storage->txn_rollback;
    };
};
```

**Transaction Rules:**
- Main subtest must be wrapped in transaction if only one behavior tested
- Each inner subtest wrapped in transaction if multiple behaviors tested
- Never nest transactions

**Global Variables:**
- `$schema`: Database schema object (global to test file)
- `$builder`: TestBuilder instance (global to test file)

**Transaction Management:**
- Always use `$schema->storage->txn_begin` at start of subtest
- Always use `$schema->storage->txn_rollback` at end of subtest

### Mandatory Pre-Commit Workflow

**CRITICAL**: All code must be formatted with Koha's tidy.pl before committing.

#### Required Steps Before Every Commit:

1. **Format code with Koha tidy.pl**:
   ```bash
   ktd --name innreach --shell --run "cd /kohadevbox/plugins/innreach-ill && /kohadevbox/koha/misc/devel/tidy.pl [modified_files...]"
   ```

2. **Remove all .bak files**:
   ```bash
   find . -name "*.bak" -delete
   ```

3. **Run tests to ensure formatting didn't break anything**:
   ```bash
   ktd --name innreach --shell --run "cd /kohadevbox/plugins/innreach-ill && export PERL5LIB=/kohadevbox/koha:/kohadevbox/plugins/innreach-ill:. && prove -lr t/"
   ```

4. **Commit with clean, formatted code**:
   ```bash
   git add .
   git commit -m "Your commit message"
   ```

#### Standard Commit Sequence:

```bash
# 1. Make your code changes
# ... edit files ...

# 2. Format with Koha tidy.pl
ktd --name innreach --shell --run "cd /kohadevbox/plugins/innreach-ill && /kohadevbox/koha/misc/devel/tidy.pl Koha/Plugin/Com/Theke/INNReach.pm"

# 3. Clean up backup files
find . -name "*.bak" -delete

# 4. Verify tests still pass
ktd --name innreach --shell --run "cd /kohadevbox/plugins/innreach-ill && export PERL5LIB=/kohadevbox/koha:/kohadevbox/plugins/innreach-ill:. && prove -lr t/"

# 5. Commit
git add .
git commit -m "[#XX] Your descriptive commit message"
```

#### Benefits of This Workflow:

- ✅ **Consistent formatting**: All code follows Koha standards
- ✅ **Clean commits**: No backup file pollution in git history
- ✅ **Professional quality**: Matches Koha project standards
- ✅ **Maintainable codebase**: Uniform style across all files
- ✅ **Easy reviews**: Reviewers focus on logic, not formatting

#### Configuration:

The repository includes `.perltidyrc` copied from Koha's main repository to ensure consistent formatting standards.

## Known Issues and Workarounds

### ILL Request Status Setting (Bug #40682)

**Issue**: Koha's ILL request status handling has a design flaw where the `->status()` method performs an implicit `->store()` call, making it impossible to set both data fields and status in a single database transaction.

**Upstream Bug**: https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=40682

**Problem**: When you need to update both data fields and status on an ILL request, you cannot do:
```perl
# ❌ WRONG - This doesn't work as expected
$req->set({
    biblio_id => $biblio_id,
    status    => 'NEW_STATUS'  # This gets ignored!
})->store();
```

**Current Workaround**: Always use separate calls for data and status:
```perl
# ✅ CORRECT - Separate data and status setting
$req->set({
    biblio_id => $biblio_id,
    due_date  => $due_date,
    # ... other data fields
});

$req->status('NEW_STATUS')->store();  # Explicit store() for future-proofing
```

**Note**: We explicitly call `->store()` after `->status()` even though `->status()` currently does an implicit store. This ensures the code will continue to work correctly if/when the upstream bug is fixed and `->status()` no longer performs the implicit store operation.

## Testing Infrastructure

### Contribution Filter Methods Testing

The plugin includes comprehensive tests for contribution filtering methods that handle item inclusion/exclusion rules.

**Key Test Areas:**
- `filter_items_by_contributable()` - Items eligible for contribution
- `filter_items_by_to_be_decontributed()` - Items that should be removed from contribution

**Using t::lib::Mocks::INNReach:**
```perl
use t::lib::Mocks::INNReach;

# Create test objects for plugin configuration
my $library  = $builder->build_object({ class => 'Koha::Libraries' });
my $category = $builder->build_object({ class => 'Koha::Patron::Categories' });
my $itemtype = $builder->build_object({ class => 'Koha::ItemTypes' });

# Create plugin with default test configuration
my $plugin = t::lib::Mocks::INNReach->new({
    library  => $library,
    category => $category,
    itemtype => $itemtype
});

# Create plugin with custom configuration override
my $plugin_custom = t::lib::Mocks::INNReach->new({
    library  => $library,
    category => $category,
    itemtype => $itemtype,
    config   => {
        'd2ir' => {
            contribution => {
                enabled        => 0,
                included_items => { ccode => ['x', 'y'] },
                excluded_items => undef,  # Remove from defaults
            }
        }
    }
});

# Use the plugin for testing
my $c = $plugin->contribution($central_server);
my $filtered_items = $c->filter_items_by_contributable( { items => $items } );
```

**Configuration Override Features:**
- **Merging**: Custom config is merged with defaults, not replaced
- **Deep merge**: Hash values are merged recursively
- **Deletion**: Set values to `undef` to remove keys from defaults
- **Extensible**: Can override any configuration parameter

**Test Pattern for Filter Methods:**
```perl
# Create test items with different characteristics
my @item_ids;
foreach my $ccode (qw(a b c d e f)) {
    my $item = $builder->build_sample_item( { ccode => $ccode, itype => 'BK' } );
    push( @item_ids, $item->id );
}

my $items = Koha::Items->search( { itemnumber => \@item_ids } );

# Mock plugin configuration for specific test scenarios
my $mock_p = Test::MockModule->new('Koha::Plugin::Com::Theke::INNReach');
$mock_p->mock(
    'configuration',
    sub {
        return {
            $central_server => {
                contribution => {
                    enabled        => 1,
                    included_items => { ccode => [ 'a', 'b', 'c' ] },
                    excluded_items => { ccode => [ 'c', 'd', 'e' ] },
                }
            }
        };
    }
);

# Test the filtering logic
my $c = $plugin->contribution($central_server);
my $filtered_items = $c->filter_items_by_contributable( { items => $items } );

# Verify results
is( $filtered_items->count, 2, 'Returns correct number of items' );
```

### Running Tests

```bash
# In KTD environment
ktd --name innreach --shell --run "cd /kohadevbox/plugins/innreach-ill && export PERL5LIB=/kohadevbox/koha:/kohadevbox/plugins/innreach-ill:. && prove -v t/db_dependent/Contribution.t"
```

## Quick Start

### KTD Setup
```bash
# Required environment variables
export KTD_HOME=/path/to/koha-testing-docker
export PLUGINS_DIR=/path/to/plugins/parent/dir
export SYNC_REPO=/path/to/kohaclone

# Launch KTD with plugins
ktd --name innreach --plugins up -d
ktd --name innreach --wait-ready 120

# Install plugin
ktd --name innreach --shell --run "cd /kohadevbox/koha && perl misc/devel/install_plugins.pl"
```

## Standard Testing

### Unit and Integration Tests

The plugin includes comprehensive test coverage across multiple areas:

#### Test Suite Overview

**Unit Tests (t/):**
- **`t/00-load.t`** - Basic module loading tests
- **`t/INNReach.t`** - Main plugin functionality tests
- **`t/Contribution.t`** - Contribution filtering tests
- **`t/BackgroundJobWorker.t`** - Background job processing tests
- **`t/lib_Mocks_INNReach.t`** - t::lib::Mocks::INNReach mock module tests

**Database-Dependent Tests (t/db_dependent/):**
- **`t/db_dependent/Contribution.t`** - Comprehensive contribution filter method tests

#### Running Tests

```bash
# Get into KTD shell
ktd --name innreach --shell

# Inside KTD, set up environment and run tests
cd /kohadevbox/plugins/innreach-ill
export PERL5LIB=$PERL5LIB:/kohadevbox/plugins/innreach-ill:.

# Run all tests
prove -v t/ t/db_dependent/

# Run specific test categories
prove -v t/                    # Unit tests only
prove -v t/db_dependent/       # Database-dependent tests only

# Run individual tests
prove -v t/Contribution.t
prove -v t/db_dependent/Contribution.t
```

#### Test Coverage Areas

**Contribution Filtering:**
- Item inclusion/exclusion rule evaluation
- Combined rule processing (both included_items and excluded_items)
- Contribution enabled/disabled states
- Force-enabled functionality
- Parameter validation and error handling

**Database Operations:**
- Plugin configuration storage and retrieval
- Item filtering with complex search criteria
- Transaction isolation and cleanup

**Business Logic:**
- Central server validation
- Contribution rule processing
- Item eligibility determination

## Key Architecture Points

### Contribution System

The contribution system handles which items are eligible for sharing via INNReach based on configurable rules.

#### Filter Method Alignment

**Recent Change**: The `filter_items_by_to_be_decontributed` method was aligned with `filter_items_by_contributable` to evaluate both `excluded_items` and `included_items` rules together, rather than using an if/else structure.

**Before (problematic):**
```perl
if ( exists $configuration->{contribution}->{included_items} ) {
    # Allow-list case, overrides any deny-list setup
    if ( $configuration->{contribution}->{included_items} ) {
        $items = $items->search( { '-not' => $configuration->{contribution}->{included_items} } );
    }
} else {
    # Deny-list case
    if ( $configuration->{contribution}->{excluded_items} ) {
        $items = $items->search( $configuration->{contribution}->{excluded_items} );
    } else {
        $items = $items->empty;
    }
}
```

**After (aligned):**
```perl
if ( exists $configuration->{contribution}->{included_items}
    && $configuration->{contribution}->{included_items} )
{
    # there are rules!
    $items = $items->search( { '-not' => $configuration->{contribution}->{included_items} } );
}

if ( exists $configuration->{contribution}->{excluded_items}
    && $configuration->{contribution}->{excluded_items} )
{
    # there are rules!
    $items = $items->search( $configuration->{contribution}->{excluded_items} );
}
```

**Benefits of Alignment:**
- **Consistent Logic**: Both methods now evaluate rules the same way
- **Combined Rules**: Both inclusion and exclusion rules are applied together
- **Predictable Behavior**: Same rule evaluation pattern across all filter methods
- **Maintainable Code**: Single pattern to understand and maintain

### Configuration System
- YAML config stored in plugin database via `store_data()`/`retrieve_data()`
- `configuration()` method applies defaults and transformations
- Configuration is cached - use `{ recreate => 1 }` to force reload

### Testing Patterns
- **Database-dependent tests**: Use transaction isolation (`txn_begin`/`txn_rollback`)
- **Test counting**: Each `subtest` = 1 test (not internal test count)
- **Naming**: Class-based (`INNReach.t` for main class) or feature-based (`Contribution.t`)
- **Structure**: Method-based subtests (`filter_items_by_contributable() tests`)
- **Mocking**: Use `Test::MockModule` for plugin configuration and external dependencies

## Common Issues & Solutions

### KTD Environment
- **`/.env: No such file or directory`**: Set `KTD_HOME` environment variable
- **Plugin not found**: Check `PLUGINS_DIR` points to parent directory
- **Module loading**: Ensure `PERL5LIB` includes plugin directory

### Testing
- **Test plan errors**: Count subtests, not internal tests
- **Database isolation**: Always use transactions in db_dependent tests
- **Mock warnings**: Use `Test::MockModule` and mock all called methods
- **Configuration mocking**: Mock the `configuration()` method to return test data

### CI/CD
- **GitHub Actions**: No `--proxy` flag needed, separate `up -d` and `--wait-ready`
- **Environment setup**: Use `$GITHUB_PATH` not sudo for PATH modification

## File Structure

```
Koha/Plugin/Com/Theke/INNReach/
├── INNReach.pm                     # Main plugin class
├── Contribution.pm                 # Contribution filtering logic
├── templates/                      # Plugin templates
└── ...                            # Other business logic

t/
├── 00-load.t                      # Module loading tests
├── INNReach.t                     # Main plugin tests
├── Contribution.t                 # Basic contribution tests
├── BackgroundJobWorker.t          # Background job tests
├── lib_Mocks_INNReach.t          # Mock module tests
├── lib/
│   └── Mocks/
│       └── INNReach.pm           # Mock plugin for testing
└── db_dependent/
    └── Contribution.t                 # Comprehensive filter method tests
```

## Development Workflow

```bash
# Get into KTD shell
ktd --name innreach --shell

# Inside KTD:
cd /kohadevbox/koha && perl misc/devel/install_plugins.pl  # Reinstall plugin
cd /kohadevbox/plugins/innreach-ill                        # Go to plugin dir
export PERL5LIB=$PERL5LIB:/kohadevbox/plugins/innreach-ill:.
prove -v t/ t/db_dependent/                                # Run tests
```

## Packaging Notes

- **Packaging**: Handled by gulpfile (only copies `Koha/` directory)
- **Releases**: Only triggered by version tags (`v*.*.*`)
- **CI**: Tests run on every push, packaging only on tags
