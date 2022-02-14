package Koha::Plugin::Com::Theke::INNReach::Commands::OwningSite;

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

use base qw(Koha::Plugin::Com::Theke::INNReach::Commands::Base);

=head1 Koha::Plugin::Com::Theke::INNReach::Commands::OwningSite

A class implementing methods for sending owning site's messages
to INN-Reach central servers

=head1 API

=head2 Class methods

=head3 final_checkin

    $command->final_checkin( $ill_request );

Given a I<Koha::Illrequest> object, notifies the final check-in took place.

=cut

sub final_checkin {
    my ($self, $request) = @_;

    INNReach::Ill::InconsistentStatus->throw( "Status is not correct: " . $request->status )
        unless $request->status =~ m/^O/; # needs to be owning site flow

    my $attributes = $request->illrequestattributes;

    my $trackingId  = $attributes->find({ type => 'trackingId'  })->value;
    my $centralCode = $attributes->find({ type => 'centralCode' })->value;

    my $response = $self->oauth2( $centralCode )->post_request(
        {   endpoint    => "/innreach/v2/circ/finalcheckin/$trackingId/$centralCode",
            centralCode => $centralCode,
        }
    );

    INNReach::Ill::RequestFailed->throw( method => 'final_checkin', response => $response )
        unless $response->is_success;

    $request->status('O_ITEM_CHECKED_IN')->store;

    return $self;
}

1;
