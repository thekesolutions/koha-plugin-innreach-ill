#!/usr/bin/env perl

# Copyright 2026 Theke Solutions
#
# This file is part of The INNReach plugin.
#
# The INNReach plugin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# The INNReach plugin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The INNReach plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 2;
use Test::MockModule;

use C4::Context;
use Koha::Database;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::INNReach;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'after_hold_action() tests' => sub {

    plan tests => 2;

    subtest 'Local hold set to waiting queues item modify for contributed items' => sub {

        plan tests => 3;

        $schema->storage->txn_begin;

        my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
        my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );

        my $plugin = t::lib::Mocks::INNReach->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype,
                config   => {
                    'd2ir' => {
                        local_to_central_itype => {
                            $itemtype->itemtype => 200,
                        },
                    },
                },
            }
        );

        my $item = $builder->build_sample_item(
            {
                library => $library->branchcode,
                itype   => $itemtype->itemtype,
                ccode   => 'a',
            }
        );

        # Mark item as contributed
        my $contributed_items = $plugin->get_qualified_table_name('contributed_items');
        C4::Context->dbh->do(
            qq{INSERT INTO $contributed_items (central_server, item_id) VALUES ('d2ir', ?)},
            undef, $item->itemnumber,
        );

        my $hold = $builder->build_object(
            {
                class => 'Koha::Holds',
                value => {
                    biblionumber   => $item->biblionumber,
                    itemnumber     => $item->itemnumber,
                    borrowernumber => $patron->borrowernumber,
                    branchcode     => $library->branchcode,
                    found          => 'W',
                },
            }
        );

        # Clear any tasks from setup
        my $task_queue = $plugin->get_qualified_table_name('task_queue');
        C4::Context->dbh->do(qq{DELETE FROM $task_queue});

        # Simulate the hold action hook
        $plugin->after_hold_action(
            {
                action  => 'fill',
                payload => { hold => $hold },
            }
        );

        # Check that an item modify task was queued
        my $tasks = C4::Context->dbh->selectall_arrayref(
            qq{SELECT object_type, object_id, action, status FROM $task_queue WHERE object_id = ? AND object_type = 'item'},
            { Slice => {} },
            $item->itemnumber,
        );

        is( scalar @$tasks, 1, 'An item task was queued for the contributed item' );
        is( $tasks->[0]->{action}, 'modify', 'Task action is modify' );
        is( $tasks->[0]->{status}, 'queued', 'Task status is queued' );

        $schema->storage->txn_rollback;
    };

    subtest 'Local hold set to waiting does NOT queue task for non-contributed items' => sub {

        plan tests => 1;

        $schema->storage->txn_begin;

        my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
        my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );

        my $plugin = t::lib::Mocks::INNReach->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype,
            }
        );

        my $item = $builder->build_sample_item(
            {
                library => $library->branchcode,
                itype   => $itemtype->itemtype,
                ccode   => 'a',
            }
        );

        # Item is NOT contributed

        my $hold = $builder->build_object(
            {
                class => 'Koha::Holds',
                value => {
                    biblionumber   => $item->biblionumber,
                    itemnumber     => $item->itemnumber,
                    borrowernumber => $patron->borrowernumber,
                    branchcode     => $library->branchcode,
                    found          => 'W',
                },
            }
        );

        my $task_queue = $plugin->get_qualified_table_name('task_queue');
        C4::Context->dbh->do(qq{DELETE FROM $task_queue});

        $plugin->after_hold_action(
            {
                action  => 'fill',
                payload => { hold => $hold },
            }
        );

        my ($count) = C4::Context->dbh->selectrow_array(
            qq{SELECT COUNT(*) FROM $task_queue WHERE object_id = ? AND object_type = 'item'},
            undef, $item->itemnumber,
        );

        is( $count, 0, 'No task queued for non-contributed item' );

        $schema->storage->txn_rollback;
    };
};

subtest 'item_circ_status() tests' => sub {

    plan tests => 1;

    subtest 'Item with waiting hold returns Not Available' => sub {

        plan tests => 2;

        $schema->storage->txn_begin;

        my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
        my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );

        my $plugin = t::lib::Mocks::INNReach->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype,
            }
        );

        my $item = $builder->build_sample_item(
            {
                library => $library->branchcode,
                itype   => $itemtype->itemtype,
            }
        );

        my $contribution = $plugin->contribution('d2ir');

        # No holds — should be Available
        my $status = $contribution->item_circ_status( { item => $item } );
        is( $status, 'Available', 'Item without holds is Available' );

        # Add a waiting hold
        $builder->build_object(
            {
                class => 'Koha::Holds',
                value => {
                    biblionumber   => $item->biblionumber,
                    itemnumber     => $item->itemnumber,
                    borrowernumber => $patron->borrowernumber,
                    branchcode     => $library->branchcode,
                    found          => 'W',
                },
            }
        );

        # Refresh the item to clear cached relationships
        $item = $item->get_from_storage;

        $status = $contribution->item_circ_status( { item => $item } );
        is( $status, 'Not Available', 'Item with waiting hold is Not Available' );

        $schema->storage->txn_rollback;
    };
};
