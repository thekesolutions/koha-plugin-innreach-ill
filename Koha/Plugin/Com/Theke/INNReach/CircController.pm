package Koha::Plugin::Com::Theke::INNReach::CircController;

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use utf8;

use DateTime;
use List::MoreUtils qw(any);
use Try::Tiny;

use CGI;
use C4::Biblio qw(AddBiblio);
use C4::Items;
use C4::Reserves qw(AddReserve CanItemBeReserved);
use Encode;

use Koha::Biblios;
use Koha::Checkouts;
use Koha::Items;
use Koha::Patrons;

use Koha::Database;
use Koha::DateUtils qw(dt_from_string);

use Koha::Illbackends::INNReach::Base;
use Koha::Illrequests;
use Koha::Illrequestattributes;
use Koha::Plugin::Com::Theke::INNReach;
use Koha::Plugin::Com::Theke::INNReach::Exceptions;
use Koha::Plugin::Com::Theke::INNReach::Normalizer;

use Mojo::Base 'Mojolicious::Controller';

=head1 Koha::Plugin::Com::Theke::INNReach::CircController

A class implementing the controller methods for the circulation-related endpoints

=head1 Class methods

=head2 Endpoints for the B<owning site flow>

=head3 itemhold

This method creates an ILLRequest and sets its status to O_ITEM_REQUESTED

=cut

sub itemhold {
    my $c = shift->openapi->valid_input or return;

    my $plugin = Koha::Plugin::Com::Theke::INNReach->new;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

    return $c->invalid_request_id({ trackingId => $trackingId, centralCode => $centralCode })
        if $req;

    my $body = $c->validation->param('body');

    my $attributes = {
        transactionTime   => $body->{transactionTime},
        pickupLocation    => $body->{pickupLocation},
        patronId          => $body->{patronId},
        patronAgencyCode  => $body->{patronAgencyCode},
        itemAgencyCode    => $body->{itemAgencyCode},
        itemId            => $body->{itemId},
        needBefore        => $body->{needBefore},
        centralPatronType => $body->{centralPatronType},
        patronName        => $body->{patronName},
        trackingId        => $trackingId,
        centralCode       => $centralCode
    };

    my $item = Koha::Items->find( $attributes->{itemId} );

    return $c->render(
        status   => 400,
        openapi => {
            status => 'error',
            reason => 'Requested a non-existent item',
            errors => []
        }
    ) unless $item;

    # Add biblio info
    my $biblio = $item->biblio;
    $attributes->{author} = $biblio->author;
    $attributes->{title}  = $biblio->title;

    return try {

        my $schema = Koha::Database->new->schema;
        $schema->txn_do(
            sub {
                my $agency_id  = $attributes->{patronAgencyCode};
                my $config     = $plugin->configuration->{$centralCode};
                my $library_id = $config->{partners_library_id};
                my $patron_id  = $plugin->get_patron_id_from_agency({
                    agency_id      => $agency_id,
                    central_server => $centralCode
                });

                unless ( $patron_id ) {
                    return $c->render(
                        status  => 500,
                        openapi => {
                            status => 'error',
                            reason => "ILL library not loaded in the system. Try again later or contact the administrator ($agency_id).",
                            errors => []
                        }
                    );
                }

                # Create the request
                my $req = Koha::Illrequest->new({
                    branchcode     => $library_id,
                    borrowernumber => $patron_id,
                    biblio_id      => $item->biblionumber,
                    updated        => dt_from_string(),
                    status         => 'O_ITEM_REQUESTED',
                    backend        => 'INNReach'
                })->store;

                # Add the custom attributes
                while ( my ( $type, $value ) = each %{$attributes} ) {
                    if ($value && length $value > 0) {
                        Koha::Illrequestattribute->new(
                            {
                                illrequest_id => $req->illrequest_id,
                                type          => $type,
                                value         => $value,
                                readonly      => 1
                            }
                        )->store;
                    }
                }

                my $can_item_be_reserved = CanItemBeReserved( $patron_id, $item->itemnumber, $library_id )->{status};

                unless ( $can_item_be_reserved eq 'OK' ) {
                    warn "INN-Reach: placing the hold, but rules woul've prevented it. FIXME! (patron_id=$patron_id, item_id="
                         . $item->itemnumber
                         . ", library_id=$library_id, status=$can_item_be_reserved)";
                }

                my $hold_id;
                if ( C4::Context->preference('Version') ge '20.050000' ) {
                    $hold_id = AddReserve(
                        {
                            branchcode       => $req->branchcode,
                            borrowernumber   => $patron_id,
                            biblionumber     => $biblio->biblionumber,
                            priority         => 1,
                            reservation_date => undef,
                            expiration_date  => undef,
                            notes            => $config->{default_hold_note} // 'Placed by ILL',
                            title            => '',
                            itemnumber       => $item->itemnumber,
                            found            => undef,
                            itemtype         => undef
                        }
                    );
                }
                else {
                    $hold_id = AddReserve(
                        $req->branchcode,          # branch
                        $patron_id,                # borrowernumber
                        $biblio->biblionumber,     # biblionumber
                        undef,                     # biblioitemnumber
                        1,                         # priority
                        undef,                     # resdate
                        undef,                     # expdate
                        $config->{default_hold_note} // 'Placed by ILL', # notes
                        '',                        # title
                        $item->itemnumber,         # checkitem
                        undef                      # found
                    );
                }

                $c->render(
                    status  => 200,
                    openapi => {
                        status => 'ok',
                        reason => '',
                        errors => []
                    }
                );
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 localhold

This method creates an ILLRequest and sets its status to O_LOCAL_HOLD

=cut

sub localhold {
    my $c = shift->openapi->valid_input or return;

    my $plugin = Koha::Plugin::Com::Theke::INNReach->new;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

    return $c->invalid_request_id({ trackingId => $trackingId, centralCode => $centralCode })
        if $req;

    my $body = $c->validation->param('body');

    my $attributes = {
        transactionTime   => $body->{transactionTime},
        pickupLocation    => $body->{pickupLocation},
        patronId          => $body->{patronId},
        patronAgencyCode  => $body->{patronAgencyCode},
        itemAgencyCode    => $body->{itemAgencyCode},
        itemId            => $body->{itemId},
        needBefore        => $body->{needBefore},
        centralPatronType => $body->{centralPatronType},
        patronName        => $body->{patronName},
        title             => $body->{title} // '',
        author            => $body->{author},
        trackingId        => $trackingId,
        centralCode       => $centralCode
    };

    my $item = Koha::Items->find( $attributes->{itemId} );

    return $c->render(
        status   => 400,
        openapi => {
            status => 'error',
            reason => 'Requested a non-existent item',
            errors => []
        }
    ) unless $item;

    my $biblio = $item->biblio;

    my $user_id = $attributes->{patronId};
    my $patron  = Koha::Patrons->find( $user_id );

    unless ($patron) {
        return $c->render(
            status  => 400,
            openapi => {
                status => 'error',
                reason => "No patron identified by the provided patronId ($user_id)",
                errors => []
            }
        );
    }

    return try {

        my $schema = Koha::Database->new->schema;
        $schema->txn_do(
            sub {
                my $agency_id = $attributes->{patronAgencyCode};
                my $patron_id = $attributes->{patronId};
                my $config    = $plugin->configuration->{$centralCode};
                # We make this kind of hold subject to ILL circulation rules, and thus
                # use the configured 'partners_library_id' entry for placing the hold.
                my $library_id = $config->{partners_library_id};

                # Create the request
                my $req = Koha::Illrequest->new({
                    branchcode     => $library_id,
                    borrowernumber => $patron_id,
                    biblio_id      => $item->biblionumber,
                    updated        => dt_from_string(),
                    status         => 'O_LOCAL_HOLD',
                    backend        => 'INNReach'
                })->store;

                # Add the custom attributes
                while ( my ( $type, $value ) = each %{$attributes} ) {
                    if ($value && length $value > 0) {
                        Koha::Illrequestattribute->new(
                            {
                                illrequest_id => $req->illrequest_id,
                                type          => $type,
                                value         => $value,
                                readonly      => 1
                            }
                        )->store;
                    }
                }

                $c->render(
                    status  => 200,
                    openapi => {
                        status => 'ok',
                        reason => '',
                        errors => []
                    }
                );

                $c->tx->on(
                    finish => sub {
                        my $can_item_be_reserved = CanItemBeReserved( $patron->borrowernumber, $item->itemnumber, $library_id )->{status};
                        if ( $can_item_be_reserved eq 'OK' ) {
                            # hold can be placed, just do it
                            my $hold_id;
                            if ( C4::Context->preference('Version') ge '20.050000' ) {
                                $hold_id = AddReserve(
                                    {
                                        branchcode       => $req->branchcode,
                                        borrowernumber   => $patron->borrowernumber,
                                        biblionumber     => $biblio->biblionumber,
                                        priority         => 1,
                                        reservation_date => undef,
                                        expiration_date  => undef,
                                        notes            => $config->{default_hold_note} // 'Placed by ILL',
                                        title            => '',
                                        itemnumber       => undef,
                                        found            => undef,
                                        itemtype         => undef
                                    }
                                );
                            }
                            else {
                                $hold_id = AddReserve(
                                    $req->branchcode,          # branch
                                    $patron->borrowernumber,   # borrowernumber
                                    $biblio->biblionumber,     # biblionumber
                                    undef,                     # biblioitemnumber
                                    1,                         # priority
                                    undef,                     # resdate
                                    undef,                     # expdate
                                    $config->{default_hold_note} // 'Placed by ILL', # notes
                                    '',                        # title
                                    undef,                     # checkitem
                                    undef                      # found
                                );
                            }
                        }
                        else {
                            # hold cannot be placed, notify them
                            my $ill = Koha::Illbackends::INNReach::Base->new;
                            $ill->cancel_request({ request => $req });
                        }
                    }
                );
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 itemreceived

This method changes the status of the ILL request to let the users
know the item has been reported at destination.

=cut

sub itemreceived {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    ## TODO: we are supposed to receive all this data, but: what for?
    ## all we do here is changing the request status
    # my $attributes = {
    #     transactionTime   => $body->{transactionTime},
    #     pickupLocation    => $body->{pickupLocation},
    #     patronId          => $body->{patronId},
    #     patronAgencyCode  => $body->{patronAgencyCode},
    #     itemAgencyCode    => $body->{itemAgencyCode},
    #     itemId            => $body->{itemId},
    #     needBefore        => $body->{needBefore},
    #     centralPatronType => $body->{centralPatronType},
    #     patronName        => $body->{patronName},
    #     trackingId        => $trackingId,
    #     centralCode       => $centralCode
    # };

    return try {

        # Get/validate the request
        my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        return $c->invalid_request_id({ trackingId => $trackingId, centralCode => $centralCode })
            unless $req;

        $req->status('O_ITEM_RECEIVED_DESTINATION')->store;

        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => []
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 intransit

This method changes the status of the ILL request to let the users
know the item has been sent back from requesting site.

=cut

sub intransit {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    ## TODO: we are supposed to receive all this data, but: what for?
    ## all we do here is changing the request status
    # my $attributes = {
    #     transactionTime   => $body->{transactionTime},
    #     pickupLocation    => $body->{pickupLocation},
    #     patronId          => $body->{patronId},
    #     patronAgencyCode  => $body->{patronAgencyCode},
    #     itemAgencyCode    => $body->{itemAgencyCode},
    #     itemId            => $body->{itemId},
    #     needBefore        => $body->{needBefore},
    #     centralPatronType => $body->{centralPatronType},
    #     patronName        => $body->{patronName},
    #     trackingId        => $trackingId,
    #     centralCode       => $centralCode
    # };

    return try {

        # Get/validate the request
        my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        return $c->invalid_request_id({ trackingId => $trackingId, centralCode => $centralCode })
            unless $req;

        $req->status('O_ITEM_IN_TRANSIT')->store;

        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => []
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 returnuncirculated

This method changes the status of the ILL request to let the users
know the item has been sent back from requesting site. And that it was
not circulated.

=cut

sub returnuncirculated {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    ## TODO: we are supposed to receive all this data, but: what for?
    ## all we do here is changing the request status
    # my $attributes = {
    #     transactionTime   => $body->{transactionTime},
    #     pickupLocation    => $body->{pickupLocation},
    #     patronId          => $body->{patronId},
    #     patronAgencyCode  => $body->{patronAgencyCode},
    #     itemAgencyCode    => $body->{itemAgencyCode},
    #     itemId            => $body->{itemId},
    #     needBefore        => $body->{needBefore},
    #     centralPatronType => $body->{centralPatronType},
    #     patronName        => $body->{patronName},
    #     trackingId        => $trackingId,
    #     centralCode       => $centralCode
    # };

    return try {

        # Get/validate the request
        my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        return $c->invalid_request_id({ trackingId => $trackingId, centralCode => $centralCode })
            unless $req;

        $req->status('O_ITEM_RETURN_UNCIRCULATED')->store;

        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => []
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 cancelitemhold

This method changes the status of the ILL request to let the users
know the requesting site has cancelled the request.

This can only happen when the ILL request status is O_ITEM_REQUESTED.

=cut

sub cancelitemhold {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $attributes = {
        transactionTime  => $body->{transactionTime},
        patronId         => $body->{patronId},
        patronAgencyCode => $body->{patronAgencyCode},
        itemAgencyCode   => $body->{itemAgencyCode},
        itemId           => $body->{itemId}
    };

    return try {

        my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        return $c->invalid_request_id({ trackingId => $trackingId, centralCode => $centralCode })
          unless $req;

        return $c->render(
            status  => 409,
            openapi => {
                status => 'error',
                reason => 'The request cannot be canceled at this stage',
                errors => []
            }
        ) unless $req->status eq 'O_ITEM_REQUESTED';

        my $plugin = Koha::Plugin::Com::Theke::INNReach->new;

        my $agency_id  = $attributes->{patronAgencyCode};
        my $patron_id  = $plugin->get_patron_id_from_agency({
            agency_id      => $agency_id,
            central_server => $centralCode
        });


        my $patron = Koha::Patrons->find( $patron_id );
        if ( $patron ) {
            my $holds = $patron->holds->search({ itemnumber => $attributes->{itemId} });
            while ( my $hold = $holds->next ) {
                $hold->cancel;
            }
        }

        $req->status('O_ITEM_CANCELLED')->store;

        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => []
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 ownerrenew

This method updates the due date for the request as notified by the central
server.

=cut

sub ownerrenew {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

    return $c->invalid_request_id({ trackingId => $trackingId, centralCode => $centralCode })
        unless $req;

    my $body = $c->validation->param('body');

    my $transactionTime   = $body->{transactionTime};
    my $dueDateTime       = $body->{dueDateTime};
    my $patronId          = $body->{patronId};
    my $patronAgencyCode  = $body->{patronAgencyCode};
    my $itemAgencyCode    = $body->{itemAgencyCode};
    my $itemId            = $body->{itemId};

    return try {

        my $item = Koha::Items->find( $itemId );
        # We are not processing this through AddRenewal
        my $checkout = Koha::Checkouts->search({ itemnumber => $item->itemnumber })->next;
        $checkout->set(
            {
                date_due        => DateTime->from_epoch( epoch => $dueDateTime ),
                renewals        => $checkout->renewals + 1,
                lastreneweddate => dt_from_string
            }
        )->store;

        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => []
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 claimsreturned

This method handles a I<claims returned> notification from central server

This can only happen when the ILL request status is O_ITEM_RECEIVED_DESTINATION.

=cut

sub claimsreturned {
    my $c = shift->openapi->valid_input or return;

    my $trackingId = $c->validation->param('trackingId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime    = $body->{transactionTime};
    my $claimsReturnedDate = $body->{claimsReturnedDate};
    my $patronId           = $body->{patronId};
    my $patronAgencyCode   = $body->{patronAgencyCode};
    my $itemAgencyCode     = $body->{itemAgencyCode};
    my $itemId             = $body->{itemId};

    return try {

        my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        return $c->render(
            status  => 404,
            openapi => {
                status => 'error',
                reason => 'Invalid trackingId/centralCode combination',
                errors => []
            }
        ) unless $req;

        return $c->render(
            status  => 409,
            openapi => {
                status => 'error',
                reason => 'The request cannot be claimed returned at this stage',
                errors => []
            }
        ) unless $req->status eq 'O_ITEM_RECEIVED_DESTINATION';

        my $schema = Koha::Database->new->schema;
        $schema->txn_do(
            sub {
                $req->status('O_ITEM_CLAIMED_RETURNED')->store;
                Koha::Illrequestattribute->new(
                    {
                        illrequest_id => $req->illrequest_id,
                        type          => 'claimsReturnedDate',
                        value         => $claimsReturnedDate,
                        readonly      => 1
                    }
                )->store;

                return $c->render(
                    status  => 200,
                    openapi => {
                        status => 'ok',
                        reason => '',
                        errors => []
                    }
                );
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head2 Endpoints for the B<requesting site flow>

=head3 patronhold

This method creates an ILLRequest and sets its status to B_ITEM_REQUESTED

=cut

sub patronhold {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

    return $c->invalid_request_id({ trackingId => $trackingId, centralCode => $centralCode })
        if $req;

    my $body = $c->validation->param('body');

    my $attributes = {
        transactionTime   => $body->{transactionTime},
        pickupLocation    => $body->{pickupLocation},
        patronId          => $body->{patronId},
        patronAgencyCode  => $body->{patronAgencyCode},
        itemAgencyCode    => $body->{itemAgencyCode},
        itemId            => $body->{itemId},
        centralItemType   => $body->{centralItemType},
        title             => $body->{title}  // '',
        author            => $body->{author} // '',
        callNumber        => $body->{callNumber},
        needBefore        => $body->{needBefore},
        trackingId        => $trackingId,
        centralCode       => $centralCode
    };

    my $user_id = $attributes->{patronId};
    my $patron  = Koha::Patrons->find( $user_id );

    unless ($patron) {
        return $c->render(
            status  => 400,
            openapi => {
                status => 'error',
                reason => "No patron identified by the provided patronId ($user_id)",
                errors => []
            }
        );
    }

    return try {

        my $schema = Koha::Database->new->schema;
        $schema->txn_do(
            sub {
                my $configuration   = Koha::Plugin::Com::Theke::INNReach->new->configuration->{$centralCode};
                my $pickup_location = $c->pickup_location_to_library_id(
                    { pickupLocation => $attributes->{pickupLocation},
                      configuration  => $configuration
                    }
                );

                # Create the request
                my $req = Koha::Illrequest->new({
                    branchcode     => $pickup_location,
                    borrowernumber => $user_id,
                    biblio_id      => undef,
                    updated        => dt_from_string(),
                    status         => 'B_ITEM_REQUESTED',
                    backend        => 'INNReach'
                })->store;

                # Add the custom attributes
                while ( my ( $type, $value ) = each %{$attributes} ) {
                    if ($value && length $value > 0) {
                        Koha::Illrequestattribute->new(
                            {
                                illrequest_id => $req->illrequest_id,
                                type          => $type,
                                value         => $value,
                                readonly      => 1
                            }
                        )->store;
                    }
                }

                return $c->render(
                    status  => 200,
                    openapi => {
                        status => 'ok',
                        reason => '',
                        errors => []
                    }
                );
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 itemshipped

This method changes the status of the ILL request to let the users
know the item has been sent to the borrowing site.

It also creates a virtual MARC record and item which has a hold placed
for the patron. This virtual records are not visible in the OPAC.

=cut

sub itemshipped {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $attributes = {
        callNumber  => $body->{callNumber},
        itemBarcode => $body->{itemBarcode},
    };

    return try {

        # Get/validate the request
        my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        return $c->invalid_request_id({ trackingId => $trackingId, centralCode => $centralCode })
            unless $req;

        # catch duplicate itemshipped requests found in the wild.
        return $c->out_of_sequence({ current_status => 'B_ITEM_SHIPPED', requested_status => 'B_ITEM_SHIPPED' })
            unless $req->status eq 'B_ITEM_REQUESTED';

        my $config = Koha::Plugin::Com::Theke::INNReach->new->configuration->{$centralCode};

        my $schema = Koha::Database->new->schema;
        $schema->txn_do(
            sub {

                # Create the MARC record and item
                my ($biblio_id, $item_id, $biblioitemnumber) = $c->add_virtual_record_and_item(
                    { req         => $req,
                      config      => $config,
                      call_number => $attributes->{callNumber},
                      barcode     => $attributes->{itemBarcode},
                    }
                );

                # Place a hold on the item
                my $patron_id = $req->borrowernumber;
                my $item      = Koha::Items->find( $item_id );
                my $reserve_id;

                if ( C4::Context->preference('Version') ge '20.050000' ) {
                    $reserve_id = AddReserve(
                        {
                            branchcode       => $req->branchcode,
                            borrowernumber   => $patron_id,
                            biblionumber     => $biblio_id,
                            priority         => 1,
                            reservation_date => undef,
                            expiration_date  => undef,
                            notes            => $config->{default_hold_note} // 'Placed by ILL',
                            title            => '',
                            itemnumber       => $item_id,
                            found            => undef,
                            itemtype         => $item->effective_itemtype
                        }
                    );
                }
                else {
                    $reserve_id = AddReserve(
                        $req->branchcode,          # branch
                        $patron_id,                # borrowernumber
                        $biblio_id,                # biblionumber
                        $biblioitemnumber,         # biblioitemnumber
                        1,                         # priority
                        undef,                     # resdate
                        undef,                     # expdate
                        $config->{default_hold_note} // 'Placed by ILL', # notes
                        '',                        # title
                        $item_id,                  # checkitem
                        undef                      # found
                    );
                }

                # Update request
                $req->biblio_id($biblio_id)
                    ->status('B_ITEM_SHIPPED')
                    ->store;

                # Add new attributes for tracking
                while ( my ( $type, $value ) = each %{$attributes} ) {
                    if ($value && length $value > 0) {
                        my $attribute = Koha::Illrequestattributes->find(
                            {
                                illrequest_id => $req->illrequest_id,
                                type          => $type
                            }
                        );
                        # If already exists, overwrite
                        $attribute->delete if $attribute;

                        Koha::Illrequestattribute->new(
                            {
                                illrequest_id => $req->illrequest_id,
                                type          => $type,
                                value         => $value,
                                readonly      => 0
                            }
                        )->store;
                    }
                }

                return $c->render(
                    status  => 200,
                    openapi => {
                        status => 'ok',
                        reason => '',
                        errors => []
                    }
                );
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 finalcheckin

This method changes the status of the ILL request to let the users
know the item has been reported at destination.

=cut

sub finalcheckin {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    return try {

        # Get/validate the request
        my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        return $c->invalid_request_id({ trackingId => $trackingId, centralCode => $centralCode })
            unless $req;

        $req->status('B_ITEM_CHECKED_IN')->store;

        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => []
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 recall

This method receives a recall notification from the Central Server. It stores the
due date and changes the status.

=cut

sub recall {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

    my $body = $c->validation->param('body');

    my $transactionTime   = $body->{transactionTime};
    my $dueDateTime       = $body->{dueDateTime};
    my $patronId          = $body->{patronId};
    my $patronAgencyCode  = $body->{patronAgencyCode};
    my $itemAgencyCode    = $body->{itemAgencyCode};
    my $itemId            = $body->{itemId};

    return try {

        # record this due date for later UI use
        Koha::Illrequestattribute->new(
            {
                illrequest_id => $req->illrequest_id,
                type          => 'recallDueDateTime',
                value         => $dueDateTime,
                readonly      => 1
            }
        )->store;

        # Update request status
        $req->status('B_ITEM_RECALLED')->store;

        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => []
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head2 Endpoints for general use

=head3 local_checkin

This method handles requests to the /koha/checkin/{barcode} endpoint.
It is designed to be used from the checkin form to produce the relevant
actions.

=cut

sub local_checkin {
    my $c = shift->openapi->valid_input or return;

    my $barcode = $c->validation->param('barcode');

    return try {
        my $req = $c->get_ill_request_from_barcode({ barcode => $barcode });

        if ( $req->status eq 'B_ITEM_SHIPPED' ) {
            # We were waiting for this! Notify them we got the item!
            my $ill = Koha::Illbackends::INNReach::Base->new;
            $ill->item_received({ request => $req });
        }
        return $c->render(
            status  => 200,
            openapi => {}
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 borrowerrenew

This method receives a renewal notification from the Central Server. All it does is
recording the new due date.

=cut

sub borrowerrenew {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

    # eary exit if wrong status
    return $c->out_of_sequence(
        {
            current_status   => $req->status,
            requested_status => 'O_ITEM_RECEIVED_DESTINATION'
        }
    ) if $req->status ne 'O_ITEM_RECEIVED_DESTINATION';

    my $body = $c->validation->param('body');

    my $transactionTime   = $body->{transactionTime};
    my $dueDateTime       = $body->{dueDateTime};
    my $patronId          = $body->{patronId};
    my $patronAgencyCode  = $body->{patronAgencyCode};
    my $itemAgencyCode    = $body->{itemAgencyCode};
    my $itemId            = $body->{itemId};

    return try {

        # the current status is valid, retrieve the checkout object
        my $checkout_attribute = $req->illrequestattributes->find({ type => 'checkout_id' });
        my $checkout;

        if ( $checkout_attribute ) {
            $checkout = Koha::Checkouts->find( $checkout_attribute->value );
        }
        else {
            warn "Old request: fallback to search by itemnumber a.k.a. might not be accurate!";
            $checkout = Koha::Checkouts->search({ itemnumber => $itemId })->next;
        }

        unless ( $checkout ) {
            return $c->render(
                status  => 409,
                openapi => {
                    status => 'error',
                    reason => 'Item already checked in at owning library',
                    errors => []
                }
            );
        }

        my $date_due =
                DateTime->from_epoch( epoch => $dueDateTime )
                        ->truncate( to => 'day' )
                        ->set( hour => 23, minute => 59 );

        $checkout->set({ date_due => $date_due })->store;

        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => []
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 cancelrequest

This method handles a cancel request from central server to the borrowing
site. It happens when the owning site issued an owningsitecancel transaction
to the central server.

This can only happen when the ILL request status is O_ITEM_REQUESTED.

=cut

sub cancelrequest {
    my $c = shift->openapi->valid_input or return;

    my $trackingId = $c->validation->param('trackingId');
    my $centralCode   = $c->validation->param('centralCode');

    # my $body = $c->validation->param('body');

    # my $transactionTime   = $body->{transactionTime};
    # my $patronId          = $body->{patronId};
    # my $patronAgencyCode  = $body->{patronAgencyCode};
    # my $itemAgencyCode    = $body->{itemAgencyCode};
    # my $itemId            = $body->{itemId};
    # my $reason            = $body->{reason};
    # my $reasonCode        = $body->{reasonCode}; # 7

    return try {

        my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        return $c->render(
            status  => 404,
            openapi => {
                status => 'error',
                reason => 'Invalid trackingId/centralCode combination',
                errors => []
            }
        ) unless $req;

        return $c->render(
            status  => 409,
            openapi => {
                status => 'error',
                reason => 'The request cannot be canceled at this stage',
                errors => []
            }
        ) unless $req->status eq 'B_ITEM_REQUESTED';

        $req->status('B_ITEM_CANCELLED')->store;

        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => []
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 receiveunshipped

TODO: this method is a stub

=cut

sub receiveunshipped {
    my $c = shift->openapi->valid_input or return;

    my $trackingId = $c->validation->param('trackingId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime    = $body->{transactionTime};
    my $patronId           = $body->{patronId};
    my $patronAgencyCode   = $body->{patronAgencyCode};
    my $itemAgencyCode     = $body->{itemAgencyCode};
    my $itemId             = $body->{itemId};

    return try {
        # do your stuff
        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => []
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 transferrequest

This method handles a transfer request from central server to the borrowing
site. It happens when the owning site notifies the central server they picked
a new item to fulfill the original request.

This request can only happen when the ILL request status is B_ITEM_REQUESTED.

=cut

sub transferrequest {
    my $c = shift->openapi->valid_input or return;

    my $trackingId = $c->validation->param('trackingId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $newItemId        = $body->{newItemId};

    my $attributes = {
        transactionTime  => $body->{transactionTime},
        patronId         => $body->{patronId},
        patronAgencyCode => $body->{patronAgencyCode},
        itemAgencyCode   => $body->{itemAgencyCode},
        itemId           => $newItemId
    };

    return try {
        my $req = $c->get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        while ( my ($type, $value) = each %{$attributes} ) {
            # Update all attributes
            my $attr = $req->illrequestattributes->find({ type => $type });
            $attr->set({ value => $value })->store;
        }

        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => []
            }
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head3 get_print_slip

Given an ILL request id and a letter code, this method returns the HTML required to
generate a print slip for an ILL request.

=cut

sub get_print_slip {
    my $c = shift->openapi->valid_input or return;

    my $illrequest_id = $c->validation->param('illrequest_id');
    my $print_slip_id = $c->validation->param('print_slip_id');

    try {

        my $plugin = Koha::Plugin::Com::Theke::INNReach->new();

        $plugin->{cgi} = CGI->new; # required by C4::Auth::gettemplate and friends
        my $template = $plugin->get_template({ file => 'print_slip.tt' });

        my $req = Koha::Illrequests->find( $illrequest_id );

        unless ($req) {
            return $c->render(
                status  => 404,
                openapi => { error => 'Object not found' }
            );
        }

        my $illrequestattributes = {};
        my $attributes = $req->illrequestattributes;
        while ( my $attribute = $attributes->next ) {
            $illrequestattributes->{$attribute->type} = $attribute->value;
        }

        # Koha::Illrequest->get_notice with hardcoded letter_code
        my $title     = $req->illrequestattributes->find({ type => 'title' });
        my $author    = $req->illrequestattributes->find({ type => 'author' });
        my $metahash  = $req->metadata;
        my @metaarray = ();

        while (my($key, $value) = each %{$metahash}) {
            push @metaarray, "- $key: $value" if $value;
        }

        my $metastring = join("\n", @metaarray);

        my $item_id;
        if ( $req->status =~ /^O_/ ) {
            # 'lending'
            my $item_id_attr = $req->illrequestattributes->find({ type => 'itemId' });
            $item_id = ($item_id_attr) ? $item_id_attr->value : '';
        }
        elsif ( $req->status =~ /^B_/ ) {
            # 'borrowing' (itemId is the lending system's, use itemBarcode instead)
            my $barcode_attr = $req->illrequestattributes->find({ type => 'itemBarcode' });
            my $barcode = ($barcode_attr) ? $barcode_attr->value : '';
            if ( $barcode ) {
                if ( Koha::Items->search({ barcode => $barcode })->count > 0 ) {
                    my $item = Koha::Items->search({ barcode => $barcode })->next;
                    $item_id = $item->id;
                }
            }
        }
        else {
            warn "Not sure where I am";
        }

        my $slip = C4::Letters::GetPreparedLetter(
            module                 => 'circulation', # FIXME: should be 'ill' in 20.11+
            letter_code            => $print_slip_id,
            branchcode             => $req->branchcode,
            message_transport_type => 'print',
            lang                   => $req->patron->lang,
            tables                 => {
                # illrequests => $req->illrequest_id, # FIXME: should be used in 20.11+
                borrowers   => $req->borrowernumber,
                biblio      => $req->biblio_id,
                item        => $item_id,
                branches    => $req->branchcode,
            },
            substitute  => {
                illrequestattributes => $illrequestattributes,
                illrequest           => $req->unblessed, # FIXME: should be removed in 20.11+
                ill_bib_title        => $title ? $title->value : '',
                ill_bib_author       => $author ? $author->value : '',
                ill_full_metadata    => $metastring
            }
        );
        # / Koha::Illrequest->get_notice

        $template->param(
            slip  => $slip->{content},
            title => $slip->{title},
        );

        return $c->render(
            status => 200,
            data   => Encode::encode('UTF-8', $template->output())
        );
    }
    catch {
        return $c->unhandled_innreach_exception($_);
    };
}

=head2 Internal methods

=head3 get_ill_request

This method retrieves the Koha::ILLRequest using trackingId and centralCode

=cut

sub get_ill_request {
    my ( $c, $args ) = @_;

    my $trackingId  = $args->{trackingId};
    my $centralCode = $args->{centralCode};

        # Get/validate the request
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare(qq{
        SELECT * FROM illrequestattributes AS ra_a
        INNER JOIN    illrequestattributes AS ra_b
        ON ra_a.illrequest_id=ra_b.illrequest_id AND
          (ra_a.type='trackingId'  AND ra_a.value='$trackingId') AND
          (ra_b.type='centralCode' AND ra_b.value='$centralCode');
    });

    $sth->execute();
    my $result = $sth->fetchrow_hashref;

    my $req;

    $req = Koha::Illrequests->find( $result->{illrequest_id} )
        if $result->{illrequest_id};

    return $req;
}

=head3 get_ill_request_from_barcode

This method retrieves the Koha::ILLRequest using a barcode, scanned
at check-in.

=cut

sub get_ill_request_from_barcode {
    my ( $c, $args ) = @_;

    my $barcode = $args->{barcode};
    my $status  = $args->{status} // 'B_ITEM_SHIPPED'; # borrowing site, item shipped, receiving

    my $item = Koha::Items->find({ barcode => $barcode });

    unless ( $item ) {
        INNReach::Circ::UnkownBarcode->throw( barcode => $barcode );
    }

    my $biblio_id = $item->biblionumber;

    my $reqs = Koha::Illrequests->search(
        {
            biblio_id => $biblio_id,
            status    => [
                $status
            ]
        }
    );

    if ( $reqs->count > 1 ) {
        warn "More than one ILL request for barcode ($barcode). Beware!";
    }

    return unless $reqs->count > 0;

    my $req = $reqs->next;
    # TODO: what about other stages? testing valid statuses?
    # TODO: Owning site use case?

    return $req;
}

=head3 add_virtual_record_and_item

    $self->add-virtual_record_and_item(
        {
            req         => $req,
            config      => $central_server_config,
            call_number => $call_number,
            barcode     => $barcode,
        }
    );

This method is used for adding a virtual (hidden for end-users) MARC record
with an item, so a hold is placed for it.

=cut

sub add_virtual_record_and_item {
    my ( $c, $args ) = @_;

    my $req         = $args->{req};
    my $config      = $args->{config};
    my $call_number = $args->{call_number};
    my $barcode     = $args->{barcode};

    my $attributes  = $req->illrequestattributes;

    my $centralItemType = $attributes->search({ type => 'centralItemType' })->next->value;

    my $marc_flavour   = C4::Context->preference('marcflavour');
    my $framework_code = $config->{default_marc_framework} || 'FA';
    my $ccode          = $config->{default_item_ccode};
    my $location       = $config->{default_location};
    my $notforloan     = $config->{default_notforloan} // -1;
    my $materials      = $config->{default_materials_specified} || 'Additional processing required (ILL)';
    my $checkin_note   = $config->{default_checkin_note} || 'Additional processing required (ILL)';

    my $no_barcode_central_itypes = $config->{no_barcode_central_itypes} // [];

    if ( any { $centralItemType eq $_ } @{$no_barcode_central_itypes} ) {
        $barcode = undef;
    }
    else {
        my $default_normalizers = $config->{default_barcode_normalizers} // [];

        my $normalizer = Koha::Plugin::Com::Theke::INNReach::Normalizer->new({ string => $barcode });

        foreach my $method ( @{$default_normalizers} ) {
            unless (
                any { $_ eq $method }
                @{ $normalizer->available_normalizers }
              )
            {
                # not a valid normalizer
                warn "Invalid barcode normalizer configured: $method";
            }
            else {
                $normalizer->$method;
            }
        }

        $barcode = $normalizer->get_string;
    }

    # determine the right item types
    my $item_type;
    if ( exists $config->{central_to_local_itype} ) {
        $item_type = ( exists $config->{central_to_local_itype}->{$centralItemType}
                          and $config->{central_to_local_itype}->{$centralItemType} )
                    ? $config->{central_to_local_itype}->{$centralItemType}
                    : $config->{default_item_type};
    }
    else {
        $item_type = $config->{default_item_type};
    }

    unless ( $item_type ) {
        $c->innreach_warn("'default_item_type' entry missing in configuration");
        return $c->render(
            status => 500,
            openapi => {
                status => 'error',
                reason => "'default_item_type' entry missing in configuration",
                errors => []
            }
        );
    }

    my $author_attr = $attributes->search({ type => 'author' })->next;
    my $author      = ( $author_attr ) ? $author_attr->value : '';
    my $title_attr  = $attributes->search({ type => 'title' })->next;
    my $title       = ( $title_attr ) ? $title_attr->value : '';

    my $record;

    if ( $marc_flavour eq 'MARC21' ) {
        $record = MARC::Record->new();
        $record->leader('     nac a22     1u 4500');
        $record->insert_fields_ordered(
            MARC::Field->new(
                '100', '1', '0', 'a' => $author
            ),
            MARC::Field->new(
                '245', '1', '0', 'a' => $title
            ),
            MARC::Field->new(
                '942', '1', '0',
                    'n' => 1,
                    'c' => $item_type
            )
        );
    }
    else {
        return $c->render(
            status => 500,
            openapi => {
                status => 'error',
                reason => "$marc_flavour is not supported (yet)",
                errors => []
            }
        );
    }

    my ( $biblio_id, $biblioitemnumber ) = AddBiblio( $record, $framework_code );

    my $item = {
        barcode          => $barcode,
        holdingbranch    => $req->branchcode,
        homebranch       => $req->branchcode,
        itype            => $item_type,
        itemcallnumber   => $call_number,
        ccode            => $ccode,
        location         => $location,
        materials        => $materials,
        notforloan       => $notforloan,
        itemnotes_nonpublic => $checkin_note,
    };
    my $item_id;
    if ( C4::Context->preference('Version') ge '20.050000' ) {
        $item->{biblionumber} = $biblio_id;
        $item->{biblioitemnumber} = $biblioitemnumber;
        my $item_obj = Koha::Item->new( $item );
        $item_obj->store->discard_changes;
        $item_id = $item_obj->itemnumber;
    }
    else {
        ( undef, undef, $item_id ) = C4::Items::AddItem( $item, $biblio_id );
    }
    return ( $biblio_id, $item_id, $biblioitemnumber );
}

=head3 pickup_location_to_library_id

Given a I<pickupLocation> code as passed to /patronhold
this method returns the local library_id that is mapped to the passed value

=cut

sub pickup_location_to_library_id {
    my ( $c, $args ) = @_;

    my $configuration = $args->{configuration};
    my $pickup_location;
    my $library_id;

    if ( $args->{pickupLocation} =~ m/^(?<pickup_location>.*):.*:.*$/ ) {
        $pickup_location = $+{pickup_location};
    }
    else {
        INNReach::Circ::BadPickupLocation->throw( value => $args->{pickupLocation} );
    }

    $library_id = $configuration->{location_to_library}->{$pickup_location};

    return $library_id;
}

=head3 invalid_request_id

Helper method for rendering invalid centralCode+transactionId combination
errors.

=cut

sub invalid_request_id {
    my ($self, $args) = @_;

    return $self->render(
        status  => 400,
        openapi => {
            status => 'failed',
            reason => 'Unknown centralCode and trackingId combination',
            errors => [
                {
                    type          => "FieldError",
                    reason        => "Invalid record key",
                    name          => "centralCode",
                    rejectedValue => $args->{centralCode}
                },
                {
                    type          => "FieldError",
                    reason        => "Invalid record key",
                    name          => "trackingId",
                    rejectedValue => $args->{trackingId}
                }
            ]
        }
    );
}

=head3 out_of_sequence

Helper method for rendering invalid centralCode+transactionId combination
errors.

=cut

sub out_of_sequence {
    my ($self, $args) = @_;

    my $current_status   = $args->{current_status};
    my $requested_status = $args->{requested_status};

    return $self->render(
        status  => 409,
        openapi => {
            status => 'failed',
            reason => 'The request is out of sequence',
            errors => [
                {
                    type          => "StatusSequenceError",
                    reason        => "The requested status ($requested_status) is not valid after ($current_status)",
                    name          => "status",
                    rejectedValue => $requested_status,
                }
            ]
        }
    );
}

=head3 unhandled_innreach_exception

Helper method for rendering unhandled exceptions correctly

=cut

sub unhandled_innreach_exception {
    my ( $self, $exception ) = @_;

    $self->innreach_warn($exception);

    return $self->render(
        status  => 500,
        openapi => {
            status => 'error',
            reason => 'Unhandled Koha exception',
            errors => [ "$exception" ],
        }
    );
}

=head3 innreach_warn

Helper method for logging warnings for the INN-Reach plugin

=cut

sub innreach_warn {
    my ( $self, $warning ) = @_;

    warn "innreach plugin warn: $warning";
}

1;
