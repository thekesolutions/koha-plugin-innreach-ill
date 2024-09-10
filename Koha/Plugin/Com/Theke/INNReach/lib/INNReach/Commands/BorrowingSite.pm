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

use C4::Biblio qw(DelBiblio);

use Koha::Biblios;
use Koha::Checkouts;
use Koha::Database;
use Koha::Items;

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

    INNReach::Ill::InconsistentStatus->throw( "Status is not correct: " . $request->status )
        unless $request->status =~ m/^B/;    # needs to be borrowing site flow

    my $attributes = $request->extended_attributes;

    my $trackingId  = $attributes->find( { type => 'trackingId' } )->value;
    my $centralCode = $attributes->find( { type => 'centralCode' } )->value;

    Koha::Database->schema->storage->txn_do(
        sub {

            # skip actual INN-Reach interactions in dev_mode
            unless ( $self->{configuration}->{$centralCode}->{dev_mode} ) {

                my $response = $self->{plugin}->get_ua($centralCode)->post_request(
                    {
                        endpoint    => "/innreach/v2/circ/itemreceived/$trackingId/$centralCode",
                        centralCode => $centralCode,
                    }
                );

                INNReach::Ill::RequestFailed->throw(
                    method   => 'item_received',
                    response => $response
                ) unless $response->is_success;
            }

            $request->status('B_ITEM_RECEIVED')->store;
        }
    );

    return $self;
}


=head3 item_in_transit

    $command->item_in_transit( $ill_request );

Given a I<Koha::Illrequest> object, notifies the item has been sent back

=cut

sub item_in_transit {
    my ( $self, $request, $options ) = @_;

    INNReach::Ill::InconsistentStatus->throw( "Status is not correct: " . $request->status )
        unless $request->status =~ m/^B/;    # needs to be borrowing site flow

    my $attrs = $request->extended_attributes;

    my $trackingId  = $attrs->find( { type => 'trackingId' } )->value;
    my $centralCode = $attrs->find( { type => 'centralCode' } )->value;

    Koha::Database->schema->storage->txn_do(
        sub {

            # skip actual INN-Reach interactions in dev_mode
            unless ( $self->{configuration}->{$centralCode}->{dev_mode} || !$options->{skip_api_request} ) {

                my $response = $self->{plugin}->get_ua($centralCode)->post_request(
                    {
                        endpoint    => "/innreach/v2/circ/intransit/$trackingId/$centralCode",
                        centralCode => $centralCode,
                    }
                );

                INNReach::Ill::RequestFailed->throw(
                    method   => 'item_in_transit',
                    response => $response
                ) unless $response->is_success;
            }

            # Return the item first
            my $barcode = $attrs->find( { type => 'itemBarcode' } )->value;

            my $item = Koha::Items->find( { barcode => $barcode } );

            if ($item) {    # is the item still on the database
                my $checkout = Koha::Checkouts->find( { itemnumber => $item->id } );

                if ($checkout) {
                    $self->{plugin}->add_return( { barcode => $barcode } );
                }
            }

            my $biblio = Koha::Biblios->find( $request->biblio_id );

            if ($biblio) {    # is the biblio still on the database
                              # Remove the virtual items. there should only be one
                foreach my $item ( $biblio->items->as_list ) {
                    $item->delete( { skip_record_index => 1 } );
                }
                DelBiblio( $biblio->id );
            }

            $request->status('B_ITEM_IN_TRANSIT')->store;
        }
    );

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

    my $response = $self->{plugin}->get_ua($centralCode)->post_request(
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

=head3 final_checkin

    $command->final_checkin( $ill_request );

Given a I<Koha::Illrequest> object, marks the request as checked in at the owning library.

=cut

sub final_checkin {
    my ( $self, $request ) = @_;

    INNReach::Ill::InconsistentStatus->throw(
        "Status is not correct: " . $request->status )
      unless $request->status =~ m/^B/; # needs to be borrowing site flow

    $request->status('B_ITEM_CHECKED_IN')->store;

    return $self;
}

1;
