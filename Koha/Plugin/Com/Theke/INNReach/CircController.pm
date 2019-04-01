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

use Mojo::Base 'Mojolicious::Controller';

=head1 Koha::Plugin::Com::Theke::INNReach::PatronsController

A class implementing the controller methods for the patron-related endpoints

=head2 Class methods

=head3 itemhold

TODO: this method is a stub

=cut

sub itemhold {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime   = $body->{transactionTime};
    my $pickupLocation    = $body->{pickupLocation};
    my $patronId          = $body->{patronId};
    my $patronAgencyCode  = $body->{patronAgencyCode};
    my $itemAgencyCode    = $body->{itemAgencyCode};
    my $itemId            = $body->{itemId};
    my $needBefore        = $body->{needBefore};
    my $centralPatronType = $body->{centralPatronType};
    my $patronName        = $body->{patronName};

    return try {
        # do your stuff
        return $c->render(
            status  => 200,
            openapi => {}
        );
    }
    catch {
        return $c->render( status => 500, openapi => { error => 'Some error' } );
    };
}

=head3 patronhold

TODO: this method is a stub

=cut

sub patronhold {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime   = $body->{transactionTime};
    my $pickupLocation    = $body->{pickupLocation};
    my $patronId          = $body->{patronId};
    my $patronAgencyCode  = $body->{patronAgencyCode};
    my $itemAgencyCode    = $body->{itemAgencyCode};
    my $itemId            = $body->{itemId};
    my $needBefore        = $body->{needBefore};
    my $centralPatronType = $body->{centralPatronType};
    my $patronName        = $body->{patronName};

    return try {
        # do your stuff
        return $c->render(
            status  => 200,
            openapi => {}
        );
    }
    catch {
        return $c->render( status => 500, openapi => { error => 'Some error' } );
    };
}

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

=head3 cancelitemhold

TODO: this method is a stub

=cut

sub cancelitemhold {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime   = $body->{transactionTime};
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

=head3 finalcheckin

TODO: this method is a stub

=cut

sub finalcheckin {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime   = $body->{transactionTime};
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

=head3 intransit

TODO: this method is a stub

=cut

sub intransit {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime   = $body->{transactionTime};
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

=head3 itemshipped

TODO: this method is a stub

=cut

sub itemshipped {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime   = $body->{transactionTime};
    my $patronId          = $body->{patronId};
    my $patronAgencyCode  = $body->{patronAgencyCode};
    my $itemAgencyCode    = $body->{itemAgencyCode};
    my $itemId            = $body->{itemId};
    my $centralItemType   = $body->{centralItemType};
    my $itemBarcode       = $body->{itemBarcode};
    my $title             = $body->{title};
    my $author            = $body->{author};
    my $callNumber        = $body->{callNumber};
    my $itemLocation      = $body->{itemLocation};
    my $pickupLocation    = $body->{pickupLocation};
    my $needBefore        = $body->{needBefore};

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

=head3 itemreceived

TODO: this method is a stub

=cut

sub itemreceived {
    my $c = shift->openapi->valid_input or return;

    my $transactionId = $c->validation->param('transactionId');
    my $centralCode   = $c->validation->param('centralCode');

    my $body = $c->validation->param('body');

    my $transactionTime    = $body->{transactionTime};
    my $patronId           = $body->{patronId};
    my $patronAgencyCode   = $body->{patronAgencyCode};
    my $itemAgencyCode     = $body->{itemAgencyCode};
    my $itemId             = $body->{itemId};
    my $centralItemType    = $body->{centralItemType};
    my $author             = $body->{author};
    my $title              = $body->{title};
    my $itemBarcode        = $body->{itemBarcode};
    my $callNumber         = $body->{callNumber};
    my $centralPatronType  = $body->{centralPatronType};

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

=cut

1;
