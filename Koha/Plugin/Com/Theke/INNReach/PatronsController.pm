package Koha::Plugin::Com::Theke::INNReach::PatronsController;

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

use Mojo::Base 'Mojolicious::Controller';

use C4::Auth qw(checkpw_hash);
use C4::Context;

use Koha::DateUtils;
use Koha::Patrons;

=head1 Koha::Plugin::Com::Theke::INNReach::PatronsController

A class implementing the controller methods for the patron-related endpoints

=head2 Class Methods

=head3 verifypatron

Method that validates a patron's password

=cut

sub verifypatron {
    my $c = shift->openapi->valid_input or return;

    my $body               = $c->validation->param('body');
    my $patron_id          = $body->{visiblePatronId};
    my $patron_agency_code = $body->{patronAgencyCode};
    my $passcode           = $body->{passcode};

    unless ( ( defined $patron_id or defined $patron_agency_code )
        and defined $passcode )
    {
        return $c->render( status => 400, openapi => { error => 'Invalid parameters' } );
    }

    my $patron;
    if ( defined $patron_id ) {
        $patron = Koha::Patrons->find( { cardnumber => $patron_id } );
    }

    unless ($patron) {
        return $c->render( status => 404, openapi => { error => 'Object not found.' } );
    }

    my $pass_valid          = ( checkpw_hash( $passcode, $patron->password ) );
    my $expiration_date     = dt_from_string( $patron->dateexpiry );
    my $agency_code         = $patron->branchcode;                     # TODO: map to central code
    my $central_patron_type = $patron->categorycode;                   # TODO: map to central type
    my $local_loans         = $patron->checkouts->count;
    my $non_local_loans     = 0;    # TODO: retrieve from INNReach table

    # Borrowed from SIP/Patron.pm
    my $fines_amount = ($patron->account->balance > 0) ? $fines_amount : 0;
    my $max_fees     = C4::Context->preference('noissuescharge') // 0;

    my $patron_info = {
        patronID          => $patron->borrowernumber,
        patronExpireDate  => $expiration_date->epoch(),
        patronAgencyCode  => $agency_code,
        centralPatronType => $central_patron_type,
        localLoans        => $local_loans,
        nonlocalLoans     => $non_local_loans,
    };

    push @errors;

    push @status, 'invalid_auth' unless $pass_valid;
    push @status, 'debarred'     if $patron->is_debarred;
    push @status, 'expired'      if $patron->is_expired;
    push @status, 'debt'         if $fines_amount > $max_fees;

    my $THE_status = 'ok';
    my $THE_reason = '';

    if ( scalar @status > 0 ) {
        # There's something preventing circ, pick the first reason
        $THE_status = $status[0];
        $THE_reason = $codes_to_status->{$THE_status};
    }

    return $c->render(
        status  => 200,
        openapi => {
            status         => $status,
            reason         => $reason,
            errors         => [],
            requestAllowed => ( $status eq 'ok' ) ? Mojo::JSON->true : Mojo::JSON->false,
            patronInfo     => $patron_info
        }
    );
}

=head2 Internal methods

=cut

my $codes_to_status = {
    debarred     => 'The patron is restricted.',
    debt         => 'Patron debt reached the limit.',
    expired      => 'The patron has expired.'
    invalid_auth => 'Patron authentication failure.',
};

1;
