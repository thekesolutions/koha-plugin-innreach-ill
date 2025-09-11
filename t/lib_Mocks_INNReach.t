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
use Test::Exception;

use Koha::Database;
use t::lib::TestBuilder;

use t::lib::Mocks::INNReach;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'new() tests' => sub {
    plan tests => 8;

    $schema->storage->txn_begin;

    # Create test objects
    my $library  = $builder->build_object({ class => 'Koha::Libraries' });
    my $category = $builder->build_object({ class => 'Koha::Patron::Categories' });
    my $itemtype = $builder->build_object({ class => 'Koha::ItemTypes' });

    # Test successful creation with default config
    my $plugin = t::lib::Mocks::INNReach->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype
    });

    isa_ok( $plugin, 'Koha::Plugin::Com::Theke::INNReach', 'Returns INNReach plugin instance' );

    # Test configuration is properly set
    my $config = $plugin->configuration;
    ok( exists $config->{d2ir}, 'Configuration contains d2ir central server' );
    is( $config->{d2ir}->{partners_library_id}, $library->branchcode, 'Library ID correctly set' );
    is( $config->{d2ir}->{partners_category}, $category->categorycode, 'Category correctly set' );
    is( $config->{d2ir}->{default_item_type}, $itemtype->itemtype, 'Item type correctly set' );

    # Test custom configuration override
    my $custom_config = {
        'd2ir' => {
            api_base_url => 'https://custom.example.com',
            partners_library_id => 'CUSTOM',
            partners_category => 'CUSTOM_CAT',
            library_to_location => {
                'CUSTOM' => {
                    location => 'custom1',
                    description => 'Custom Library'
                }
            },
            local_to_central_patron_type => {
                'CUSTOM_CAT' => 200
            },
            contribution => {
                enabled => 0,
                included_items => { ccode => ['x', 'y'] }
            }
        }
    };

    my $plugin_custom = t::lib::Mocks::INNReach->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype,
        config   => $custom_config
    });

    my $custom_config_result = $plugin_custom->configuration;
    is( $custom_config_result->{d2ir}->{partners_library_id}, 'CUSTOM', 'Custom library ID correctly set' );
    is( $custom_config_result->{d2ir}->{contribution}->{enabled}, 0, 'Custom contribution setting correctly set' );

    # Test parameter validation
    throws_ok {
        t::lib::Mocks::INNReach->new({});
    } qr/library parameter required/, 'Dies when library parameter missing';

    $schema->storage->txn_rollback;
};
