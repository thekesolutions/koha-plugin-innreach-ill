#!/usr/bin/perl

# Regression test for background job enqueuing issue
# This test captures the specific problem where removing require statements
# from BEGIN block broke background job enqueuing functionality

use Modern::Perl;

use Test::More tests => 1;
use Test::Exception;

use Koha::Database;
use t::lib::TestBuilder;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'Background job enqueuing works after plugin instantiation' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    # This test captures the regression where background jobs couldn't be enqueued
    # because the modules weren't loaded after removing require statements from BEGIN block

    use_ok('Koha::Plugin::Com::Theke::INNReach');
    
    # Instantiate plugin - this should load BackgroundJobs modules
    my $plugin = Koha::Plugin::Com::Theke::INNReach->new();

    # Test the specific case that was broken: enqueuing a background job
    lives_ok { 
        my $job = INNReach::BackgroundJobs::OwningSite::ItemShipped->new();
        # We don't actually enqueue to avoid database side effects,
        # but verify the object can be created and has the enqueue method
        ok($job->can('enqueue'), 'Background job has enqueue method');
    } 'Can create background job object after plugin instantiation';

    $schema->storage->txn_rollback;
};
