#!/usr/bin/perl

# This file is part of the INNReach plugin
#
# The INNReach plugin is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# The INNReach plugin is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The INNReach plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 5;
use Test::MockModule;
use JSON qw( encode_json decode_json );

use Koha::Database;
use Koha::BackgroundJob;
use Koha::BackgroundJobs;

use Koha::Plugin::Com::Theke::INNReach;

my $schema = Koha::Database->new->schema;

=head1 NAME

t/BackgroundJobWorker.t - Test INNReach background job worker compatibility

=head1 DESCRIPTION

This test verifies that INNReach background jobs work correctly with Koha's
background job worker after removing eager loading of BackgroundJobs modules.

The test simulates the exact workflow that background_jobs_worker.pl follows
to ensure that plugin-defined background jobs can be discovered, instantiated,
and processed without issues.

=cut

subtest 'Background job discovery tests' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    # Test that INNReach background jobs are properly registered with Koha
    my $bg_job = Koha::BackgroundJob->new;
    my $plugin_mappings = $bg_job->plugin_types_to_classes;
    my @innreach_types = grep { /innreach/i } keys %$plugin_mappings;

    is( scalar(@innreach_types), 5, 'All 5 INNReach background job types discovered' );

    # Test each expected background job type
    my @expected_types = (
        'plugin_innreach_b_item_in_transit',
        'plugin_innreach_b_item_received',
        'plugin_innreach_o_cancel_request',
        'plugin_innreach_o_final_checkin',
        'plugin_innreach_o_item_shipped'
    );

    foreach my $expected_type (@expected_types) {
        ok( exists $plugin_mappings->{$expected_type}, 
            "Background job type $expected_type is registered with Koha" );
    }

    $schema->storage->txn_rollback;
};

subtest 'Background job worker simulation tests' => sub {

    plan tests => 5; # 5 job types

    $schema->storage->txn_begin;

    my $bg_job = Koha::BackgroundJob->new;
    my $plugin_mappings = $bg_job->plugin_types_to_classes;
    my @innreach_types = grep { /innreach/i } keys %$plugin_mappings;

    foreach my $job_type (@innreach_types) {
        my $class = $plugin_mappings->{$job_type};

        subtest "Worker simulation for $job_type" => sub {
            plan tests => 5;

            # Step 1: Create background job (simulating enqueue)
            my $job_data = {
                type => $job_type,
                status => 'new',
                queue => 'default',
                size => 1,
                data => encode_json({ ill_request_id => 123, test_mode => 1 }),
                context => encode_json({ interface => 'intranet' }),
                enqueued_on => '2024-01-01 12:00:00',
                borrowernumber => undef
            };

            my $job_rs = $schema->resultset('BackgroundJob')->create($job_data);
            my $job_id = $job_rs->id;

            ok( $job_id, "Background job created for $job_type" );

            # Step 2: Retrieve job (simulating worker finding job)
            my $job = Koha::BackgroundJobs->find($job_id);
            ok( $job, "Job retrieved from database" );
            is( $job->status, 'new', "Job has correct status" );

            # Step 3: Get derived class (critical step that worker performs)
            my $derived_class = eval { $job->_derived_class };
            ok( $derived_class, "_derived_class works without error" );
            isa_ok( $derived_class, $class, "Derived class is correct type" );

            # Note: We don't call process() to avoid side effects in tests
        };
    }

    $schema->storage->txn_rollback;
};

subtest 'New plugin methods usage tests' => sub {

    plan tests => 5;

    $schema->storage->txn_begin;

    my $bg_job = Koha::BackgroundJob->new;
    my $plugin_mappings = $bg_job->plugin_types_to_classes;
    my @innreach_types = grep { /innreach/i } keys %$plugin_mappings;

    foreach my $job_type (@innreach_types) {
        my $class = $plugin_mappings->{$job_type};
        my $class_file = $class;
        $class_file =~ s/::/\//g;
        $class_file .= '.pm';

        # Find the source file in the plugin lib directory
        my $source_path;
        foreach my $inc_path (@INC) {
            my $potential_path = "$inc_path/$class_file";
            if (-f $potential_path) {
                $source_path = $potential_path;
                last;
            }
        }

        SKIP: {
            skip "Source file not found for $class", 1 unless $source_path;

            open my $fh, '<', $source_path or skip "Cannot read $source_path", 1;
            my $content = do { local $/; <$fh> };
            close $fh;

            my $uses_new_methods = $content =~ /->(?:borrowing_commands|owning_commands)/;
            my $uses_old_methods = $content =~ /INNReach::Commands::(?:BorrowingSite|OwningSite)->new/;

            ok( $uses_new_methods && !$uses_old_methods,
                "$class uses new plugin methods (not old direct instantiation)" );
        }
    }

    $schema->storage->txn_rollback;
};

subtest 'No eager loading verification tests' => sub {

    plan tests => 2;

    $schema->storage->txn_begin;

    # Find the main plugin file
    my $plugin_file;
    foreach my $inc_path (@INC) {
        my $potential_path = "$inc_path/Koha/Plugin/Com/Theke/INNReach.pm";
        if (-f $potential_path) {
            $plugin_file = $potential_path;
            last;
        }
    }

    SKIP: {
        skip "Plugin file not found", 2 unless $plugin_file;

        open my $fh, '<', $plugin_file or skip "Cannot read plugin file", 2;
        my $content = do { local $/; <$fh> };
        close $fh;

        my $has_eager_loading = $content =~ /BEGIN\s*\{[^}]*require\s+INNReach::BackgroundJobs/s;
        ok( !$has_eager_loading, "No eager loading of BackgroundJobs in BEGIN block" );

        my $has_new_methods = $content =~ /sub\s+(?:borrowing_commands|owning_commands)/;
        ok( $has_new_methods, "Plugin has new borrowing_commands/owning_commands methods" );
    }

    $schema->storage->txn_rollback;
};

subtest 'End-to-end background job worker process tests' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    # Test complete worker process simulation
    my $test_type = 'plugin_innreach_b_item_in_transit';

    # Create job (simulating enqueue)
    my $job_data = {
        type => $test_type,
        status => 'new',
        queue => 'default',
        size => 1,
        data => encode_json({ ill_request_id => 999, end_to_end_test => 1 }),
        context => encode_json({ interface => 'intranet' }),
        enqueued_on => '2024-01-01 12:00:00',
        borrowernumber => undef
    };

    my $job_rs = $schema->resultset('BackgroundJob')->create($job_data);
    my $job = Koha::BackgroundJobs->find($job_rs->id);

    ok( $job, "End-to-end test job created" );

    # Simulate exact background_jobs_worker.pl process
    is( $job->status, 'new', "Job has correct initial status" );

    # Decode args (what worker does)
    my $args = eval { decode_json($job->data) };
    ok( $args, "Job data decoded successfully" );
    $args->{job_id} = $job->id;
    ok( $args->{job_id}, "Job ID added to args" );

    # Get derived class and verify process method (critical worker steps)
    my $derived_class = eval { $job->_derived_class };
    ok( $derived_class, "Derived class obtained successfully" );
    can_ok( $derived_class, 'process' );

    # At this point, the worker would call: $job->process($args)
    # We've verified all the prerequisites for successful processing

    $schema->storage->txn_rollback;
};

=head1 AUTHOR

This test verifies that the removal of eager loading of BackgroundJobs modules
from the INNReach plugin does not break background job functionality.

The test confirms that:
- All INNReach background jobs are discoverable by Koha
- Background job worker can instantiate plugin-defined jobs
- Jobs use new plugin methods (lazy loading) instead of direct instantiation
- No eager loading exists in the main plugin
- Complete worker process simulation works end-to-end

=cut
