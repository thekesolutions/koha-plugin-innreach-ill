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

use Test::More tests => 2;
use Test::Exception;

use Koha::Database;
use t::lib::TestBuilder;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'BackgroundJobs modules load after plugin instantiation' => sub {
    plan tests => 12;

    $schema->storage->txn_begin;

    # Test that plugin instantiation loads the BackgroundJobs modules
    use_ok('Koha::Plugin::Com::Theke::INNReach');
    
    my $plugin = Koha::Plugin::Com::Theke::INNReach->new();
    ok($plugin, 'Plugin instantiated successfully');

    # Test that all BackgroundJobs modules are now available
    my @job_classes = (
        'INNReach::BackgroundJobs::BorrowingSite::ItemInTransit',
        'INNReach::BackgroundJobs::BorrowingSite::ItemReceived', 
        'INNReach::BackgroundJobs::OwningSite::CancelRequest',
        'INNReach::BackgroundJobs::OwningSite::FinalCheckin',
        'INNReach::BackgroundJobs::OwningSite::ItemShipped'
    );

    foreach my $job_class (@job_classes) {
        lives_ok { 
            my $job = $job_class->new();
            ok($job->can('enqueue'), "$job_class has enqueue method");
        } "$job_class can be instantiated after plugin creation";
    }

    $schema->storage->txn_rollback;
};

subtest 'BackgroundJobs modules fail without plugin instantiation' => sub {
    plan tests => 5;

    $schema->storage->txn_begin;

    # Test that BackgroundJobs modules are NOT available without plugin instantiation
    # This simulates the broken state when modules weren't loaded
    
    my @job_classes = (
        'INNReach::BackgroundJobs::BorrowingSite::ItemInTransit',
        'INNReach::BackgroundJobs::BorrowingSite::ItemReceived', 
        'INNReach::BackgroundJobs::OwningSite::CancelRequest',
        'INNReach::BackgroundJobs::OwningSite::FinalCheckin',
        'INNReach::BackgroundJobs::OwningSite::ItemShipped'
    );

    # Clear any previously loaded modules to simulate fresh state
    foreach my $job_class (@job_classes) {
        delete $INC{$job_class . '.pm'};
        no strict 'refs';
        undef %{$job_class . '::'};
    }

    foreach my $job_class (@job_classes) {
        throws_ok { 
            my $job = $job_class->new();
        } qr/Can't locate object method "new" via package/, 
        "$job_class fails to instantiate without plugin loading modules";
    }

    $schema->storage->txn_rollback;
};
