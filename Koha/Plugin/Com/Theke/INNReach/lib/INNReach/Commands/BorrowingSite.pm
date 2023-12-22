package INNReach::Commands::BorrowingSite;

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

use base qw(INNReach::Commands::Base);

=head1 INNReach::Commands::BorrowingSite

A class implementing methods for sending borrowing site's messages
to INN-Reach central servers

=head1 API

=head2 Class methods

=head3 item_received

    $command->item_received( $ill_request );

Given a I<Koha::Illrequest> object, notifies the item has been received

=cut

sub item_received {
    my ( $self, $request ) = @_;

    INNReach::Ill::InconsistentStatus->throw(
        "Status is not correct: " . $request->status )
      unless $request->status =~ m/^B/; # needs to be borrowing site flow

    my $attributes = $request->extended_attributes;

    my $trackingId  = $attributes->find( { type => 'trackingId' } )->value;
    my $centralCode = $attributes->find( { type => 'centralCode' } )->value;

    my $response = $self->oauth2($centralCode)->post_request(
        {
            endpoint => "/innreach/v2/circ/intransit/$trackingId/$centralCode",
            centralCode => $centralCode,
        }
    );

    INNReach::Ill::RequestFailed->throw(
        method   => 'item_received',
        response => $response
    ) unless $response->is_success;

    $request->status('B_ITEM_RECEIVED')->store;

    return $self;
}

=head3 receive_unshipped

    $command->receive_unshipped( $ill_request );

Given a I<Koha::Illrequest> object, notifies the item has been received but no
I<itemshipped> message was received.

=cut

sub receive_unshipped {
    my ( $self, $request ) = @_;

    INNReach::Ill::InconsistentStatus->throw(
        "Status is not correct: " . $request->status )
      unless $request->status =~ m/^B/; # needs to be borrowing site flow

    my $attributes = $request->extended_attributes;

    my $trackingId  = $attributes->find( { type => 'trackingId' } )->value;
    my $centralCode = $attributes->find( { type => 'centralCode' } )->value;

    my $response = $self->oauth2($centralCode)->post_request(
        {
            endpoint => "/innreach/v2/circ/receiveunshipped/$trackingId/$centralCode",
            centralCode => $centralCode,
        }
    );

    INNReach::Ill::RequestFailed->throw(
        method   => 'receive_unshipped',
        response => $response
    ) unless $response->is_success;

    return $self;
}

1;
