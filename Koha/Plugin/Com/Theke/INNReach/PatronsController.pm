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

use Koha::DateUtils qw(dt_from_string);
use Koha::Patrons;

use Koha::Plugin::Com::Theke::INNReach;

=head1 Koha::Plugin::Com::Theke::INNReach::PatronsController

A class implementing the controller methods for the patron-related endpoints

=head2 Class methods

=head3 verifypatron

Method that validates a patron's password

=cut

sub verifypatron {
    my $c = shift->openapi->valid_input or return;

    my $body               = $c->validation->param('body');
    my $patron_id          = $body->{visiblePatronId};
    my $patron_agency_code = $body->{patronAgencyCode};
    my $patronName         = $body->{patronName};
    my $passcode           = $body->{passcode} // undef;

    my $configuration = Koha::Plugin::Com::Theke::INNReach->new->configuration;
    my $require_patron_auth = $configuration->{require_patron_auth} // 'false';
    $require_patron_auth = ( $require_patron_auth eq 'true' ) ? 1 : 0;

    if ( $require_patron_auth and !defined $passcode ) {
        return $c->render(
            status  => 403,
            openapi => {
                status => 'error',
                reason => 'Patron authentication required, passcode not supplied',
                errors => [],
            }
        );
    }

    unless ( defined $patron_id and
             defined $patron_agency_code and
             defined $patronName )
    {
        # All fields are mandatory
        my @errors;
        push @errors, 'Missing visiblePatronId'  unless $patron_id;
        push @errors, 'Missing patronAgencyCode' unless $patron_agency_code;
        push @errors, 'Missing patronName'       unless $patronName;

        return $c->render(
            status  => 400,
            openapi => {
                status => 'error',
                reason => 'Invalid parameters',
                errors => \@errors,
            }
        );
    }

    my $patron;
    if ( defined $patron_id ) {
        $patron = Koha::Patrons->find( { cardnumber => $patron_id } );
    }

    unless ($patron) {
        return $c->render(
            status  => 404,
            openapi => {
                status => 'error',
                reason => 'Patron not found',
                errors => []
            }
        );
    }

    my $pass_valid = 1;

    if ( $require_patron_auth ) {
        $pass_valid = ( checkpw_hash( $passcode, $patron->password ) );
    }

    my $expiration_date     = dt_from_string( $patron->dateexpiry );
    my $agency_code         = (exists $configuration->{library_to_location}->{$patron->branchcode})
                                ? $configuration->{library_to_location}->{$patron->branchcode}
                                : $configuration->{mainAgency};
    my $central_patron_type = (exists $configuration->{local_to_central_patron_type}->{$patron->categorycode})
                                ? $configuration->{local_to_central_patron_type}->{$patron->categorycode}
                                : 200;
    my $local_loans         = $patron->checkouts->count;
    my $non_local_loans     = 0;    # TODO: retrieve from INNReach table

    # Borrowed from SIP/Patron.pm
    my $fines_amount = ($patron->account->balance > 0) ? $patron->account->balance : 0;
    my $max_fees     = C4::Context->preference('noissuescharge') // 0;

    my $patron_info = {
        patronId          => $patron->borrowernumber,
        patronExpireDate  => $expiration_date->epoch(),
        patronAgencyCode  => $agency_code,
        centralPatronType => $central_patron_type,
        localLoans        => $local_loans,
        nonlocalLoans     => $non_local_loans,
    };

    my @errors;

    push @errors, 'Patron authentication failure.' unless $pass_valid;
    push @errors, 'The patron is restricted.'      if $patron->is_debarred;
    push @errors, 'The patron has expired.'        if $patron->is_expired;
    push @errors, 'Patron debt reached the limit.' if $fines_amount > $max_fees;

    my $THE_status = 'ok';
    my $THE_reason = '';

    if ( scalar @errors > 0 ) {
        # There's something preventing circ, pick the first reason
        $THE_status = 'error';
        $THE_reason = $errors[0];
    }

    return $c->render(
        status  => 200,
        openapi => {
            status         => $THE_status,
            reason         => $THE_reason,
            errors         => \@errors,
            requestAllowed => ( $THE_status eq 'ok' ) ? Mojo::JSON->true : Mojo::JSON->false,
            patronInfo     => $patron_info
        }
    );
}

=head2 Internal methods

=cut

1;
