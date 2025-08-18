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
use Test::Warn;

use Koha::Database;

use t::lib::Mocks;
use t::lib::TestBuilder;

# INN-Reach specific
use Koha::Plugin::Com::Theke::INNReach;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;
my $plugin  = Koha::Plugin::Com::Theke::INNReach->new;

my $ill_reqs_class;
if ( C4::Context->preference('Version') ge '24.050000' ) {
    $ill_reqs_class = "Koha::ILL::Requests";
} else {
    $ill_reqs_class = "Koha::Illrequests";
}

t::lib::Mocks::mock_preference( 'SearchEngine', 'Zebra' );

subtest 'new() tests' => sub {

    plan tests => 1;

    my $p = Koha::Plugin::Com::Theke::INNReach->new;
    my $c = $p->borrowing_commands;
    
    isa_ok( $c, 'INNReach::Commands::BorrowingSite', 'borrowing_commands returns correct object type' );
};

subtest 'item_in_transit() tests' => sub {

    plan tests => 2;

    $schema->storage->txn_begin;

    my $p = Koha::Plugin::Com::Theke::INNReach->new;
    my $c = $p->borrowing_commands;

    my $patron    = $builder->build_object( { class => 'Koha::Patrons' } );
    my $item      = $builder->build_sample_item();
    my $biblio_id = $item->biblionumber;

    my $r = $builder->build_object(
        {
            class => $ill_reqs_class,
            value => {
                backend           => 'INNReach',
                status            => 'POTATO',
                biblio_id         => $item->biblionumber,
                deleted_biblio_id => undef,
                completed         => undef,
                medium            => undef,
                orderid           => undef,
                borrowernumber    => $patron->id,
                branchcode        => $patron->branchcode,
            }
        }
    );

    my $trackingId  = "123456789";
    my $centralCode = "d2ir";

    $plugin->add_or_update_attributes(
        {
            request    => $r,
            attributes => {
                centralCode => $centralCode,
                itemBarcode => $item->barcode,
                trackingId  => $trackingId,
            }
        }
    );

    throws_ok { $c->item_in_transit($r) }
    'INNReach::Ill::InconsistentStatus',
        'Only ^B.* statuses can be passed to item_in_transit';

    my $indexer_mock = Test::MockModule->new('Koha::SearchEngine::Zebra::Indexer');
    $indexer_mock->mock(
        'index_records',
        sub { my ( $self, $biblio_id ) = @_; warn "index_records called with $biblio_id"; }
    );

    $r->status('B_ITEM_RECEIVED')->store();

    warnings_exist { $c->item_in_transit($r); }
    qr/^index_records called with $biblio_id/,
        'Reindexing triggered';

    $schema->storage->txn_rollback;
};
