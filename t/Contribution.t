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

use Test::More tests => 1;
use Test::MockModule;

use List::MoreUtils qw(any);

use Koha::Database;

use t::lib::TestBuilder;

use Koha::Plugin::Com::Theke::INNReach;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

my $central_server = 'd2ir';

subtest 'filter_items_by_contributable() tests' => sub {

    plan tests => 5;

    $schema->storage->txn_begin;

    my $contribution_enabled = 0;

    my $mock_p = Test::MockModule->new('Koha::Plugin::Com::Theke::INNReach');

    # disable hooks to avoid noise
    $mock_p->mock( 'after_biblio_action', undef );
    $mock_p->mock( 'after_item_action',   undef );
    $mock_p->mock(
        'configuration',
        sub {
            my ($self) = @_;
            return {
                $central_server => {
                    contribution => {
                        enabled        => $contribution_enabled,
                        included_items => { ccode => [ 'a', 'b', 'c' ] },
                        excluded_items => { ccode => [ 'c', 'd', 'e' ] },
                    }
                }
            };
        }
    );

    my @item_ids;
    foreach my $ccode (qw(a b c d e)) {
        my $item = $builder->build_sample_item( { ccode => $ccode, itype => 'BK' } );
        push( @item_ids, $item->id );
    }

    my $items = Koha::Items->search( { itemnumber => \@item_ids } );

    is( $items->count, 5, 'Count is correct' );

    my $c = Koha::Plugin::Com::Theke::INNReach->new->contribution($central_server);
    is( $c->filter_items_by_contributable( { items => $items } )->count, 0, 'Contribution disabled, empty resultset' );

    $contribution_enabled = 1;

    # configuration is retrieved on Contribution object initialization
    $c = Koha::Plugin::Com::Theke::INNReach->new->contribution($central_server);

    is( $c->filter_items_by_contributable( { items => $items } )->count, 2, 'Contribution enabled, 2 items' );

    my $filtered_items = $c->filter_items_by_contributable( { items => $items } );

    while ( my $item = $filtered_items->next ) {
        ok( ( any { $item->ccode eq $_ } qw(a b) ), "ccode either 'a' or 'b' ($item->ccode)" );
    }

    $schema->storage->txn_rollback;
};
