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

=head2 Class Methods

=head3 itemhold

Method that generates an item hold

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

Method that generates a patron hold

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

=head2 Internal methods

=cut

1;
