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
use Test::Mojo;

use DDP;

use Koha::Database;
use Koha::DateUtils qw(dt_from_string);

use t::lib::Mocks;
use t::lib::TestBuilder;

# INN-Reach specific
use Koha::Plugin::Com::Theke::INNReach;
use Koha::Plugin::Com::Theke::INNReach::Utils qw(add_or_update_attributes);

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;
my $plugin  = Koha::Plugin::Com::Theke::INNReach->new;

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
            class => 'Koha::Illrequests',
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

    add_or_update_attributes(
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

    warn "BEFORE";
    my $deleted_item    = $builder->build_sample_item;
    warn "BETWEEN";
    my $deleted_item_id = $deleted_item->id;
    $deleted_item->delete;
    warn "AFTER";

    $params->{itemId} = $deleted_item_id;

    $t->post_ok( "//$userid:$password@/api/v1/contrib/innreach/v2/circ/itemhold/"
            . "$trackingId/$centralCode" => json => $params )->status_is(400)->json_is( '/status' => 'error' )
        ->json_is( '/reason' => 'Requested a non-existent item' );

    $params->{itemId} = $item->id;

    $t->post_ok(
        "//$userid:$password@/api/v1/contrib/innreach/v2/circ/itemhold/$trackingId/$centralCode" => json => $params )
        ->status_is(200)->json_is( { errors => [], reason => q{}, status => q{ok} } );

    $r = get_ill_request( { centralCode => $centralCode, trackingId => $trackingId } );

    is( $r->status,         'O_ITEM_REQUESTED' );
    is( $r->branchcode,     $configuration->{partners_library_id} );
    is( $r->biblio_id,      $item->biblionumber );
    is( $r->backend,        'INNReach' );
    is( $r->borrowernumber, $patron->id );

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

sub get_ill_request {
    my ($args) = @_;

    my $trackingId  = $args->{trackingId};
    my $centralCode = $args->{centralCode};

    # Get/validate the request
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare(
        qq{
        SELECT * FROM illrequestattributes AS ra_a
        INNER JOIN    illrequestattributes AS ra_b
        ON ra_a.illrequest_id=ra_b.illrequest_id AND
          (ra_a.type='trackingId'  AND ra_a.value='$trackingId') AND
          (ra_b.type='centralCode' AND ra_b.value='$centralCode');
    }
    );

    $sth->execute();
    my $result = $sth->fetchrow_hashref;

    my $req;

    $req = Koha::Illrequests->find( $result->{illrequest_id} )
        if $result->{illrequest_id};

    return $req;
}
