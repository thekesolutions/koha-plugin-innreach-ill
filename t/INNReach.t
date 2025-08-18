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
use Test::MockModule;

use Koha::Database;

use t::lib::TestBuilder;

use Koha::Plugin::Com::Theke::INNReach;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'borrowing_commands() tests' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    my $plugin = Koha::Plugin::Com::Theke::INNReach->new;

    # Test that borrowing_commands method exists
    can_ok( $plugin, 'borrowing_commands' );

    # Test that borrowing_commands returns the correct object
    my $borrowing_commands = $plugin->borrowing_commands;
    isa_ok(
        $borrowing_commands, 'INNReach::Commands::BorrowingSite',
        'borrowing_commands returns BorrowingSite object'
    );

    # Test that the command object has the plugin reference
    is( $borrowing_commands->{plugin}, $plugin, 'Command object has correct plugin reference' );

    # Test that command object has expected methods
    can_ok( $borrowing_commands, 'item_received', 'cancel_request', 'item_in_transit', 'final_checkin' );

    $schema->storage->txn_rollback;
};

subtest 'owning_commands() tests' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    my $plugin = Koha::Plugin::Com::Theke::INNReach->new;

    # Test that owning_commands method exists
    can_ok( $plugin, 'owning_commands' );

    # Test that owning_commands returns the correct object
    my $owning_commands = $plugin->owning_commands;
    isa_ok( $owning_commands, 'INNReach::Commands::OwningSite', 'owning_commands returns OwningSite object' );

    # Test that the command object has the plugin reference
    is( $owning_commands->{plugin}, $plugin, 'Command object has correct plugin reference' );

    # Test that command object has expected methods
    can_ok( $owning_commands, 'cancel_request', 'final_checkin', 'item_shipped' );

    $schema->storage->txn_rollback;
};
