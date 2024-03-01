package INNReach::Commands::OwningSite;

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

use C4::Context;

use Koha::Database;
use Koha::Illrequestattribute;
use Koha::Items;
use Koha::Patrons;

use base qw(INNReach::Commands::Base);

=head1 INNReach::Commands::OwningSite

A class implementing methods for sending owning site's messages
to INN-Reach central servers

=head1 API

=head2 Class methods


=head3 cancel_request

    $command->cancel_request( $request );

Given a I<Koha::Illrequest> object, notifies it got cancelled by the owning site.

=cut

sub cancel_request {
    my ( $self, $request ) = @_;

    INNReach::Ill::InconsistentStatus->throw( "Status is not correct: " . $request->status )
        unless $request->status =~ m/^O/;    # needs to be owning site flow

    Koha::Database->schema->storage->txn_do(
        sub {
            my $attributes = $request->extended_attributes;

            my $trackingId  = $attributes->find( { type => 'trackingId' } )->value;
            my $centralCode = $attributes->find( { type => 'centralCode' } )->value;
            my $patronName  = $attributes->find( { type => 'patronName' } )->value;

            $request->status('O_ITEM_CANCELLED_BY_US')->store;

            # skip actual INN-Reach interactions in dev_mode
            unless ( $self->{configuration}->{$centralCode}->{dev_mode} ) {
                my $response = $self->{plugin}->get_ua($centralCode)->post_request(
                    {
                        endpoint    => "/innreach/v2/circ/owningsitecancel/$trackingId/$centralCode",
                        centralCode => $centralCode,
                        data        => {
                            localBibId => $request->biblio_id,
                            reason     => '',
                            reasonCode => '7',
                            patronName => $patronName
                        }
                    }
                );

                INNReach::Ill::RequestFailed->throw( method => 'cancel_request', response => $response )
                    unless $response->is_success;
            }
        }
    );

    return $self;
}

=head3 final_checkin

    $command->final_checkin( $request );

Given a I<Koha::Illrequest> object, notifies the final check-in took place.

=cut

sub final_checkin {
    my ( $self, $request ) = @_;

    INNReach::Ill::InconsistentStatus->throw( "Status is not correct: " . $request->status )
        unless $request->status =~ m/^O/;    # needs to be owning site flow

    my $attributes = $request->extended_attributes;

    my $trackingId  = $attributes->find( { type => 'trackingId' } )->value;
    my $centralCode = $attributes->find( { type => 'centralCode' } )->value;

    my $response = $self->{plugin}->get_ua($centralCode)->post_request(
        {
            endpoint    => "/innreach/v2/circ/finalcheckin/$trackingId/$centralCode",
            centralCode => $centralCode,
        }
    );

    INNReach::Ill::RequestFailed->throw( method => 'final_checkin', response => $response )
        unless $response->is_success;

    $request->status('O_ITEM_CHECKED_IN')->store;

    return $self;
}

=head3 item_shipped

    $command->item_shipped( $request );

Given a I<Koha::Illrequest> object, notifies the item has been shipped.

=cut

sub item_shipped {
    my ( $self, $request ) = @_;

    INNReach::Ill::InconsistentStatus->throw( "Status is not correct: " . $request->status )
        unless $request->status =~ m/^O_ITEM_REQUESTED/;

    my $attributes = $request->extended_attributes;

    my $trackingId  = $attributes->find( { type => 'trackingId' } )->value;
    my $centralCode = $attributes->find( { type => 'centralCode' } )->value;
    my $item_id     = $attributes->find( { type => 'itemId' } )->value;

    INNReach::Ill::MissingParameter->throw( param => 'item_id' )
        unless $item_id;

    Koha::Database->schema->storage->txn_do(
        sub {

            my $item   = Koha::Items->find($item_id);
            my $patron = Koha::Patrons->find( $request->borrowernumber );

            # If calling this from the UI, things are set.
            unless ( C4::Context->userenv ) {

                # CLI => set userenv
                C4::Context->_new_userenv(1);
                C4::Context->set_userenv(
                    undef,                undef, undef, 'CLI', 'CLI',
                    $request->branchcode, undef, undef, undef, undef
                );

                # Set interface
                C4::Context->interface('commandline');
            }

            # update status first, to avoid doubled jobs which could
            # happen if the item needs a transfer, etc
            $request->status('O_ITEM_SHIPPED')->store;

            my $checkout = $self->{plugin}->add_issue( { patron => $patron, barcode => $item->barcode } );

            # record checkout_id
            Koha::Illrequestattribute->new(
                {
                    illrequest_id => $request->illrequest_id,
                    type          => 'checkout_id',
                    value         => $checkout->id,
                    readonly      => 0
                }
            )->store;

            # skip actual INN-Reach interactions in dev_mode
            unless ( $self->{configuration}->{$centralCode}->{dev_mode} ) {
                my $response = $self->{plugin}->get_ua($centralCode)->post_request(
                    {
                        endpoint    => "/innreach/v2/circ/itemshipped/$trackingId/$centralCode",
                        centralCode => $centralCode,
                        data        => {
                            callNumber  => $item->itemcallnumber // q{},
                            itemBarcode => $item->barcode        // q{},
                        }
                    }
                );

                INNReach::Ill::RequestFailed->throw( method => 'item_shipped', response => $response )
                    unless $response->is_success;
            }
        }
    );

    return $self;
}

1;
