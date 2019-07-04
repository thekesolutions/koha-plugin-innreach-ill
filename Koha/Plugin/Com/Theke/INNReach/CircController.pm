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

use Try::Tiny;
use C4::Reserves;

use Koha::DateUtils qw(dt_from_string);

use Koha::Illbackends::INNReach::Base;
use Koha::Illrequests;
use Koha::Illrequestattributes;
use Koha::Items;
use Koha::Plugin::Com::Theke::INNReach;

use Mojo::Base 'Mojolicious::Controller';

=head1 Koha::Plugin::Com::Theke::INNReach::PatronsController

A class implementing the controller methods for the patron-related endpoints

=head1 Class methods

=head2 Endpoints for the owning site flow

=head3 itemhold

This method creates an ILLRequest and sets its status to O_ITEM_REQUESTED

=cut

sub itemhold {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    # TODO: check why we cannot use the stashed patron
    #my $user_id = $c->stash('koha.user')->borrowernumber;
    my $user_id = Koha::Plugin::Com::Theke::INNReach->new->configuration->{local_patron_id};

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

        # Create the request
        my $req = Koha::Illrequest->new({
            branchcode     => 'ILL',  # FIXME
            borrowernumber => $user_id,
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
        return $c->render(
            status => 500,
            openapi => {
                status => 'error',
                reason => 'Unknown error',
                errors => []
            }
        );
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
        my $req = get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        return $c->render(
            status  => 400,
            openapi => {
                status => 'error',
                reason => 'Invalid trackingId/centralCode combination',
                errors => []
            }
        ) unless $req;

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
        return $c->render(
            status => 500,
            openapi => {
                status => 'error',
                reason => 'Unknown error',
                errors => []
            }
        );
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
        my $req = get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        return $c->render(
            status  => 400,
            openapi => {
                status => 'error',
                reason => 'Invalid trackingId/centralCode combination',
                errors => []
            }
        ) unless $req;

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
        return $c->render(
            status => 500,
            openapi => {
                status => 'error',
                reason => 'Unknown error',
                errors => []
            }
        );
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

    # my $body = $c->validation->param('body');

    # my $attributes = {
    #     transactionTime  => $body->{transactionTime},
    #     patronId         => $body->{patronId},
    #     patronAgencyCode => $body->{patronAgencyCode},
    #     itemAgencyCode   => $body->{itemAgencyCode},
    #     itemId           => $body->{itemId}
    # }

    return try {

        my $req = get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

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
        ) unless $req->status eq 'O_ITEM_REQUESTED';

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
        return $c->render(
            status => 500,
            openapi => {
                status => 'error',
                reason => 'Internal error',
                errors => []
            }
        );
    };
}

=head2 Endpoints for the owning site flow

=head3 patronhold

This method creates an ILLRequest and sets its status to B_ITEM_REQUESTED

=cut

sub patronhold {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

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

    return try {

        my $patron = Koha::Patrons->find( $user_id );

        # Create the request
        my $req = Koha::Illrequest->new({
            branchcode     => $patron->branchcode,
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
    catch {
        return $c->render(
            status => 500,
            openapi => {
                status => 'error',
                reason => "$_",
                errors => []
            }
        );
    };
}

=head3 itemshipped

This method changes the status of the ILL request to let the users
know the item has been reported at destination.

=cut

sub itemshipped {
    my $c = shift->openapi->valid_input or return;

    my $trackingId  = $c->validation->param('trackingId');
    my $centralCode = $c->validation->param('centralCode');

    return try {

        # Get/validate the request
        my $req = get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        return $c->render(
            status  => 400,
            openapi => {
                status => 'error',
                reason => 'Invalid trackingId/centralCode combination',
                errors => []
            }
        ) unless $req;

        $req->status('B_ITEM_SHIPPED')->store;

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
        return $c->render(
            status => 500,
            openapi => {
                status => 'error',
                reason => 'Unknown error',
                errors => []
            }
        );
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
        my $req = get_ill_request({ trackingId => $trackingId, centralCode => $centralCode });

        return $c->render(
            status  => 400,
            openapi => {
                status => 'error',
                reason => 'Invalid trackingId/centralCode combination',
                errors => []
            }
        ) unless $req;

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
        return $c->render(
            status => 500,
            openapi => {
                status => 'error',
                reason => 'Unknown error',
                errors => []
            }
        );
    };
}

=head2 TODO AREA

=head3 borrowerrenew

TODO: this method is a stub

=cut

sub borrowerrenew {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime   = $body->{transactionTime};
    my $dueDateTime       = $body->{dueDateTime};
    my $patronId          = $body->{patronId};
    my $patronAgencyCode  = $body->{patronAgencyCode};
    my $itemAgencyCode    = $body->{itemAgencyCode};
    my $itemId            = $body->{itemId};

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
        return $c->render( status => 500, openapi => { error => 'Some error' } );
    };
}

=head3 cancelrequest

TODO: this method is a stub

=cut

sub cancelrequest {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime   = $body->{transactionTime};
    my $patronId          = $body->{patronId};
    my $patronAgencyCode  = $body->{patronAgencyCode};
    my $itemAgencyCode    = $body->{itemAgencyCode};
    my $itemId            = $body->{itemId};
    my $reason            = $body->{reason};
    my $reasonCode        = $body->{reasonCode}; # 7

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
        return $c->render( status => 500, openapi => { error => 'Some error' } );
    };
}

=head3 ownerrenew

TODO: this method is a stub

=cut

sub ownerrenew {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime   = $body->{transactionTime};
    my $dueDateTime       = $body->{dueDateTime};
    my $patronId          = $body->{patronId};
    my $patronAgencyCode  = $body->{patronAgencyCode};
    my $itemAgencyCode    = $body->{itemAgencyCode};
    my $itemId            = $body->{itemId};

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
        return $c->render( status => 500, openapi => { error => 'Some error' } );
    };
}

=head3 claimsreturned

TODO: this method is a stub

=cut

sub claimsreturned {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime    = $body->{transactionTime};
    my $claimsReturnedDate = $body->{claimsReturnedDate};
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
        return $c->render( status => 500, openapi => { error => 'Some error' } );
    };
}

=head3 receiveunshipped

TODO: this method is a stub

=cut

sub receiveunshipped {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
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
        return $c->render( status => 500, openapi => { error => 'Some error' } );
    };
}

=head3 returnuncirculated

TODO: this method is a stub

=cut

sub returnuncirculated {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime  = $body->{transactionTime};
    my $patronId         = $body->{patronId};
    my $patronAgencyCode = $body->{patronAgencyCode};
    my $itemAgencyCode   = $body->{itemAgencyCode};
    my $itemId           = $body->{itemId};
    my $author           = $body->{author};
    my $title            = $body->{title};

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
        return $c->render( status => 500, openapi => { error => 'Some error' } );
    };
}

=head3 transferrequest

TODO: this method is a stub

=cut

sub transferrequest {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime  = $body->{transactionTime};
    my $patronId         = $body->{patronId};
    my $patronAgencyCode = $body->{patronAgencyCode};
    my $itemAgencyCode   = $body->{itemAgencyCode};
    my $itemId           = $body->{itemId};
    my $newItemId        = $body->{newItemId};

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
        return $c->render( status => 500, openapi => { error => 'Some error' } );
    };
}

=head2 Internal methods

=head3 get_ill_request

This method retrieves the Koha::ILLRequest using trackingId and centralCode

=cut

sub get_ill_request {
    my ( $args ) = @_;

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

1;
