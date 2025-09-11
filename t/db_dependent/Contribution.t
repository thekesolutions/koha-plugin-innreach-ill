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
use Test::Exception;

use List::MoreUtils qw(any);

use Koha::Database;
use t::lib::TestBuilder;
use t::lib::Mocks::INNReach;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

my $central_server = 'd2ir';

subtest 'filter_items_by_contributable() tests' => sub {
    plan tests => 8;

    $schema->storage->txn_begin;

    # Create test objects for plugin configuration
    my $library  = $builder->build_object({ class => 'Koha::Libraries' });
    my $category = $builder->build_object({ class => 'Koha::Patron::Categories' });
    my $itemtype = $builder->build_object({ class => 'Koha::ItemTypes' });

    # Create plugin with test configuration
    my $plugin = t::lib::Mocks::INNReach->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype
    });

    # Create test items with different ccodes
    my @item_ids;
    foreach my $ccode (qw(a b c d e f)) {
        my $item = $builder->build_object({ 
            class => 'Koha::Items',
            value => { ccode => $ccode }
        });
        push( @item_ids, $item->id );
    }

    my $items = Koha::Items->search( { itemnumber => \@item_ids } );
    is( $items->count, 6, 'Created 6 test items' );

    my $c = $plugin->contribution($central_server);

    # Test with contribution enabled (default in mock)
    my $filtered_items = $c->filter_items_by_contributable( { items => $items } );
    is( $filtered_items->count, 2, 'Contribution enabled returns 2 items' );

    # Verify the correct items are returned (a,b - included but not excluded)
    my @returned_ccodes = map { $_->ccode } $filtered_items->as_list;
    @returned_ccodes = sort @returned_ccodes;
    is_deeply( \@returned_ccodes, ['a', 'b'], 'Returns items with ccode a,b (included but not excluded)' );

    # Test with contribution disabled
    my $plugin_disabled = t::lib::Mocks::INNReach->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype,
        config   => {
            $central_server => {
                contribution => {
                    enabled        => 0,
                    included_items => { ccode => [ 'a', 'b', 'c' ] },
                    excluded_items => { ccode => [ 'c', 'd', 'e' ] },
                }
            }
        }
    });
    $c = $plugin_disabled->contribution($central_server);
    is( $c->filter_items_by_contributable( { items => $items } )->count, 0, 
        'Contribution disabled returns empty resultset' );

    my $forced_items = $c->filter_items_by_contributable( { items => $items, force_enabled => 1 } );
    is( $forced_items->count, 2, 'Force enabled returns 2 items (a,b after applying both rules)' );

    # Test with only included_items rule
    my $plugin_included = t::lib::Mocks::INNReach->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype,
        config   => {
            $central_server => {
                contribution => {
                    enabled        => 1,
                    included_items => { ccode => [ 'a', 'b', 'c' ] },
                    excluded_items => undef,  # Remove excluded_items
                }
            }
        }
    });
    $c = $plugin_included->contribution($central_server);
    is( $c->filter_items_by_contributable( { items => $items } )->count, 3, 
        'Only included_items rule returns 3 items (a,b,c)' );

    # Test with only excluded_items rule
    my $plugin_excluded = t::lib::Mocks::INNReach->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype,
        config   => {
            $central_server => {
                contribution => {
                    enabled        => 1,
                    included_items => undef,  # Remove included_items
                    excluded_items => { ccode => [ 'c', 'd', 'e' ] },
                }
            }
        }
    });
    $c = $plugin_excluded->contribution($central_server);
    is( $c->filter_items_by_contributable( { items => $items } )->count, 3, 
        'Only excluded_items rule returns 3 items (a,b,f)' );

    # Test with no rules
    my $plugin_no_rules = t::lib::Mocks::INNReach->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype,
        config   => {
            $central_server => {
                contribution => {
                    enabled => 1,
                    included_items => undef,  # Remove included_items
                    excluded_items => undef,  # Remove excluded_items
                }
            }
        }
    });
    $c = $plugin_no_rules->contribution($central_server);
    is( $c->filter_items_by_contributable( { items => $items } )->count, 6, 
        'No filtering rules returns all items' );

    $schema->storage->txn_rollback;
};

subtest 'filter_items_by_to_be_decontributed() tests' => sub {
    plan tests => 7;

    $schema->storage->txn_begin;

    # Create test objects for plugin configuration
    my $library  = $builder->build_object({ class => 'Koha::Libraries' });
    my $category = $builder->build_object({ class => 'Koha::Patron::Categories' });
    my $itemtype = $builder->build_object({ class => 'Koha::ItemTypes' });

    # Create plugin with test configuration
    my $plugin = t::lib::Mocks::INNReach->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype
    });

    # Create test items and mark some as contributed
    my @item_ids;
    my @contributed_items;
    foreach my $ccode (qw(a b c d e f)) {
        my $item = $builder->build_object({ 
            class => 'Koha::Items',
            value => { ccode => $ccode }
        });
        push( @item_ids, $item->id );
        push( @contributed_items, $item ) if $ccode =~ /[abcde]/; # Mark a,b,c,d,e as contributed
    }

    # Mock the contributed items
    my $mock_contribution = Test::MockModule->new('Koha::Plugin::Com::Theke::INNReach::Contribution');
    $mock_contribution->mock(
        'filter_items_by_contributed',
        sub {
            my ( $self, $params ) = @_;
            my $items = $params->{items};
            my @contributed_ids = map { $_->id } @contributed_items;
            return $items->search( { itemnumber => \@contributed_ids } );
        }
    );

    my $items = Koha::Items->search( { itemnumber => \@item_ids } );
    is( $items->count, 6, 'Created 6 test items' );

    my $c = $plugin->contribution($central_server);

    # Test the main functionality - items that should be decontributed
    # These are contributed items that no longer match the contribution rules
    my $decontrib_items = $c->filter_items_by_to_be_decontributed( 
        { items => $items, central_server => $central_server } 
    );
    is( $decontrib_items->count, 2, 'Returns 2 items to be decontributed (d,e)' );

    # Verify the correct items are returned
    my @returned_ccodes = map { $_->ccode } $decontrib_items->as_list;
    @returned_ccodes = sort @returned_ccodes;
    is_deeply( \@returned_ccodes, ['d', 'e'], 
        'Returns items d,e (contributed but no longer matching rules)' );

    # Test with only included_items rule
    my $plugin_included = t::lib::Mocks::INNReach->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype,
        config   => {
            $central_server => {
                contribution => {
                    enabled        => 1,
                    included_items => { ccode => [ 'a', 'b' ] },
                    excluded_items => undef,  # Remove excluded_items
                }
            }
        }
    });
    $c = $plugin_included->contribution($central_server);
    my $decontrib_included = $c->filter_items_by_to_be_decontributed(
        { items => $items, central_server => $central_server }
    );
    is( $decontrib_included->count, 3, 
        'Only included_items: returns 3 items (c,d,e - not in included list)' );

    # Test with only excluded_items rule
    my $plugin_excluded = t::lib::Mocks::INNReach->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype,
        config   => {
            $central_server => {
                contribution => {
                    enabled        => 1,
                    included_items => undef,  # Remove included_items
                    excluded_items => { ccode => [ 'd', 'e' ] },
                }
            }
        }
    });
    $c = $plugin_excluded->contribution($central_server);
    my $decontrib_excluded = $c->filter_items_by_to_be_decontributed(
        { items => $items, central_server => $central_server }
    );
    is( $decontrib_excluded->count, 2, 
        'Only excluded_items: returns 2 items (d,e - in excluded list)' );

    # Test parameter validation
    throws_ok {
        $c->filter_items_by_to_be_decontributed( { items => $items } );
    } 'INNReach::Ill::MissingParameter', 'Throws exception when central_server missing';

    throws_ok {
        $c->filter_items_by_to_be_decontributed( { central_server => $central_server } );
    } 'INNReach::Ill::MissingParameter', 'Throws exception when items missing';

    $schema->storage->txn_rollback;
};
