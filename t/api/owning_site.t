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

use Test::More tests => 3;
use Test::Mojo;
use Test::Warn;

use DDP;

use Koha::Database;
use Koha::DateUtils qw(dt_from_string);

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

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'Full flow tests' => sub {

    plan tests => 16;

    $schema->storage->txn_begin;

    my $centralCode = "d2ir";
    my $agency_id   = "code2";
    my $password    = 'thePassword123';
    my $user        = add_superlibrarian($password);
    my $userid      = $user->userid;

    my $item = $builder->build_sample_item;

    my $configuration = $plugin->configuration->{$centralCode};
    my $patron        = $plugin->generate_patron_for_agency(
        {
            central_server => $centralCode,
            local_server   => $configuration->{localServerCode},
            description    => 'Sample external library',
            agency_id      => $agency_id,
        }
    );

    my $r = $builder->build_object(
        {
            class => $ill_reqs_class,
            value => {
                backend           => 'INNReach',
                status            => 'O_ITEM_SHIPPED',
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

    my $trackingId = "123456789";

    $plugin->add_or_update_attributes(
        {
            request    => $r,
            attributes => {
                trackingId  => "$trackingId",
                centralCode => "$centralCode",
            }
        }
    );

    my $params = {
        transactionTime   => dt_from_string->epoch,
        pickupLocation    => 'asd',
        patronId          => $patron->id,
        patronAgencyCode  => $configuration->{mainAgency},
        itemAgencyCode    => $configuration->{mainAgency},
        itemId            => $item->id,
        needBefore        => dt_from_string->add( days => 60 )->epoch,
        centralPatronType => 200,
        patronName        => 'Lisette',
    };

    $t->post_ok( "//$userid:$password@/api/v1/contrib/innreach/v2/circ/itemhold/"
            . "$trackingId/$centralCode" => json => $params )->status_is(400)->json_is( '/status' => 'failed' )
        ->json_is( '/reason' => 'Unknown centralCode and trackingId combination' );

    # remove the duplicate request
    $r->delete;

    my $deleted_item    = $builder->build_sample_item;
    my $deleted_item_id = $deleted_item->id;
    $deleted_item->delete;

    $params->{itemId} = $deleted_item_id;

    $t->post_ok( "//$userid:$password@/api/v1/contrib/innreach/v2/circ/itemhold/"
            . "$trackingId/$centralCode" => json => $params )->status_is(400)->json_is( '/status' => 'error' )
        ->json_is( '/reason' => 'Requested a non-existent item' );

    $params->{itemId} = $item->id;

    $t->post_ok(
        "//$userid:$password@/api/v1/contrib/innreach/v2/circ/itemhold/$trackingId/$centralCode" => json => $params )
        ->status_is(200)->json_is( { errors => [], reason => q{}, status => q{ok} } );

    $r = $plugin->get_ill_request( { centralCode => $centralCode, trackingId => $trackingId } );

    is( $r->status,         'O_ITEM_REQUESTED' );
    is( $r->branchcode,     $configuration->{partners_library_id} );
    is( $r->biblio_id,      $item->biblionumber );
    is( $r->backend,        'INNReach' );
    is( $r->borrowernumber, $patron->id );

    $schema->storage->txn_rollback;
};

subtest 'intransit() tests' => sub {

    plan tests => 12;

    $schema->storage->txn_begin;

    my $centralCode = "d2ir";
    my $agency_id   = "code2";
    my $password    = 'thePassword123';
    my $user        = add_superlibrarian($password);
    my $userid      = $user->userid;

    my $item = $builder->build_sample_item;

    my $configuration = $plugin->configuration->{$centralCode};
    my $patron        = $plugin->generate_patron_for_agency(
        {
            central_server => $centralCode,
            local_server   => $configuration->{localServerCode},
            description    => 'Sample external library',
            agency_id      => $agency_id,
        }
    );

    my $r = $builder->build_object(
        {
            class => $ill_reqs_class,
            value => {
                backend           => 'INNReach',
                status            => 'O_ITEM_REQUESTED',
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

    my $hold_id = $plugin->add_hold(
        {
            library_id => $patron->branchcode,
            patron_id  => $patron->id,
            biblio_id  => $item->biblionumber,
            item_id    => $item->id,
        }
    );

    my $trackingId = "123456789";

    $plugin->add_or_update_attributes(
        {
            request    => $r,
            attributes => {
                trackingId  => "$trackingId",
                centralCode => "$centralCode",
                hold_id     => $hold_id,
            }
        }
    );

    my $params = {
        transactionTime  => dt_from_string->epoch,
        patronId         => $patron->id,
        patronAgencyCode => $configuration->{mainAgency},
        itemAgencyCode   => $configuration->{mainAgency},
        itemId           => $item->id,
    };

    warnings_exist {
        $t->put_ok(
            "//$userid:$password@/api/v1/contrib/innreach/v2/circ/intransit/$trackingId/$centralCode" => json =>
                $params )->status_is(200)->json_is( { errors => [], reason => q{}, status => q{ok} } );
    }
    qr{^innreach_plugin_warn: Request \d+ set to O_ITEM_IN_TRANSIT but didn't have a 'checkout_id' attribute};

    $r->discard_changes;
    is( $r->status, 'O_ITEM_IN_TRANSIT',                                            'Status updated correctly' );
    is( $r->extended_attributes->search( { type => 'checkout_id' } )->count, 1,     'The item has been checked out' );
    is( Koha::Holds->find($hold_id),                                         undef, 'No hold' );

    my $checkout_id = $r->extended_attributes->search( { type => 'checkout_id' } )->next->value;

    $t->put_ok(
        "//$userid:$password@/api/v1/contrib/innreach/v2/circ/intransit/$trackingId/$centralCode" => json => $params )
        ->status_is(200)->json_is( { errors => [], reason => q{}, status => q{ok} } );

    is( $r->extended_attributes->search( { type => 'checkout_id' } )->count, 1, 'No new checkout_id added' );

    my $new_checkou_id = $r->extended_attributes->search( { type => 'checkout_id' } )->next->value;

    is( $new_checkou_id, $checkout_id, 'checkout_id unchanged' );

    $schema->storage->txn_rollback;
};

subtest 'itemreceived() tests' => sub {

    plan tests => 12;

    $schema->storage->txn_begin;

    my $centralCode = "d2ir";
    my $agency_id   = "code2";
    my $password    = 'thePassword123';
    my $user        = add_superlibrarian($password);
    my $userid      = $user->userid;

    my $item = $builder->build_sample_item;

    my $configuration = $plugin->configuration->{$centralCode};
    my $patron        = $plugin->generate_patron_for_agency(
        {
            central_server => $centralCode,
            local_server   => $configuration->{localServerCode},
            description    => 'Sample external library',
            agency_id      => $agency_id,
        }
    );

    my $r = $builder->build_object(
        {
            class => $ill_reqs_class,
            value => {
                backend           => 'INNReach',
                status            => 'O_ITEM_REQUESTED',
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

    my $hold_id = $plugin->add_hold(
        {
            library_id => $patron->branchcode,
            patron_id  => $patron->id,
            biblio_id  => $item->biblionumber,
            item_id    => $item->id,
        }
    );

    my $trackingId = "123456789";

    $plugin->add_or_update_attributes(
        {
            request    => $r,
            attributes => {
                trackingId  => "$trackingId",
                centralCode => "$centralCode",
                hold_id     => $hold_id,
            }
        }
    );

    my $params = {
        transactionTime  => dt_from_string->epoch,
        patronId         => $patron->id,
        patronAgencyCode => $configuration->{mainAgency},
        itemAgencyCode   => $configuration->{mainAgency},
        itemId           => $item->id,
    };

    warnings_exist {
        $t->put_ok(
            "//$userid:$password@/api/v1/contrib/innreach/v2/circ/itemreceived/$trackingId/$centralCode" => json =>
                $params )->status_is(200)->json_is( { errors => [], reason => q{}, status => q{ok} } );
    }
    qr{^innreach_plugin_warn: Request \d+ set to O_ITEM_RECEIVED_DESTINATION but didn't have a 'checkout_id' attribute};

    $r->discard_changes;
    is( $r->status, 'O_ITEM_RECEIVED_DESTINATION',                                            'Status updated correctly' );
    is( $r->extended_attributes->search( { type => 'checkout_id' } )->count, 1,     'The item has been checked out' );
    is( Koha::Holds->find($hold_id),                                         undef, 'No hold' );

    my $checkout_id = $r->extended_attributes->search( { type => 'checkout_id' } )->next->value;

    $t->put_ok(
        "//$userid:$password@/api/v1/contrib/innreach/v2/circ/itemreceived/$trackingId/$centralCode" => json => $params )
        ->status_is(200)->json_is( { errors => [], reason => q{}, status => q{ok} } );

    is( $r->extended_attributes->search( { type => 'checkout_id' } )->count, 1, 'No new checkout_id added' );

    my $new_checkou_id = $r->extended_attributes->search( { type => 'checkout_id' } )->next->value;

    is( $new_checkou_id, $checkout_id, 'checkout_id unchanged' );

    $schema->storage->txn_rollback;
};

sub add_superlibrarian {
    my ($password) = @_;
    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 1 }
        }
    );
    $password //= 'thePassword123';
    $patron->set_password( { password => $password, skip_validation => 1 } );
    $patron->discard_changes;
    return $patron;
}
