package Koha::Illbackends::INNReach::Base;

# Copyright Theke Solutions 2019
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use DateTime;
use Try::Tiny;

use Koha::Database;

use C4::Biblio qw(DelBiblio);
use C4::Circulation qw(AddIssue AddReturn);

use Koha::Biblios;
use Koha::DateUtils qw(dt_from_string);
use Koha::Illrequests;
use Koha::Illrequestattributes;
use Koha::Patron;

use Koha::Plugin::Com::Theke::INNReach;
use Koha::Plugin::Com::Theke::INNReach::OAuth2;

=head1 NAME

Koha::Illrequest::Backend::INNReach::Base - Koha ILL Backend: INNReach

=head1 SYNOPSIS

Koha ILL implementation for the "INNReach" backend.

=head1 DESCRIPTION

=head2 Overview

The INN-Reach system acts as a broker for the ILL interactions between different
ILS.

=head2 On the INNReach backend

The INNReach backend is a simple backend that implements two flows:
- Owning site flow
- Borrowing site flow

=head1 API

=head2 Class methods

=cut

=head3 new

  my $backend = Koha::Illrequest::Backend::INNReach->new;

=cut

sub new {

    # -> instantiate the backend
    my ($class) = @_;
    my $plugin = Koha::Plugin::Com::Theke::INNReach->new;
    my $configuration   = $plugin->configuration;
    my @central_servers = $plugin->central_servers;

    my $oauth2;
    foreach my $centralServer ( @central_servers ) {
        $oauth2->{$centralServer} = Koha::Plugin::Com::Theke::INNReach::OAuth2->new({
            client_id          => $configuration->{$centralServer}->{client_id},
            client_secret      => $configuration->{$centralServer}->{client_secret},
            api_base_url       => $configuration->{$centralServer}->{api_base_url},
            api_token_base_url => $configuration->{$centralServer}->{api_token_base_url},
            local_server_code  => $configuration->{$centralServer}->{localServerCode}
        });
    }
    my $self = {
        configuration => $configuration,
        plugin        => $plugin,
        _oauth2       => $oauth2
    };
    bless( $self, $class );
    return $self;
}

=head3 name

Return the name of this backend.

=cut

sub name {
    return "INNReach";
}

=head3 metadata

Return a hashref containing canonical values from the key/value
illrequestattributes store. We may want to ignore certain values
that we do not consider to be metadata

=cut

sub metadata {
    my ( $self, $request ) = @_;
    my $attrs       = $request->illrequestattributes;
    my $metadata    = {};
    my @ignore      = ('requested_partners');
	my $core_fields = _get_core_fields();
    while ( my $attr = $attrs->next ) {
        my $type = $attr->type;
        if ( !grep { $_ eq $type } @ignore ) {
            my $name;
            $name = $core_fields->{$type} || ucfirst($type);
            $metadata->{$name} = $attr->value;
        }
    }
    return $metadata;
}

=head3 status_graph

This backend provides no additional actions on top of the core_status_graph.

=cut

sub status_graph {
    return {

        # status graph for owning site
        O_ITEM_REQUESTED => {
            prev_actions => [ ],
            id             => 'O_ITEM_REQUESTED',
            name           => 'Item Requested',
            ui_method_name => 'Item Requested',
            method         => '',
            next_actions   => [ 'O_ITEM_SHIPPED', 'O_ITEM_CANCELLED_BY_US' ],
            ui_method_icon => '',
        },
        O_LOCAL_HOLD  => {
            prev_actions => [ ],
            id             => 'O_LOCAL_HOLD',
            name           => 'Local hold requested',
            ui_method_name => 'Local hold requested',
            method         => '',
            next_actions   => [ 'COMP' ],
            ui_method_icon => '',
        },
        O_ITEM_CANCELLED => {
            prev_actions => [ 'O_ITEM_REQUESTED' ],
            id             => 'O_ITEM_CANCELLED',
            name           => 'Item request cancelled by requesting library',
            ui_method_name => 'Item request cancelled by requesting library',
            method         => '',
            next_actions   => [ 'COMP' ],
            ui_method_icon => '',
        },
        O_ITEM_CANCELLED_BY_US => {
            prev_actions => [ 'O_ITEM_REQUESTED' ],
            id             => 'O_ITEM_CANCELLED_BY_US',
            name           => 'Item request cancelled',
            ui_method_name => 'Cancel request',
            method         => 'cancel_request',
            next_actions   => [ 'COMP' ],
            ui_method_icon => 'fa-times',
        },
        O_ITEM_SHIPPED => {
            prev_actions => [ 'O_ITEM_REQUESTED' ],
            id             => 'O_ITEM_SHIPPED',
            name           => 'Item shipped to borrowing library',
            ui_method_name => 'Ship item',
            method         => 'item_shipped',
            next_actions   => [ ],
            ui_method_icon => 'fa-send-o',
        },
        O_ITEM_RECEIVED_DESTINATION => {
            prev_actions => [ 'O_ITEM_SHIPPED' ],
            id             => 'O_ITEM_RECEIVED_DESTINATION',
            name           => 'Item received by borrowing library',
            ui_method_name => '',
            method         => '',
            next_actions   => [ 'O_ITEM_RECALLED' ],
            ui_method_icon => '',
        },
        O_ITEM_RECALLED => {
            prev_actions => [ 'O_ITEM_RECEIVED_DESTINATION' ],
            id             => 'O_ITEM_RECALLED',
            name           => 'Item recalled to borrowing library',
            ui_method_name => 'Recall item',
            method         => 'item_recalled',
            next_actions   => [ ],
            ui_method_icon => 'fa-exclamation-circle',
        },
        O_ITEM_CLAIMED_RETURNED => {
            prev_actions => [ 'O_ITEM_RECEIVED_DESTINATION' ],
            id             => 'O_ITEM_CLAIMED_RETURNED',
            name           => 'Item claimed returned at borrowing library',
            ui_method_name => '',
            method         => '',
            next_actions   => [ ],
            ui_method_icon => '',
        },
        O_ITEM_IN_TRANSIT => {
            prev_actions => [ 'O_ITEM_RECEIVED_DESTINATION', 'O_ITEM_CLAIMED_RETURNED' ],
            id             => 'O_ITEM_IN_TRANSIT',
            name           => 'Item in transit from borrowing library',
            ui_method_name => '',
            method         => '',
            next_actions   => [ 'O_ITEM_CHECKED_IN' ],
            ui_method_icon => 'fa-inbox',
        },
        O_ITEM_RETURN_UNCIRCULATED => {
            prev_actions => [ 'O_ITEM_RECEIVED_DESTINATION', 'O_ITEM_CLAIMED_RETURNED' ],
            id             => 'O_ITEM_RETURN_UNCIRCULATED',
            name           => 'Item in transit from borrowing library (uncirculated)',
            ui_method_name => '',
            method         => '',
            next_actions   => [ 'O_ITEM_CHECKED_IN' ],
            ui_method_icon => 'fa-inbox',
        },
        O_ITEM_CHECKED_IN => {
            prev_actions => [ 'O_ITEM_IN_TRANSIT' ],
            id             => 'O_ITEM_CHECKED_IN',
            name           => 'Item checked-in at owning library',
            ui_method_name => 'Check-in',
            method         => 'item_checkin',
            next_actions   => [ 'COMP' ],
            ui_method_icon => 'fa-inbox',
        },

        # status graph for borrowing site
        B_ITEM_REQUESTED => {
            prev_actions => [ ],
            id             => 'B_ITEM_REQUESTED',
            name           => 'Item requested to owning library',
            ui_method_name => 'Item requested to owning library',
            method         => '',
            next_actions   => [ 'B_ITEM_CANCELLED_BY_US' ],
            ui_method_icon => '',
        },
        B_ITEM_CANCELLED => {
            prev_actions => [ ],
            id             => 'B_ITEM_CANCELLED',
            name           => 'Item request cancelled by owning library',
            ui_method_name => 'Item request cancelled by owning library',
            method         => '',
            next_actions   => [ 'COMP' ],
            ui_method_icon => '',
        },
        B_ITEM_CANCELLED_BY_US => {
            prev_actions => [ 'B_ITEM_REQUESTED' ],
            id             => 'B_ITEM_CANCELLED_BY_US',
            name           => 'Item request cancelled',
            ui_method_name => 'Cancel request',
            method         => 'cancel_request_by_us',
            next_actions   => [ 'COMP' ],
            ui_method_icon => 'fa-times',
        },
        B_ITEM_SHIPPED => {
            prev_actions => [ ],
            id             => 'B_ITEM_SHIPPED',
            name           => 'Item shipped by owning library',
            ui_method_name => '',
            method         => '',
            next_actions   => [ 'B_ITEM_RECEIVED' ],
            ui_method_icon => '',
        },
        B_ITEM_RECEIVED => {
            prev_actions => [ 'B_ITEM_SHIPPED' ],
            id             => 'B_ITEM_RECEIVED',
            name           => 'Item received',
            ui_method_name => 'Receive item',
            method         => 'item_received',
            next_actions   => [ 'B_ITEM_IN_TRANSIT', 'B_ITEM_CLAIMED_RETURNED', 'B_ITEM_RETURN_UNCIRCULATED' ],
            ui_method_icon => 'fa-inbox',
        },
        B_ITEM_RECALLED => {
            prev_actions => [ ],
            id             => 'B_ITEM_RECALLED',
            name           => 'Item recalled by owning library',
            ui_method_name => '',
            method         => '',
            next_actions   => [ 'B_ITEM_IN_TRANSIT' ],
            ui_method_icon => '',
        },
        B_ITEM_CLAIMED_RETURNED => {
            prev_actions => [ 'B_ITEM_RECEIVED' ],
            id             => 'B_ITEM_CLAIMED_RETURNED',
            name           => 'Claimed as returned',
            ui_method_name => 'Claim returned',
            method         => 'claims_returned',
            next_actions   => [ 'B_ITEM_IN_TRANSIT' ],
            ui_method_icon => 'fa-exclamation-triangle',
        },
        B_ITEM_IN_TRANSIT => {
            prev_actions => [ 'B_ITEM_RECEIVED', 'B_ITEM_CLAIMED_RETURNED' ],
            id             => 'B_ITEM_IN_TRANSIT',
            name           => 'Item in transit to owning library',
            ui_method_name => 'Item in transit',
            method         => 'item_in_transit',
            next_actions   => [ ],
            ui_method_icon => 'fa-send-o',
        },
        B_ITEM_RETURN_UNCIRCULATED => {
            prev_actions => [ 'B_ITEM_RECEIVED' ],
            id             => 'B_ITEM_RETURN_UNCIRCULATED',
            name           => 'Item in transit to owning library (uncirculated)',
            ui_method_name => 'Return uncirculated',
            method         => 'return_uncirculated',
            next_actions   => [ ],
            ui_method_icon => 'fa-send-o',
        },
        B_ITEM_CHECKED_IN => {
            prev_actions => [ 'B_ITEM_IN_TRANSIT', 'B_ITEM_RETURN_UNCIRCULATED' ],
            id             => 'B_ITEM_CHECKED_IN',
            name           => 'Item checked-in at owning library',
            ui_method_name => 'Check-in',
            method         => '',
            next_actions   => [ 'COMP' ],
            ui_method_icon => '',
        }
    };
}

=head2 Owning site methods

=head3 item_shipped

Method triggered by the UI, to notify the requesting site the item has been
shipped.

=cut

sub item_shipped {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $trackingId  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'trackingId' })->value;
    my $centralCode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'centralCode' })->value;
    my $itemId      = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'itemId' })->value;
    my $item = Koha::Items->find( $itemId );

    return try {
        Koha::Database->schema->storage->txn_do(
            sub {
                my $patron   = Koha::Patrons->find( $req->borrowernumber );
                my $checkout = AddIssue( $patron->unblessed, $item->barcode );

                # record checkout_id
                Koha::Illrequestattribute->new(
                    {
                        illrequest_id => $req->illrequest_id,
                        type          => 'checkout_id',
                        value         => $checkout->id,
                        readonly      => 0
                    }
                )->store;

                # update status
                $req->status('O_ITEM_SHIPPED')->store;
            }
        );

        my $response = $self->oauth2( $centralCode )->post_request(
            {   endpoint    => "/innreach/v2/circ/itemshipped/$trackingId/$centralCode",
                centralCode => $centralCode,
                data        => {
                    callNumber  => $item->itemcallnumber // q{},
                    itemBarcode => $item->barcode // q{},
                }
            }
        );

        return {
            error   => 0,
            status  => '',
            message => '',
            method  => 'item_shipped',
            stage   => 'commit',
            next    => 'illview',
            value   => '',
        };
    }
    catch {
        return {
            error   => 1,
            status  => 'error_on_checkout',
            message => "$_",
            method  => 'item_shipped',
            stage   => 'commit',
            value   => q{},
        };
    };
}

=head3 item_recalled

Method triggered by the UI, to notify the requesting site the item has been
recalled.

=cut

sub item_recalled {
    my ( $self, $params ) = @_;

    my $stage = $params->{other}->{stage};

    if ( !$stage || $stage eq 'init' ) { # initial form, allow choosing date
        return {
            error   => 0,
            status  => '',
            message => '',
            method  => 'item_recalled',
            stage   => 'form'
        };
    }
    else {
        my $req = $params->{request};

        my $trackingId  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'trackingId' })->value;
        my $centralCode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'centralCode' })->value;
        my $itemId      = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'itemId' })->value;

        my $recall_due_date = dt_from_string( $params->{other}->{recall_due_date} );

        return try {

            my $response = $self->oauth2( $centralCode )->post_request(
                {   endpoint    => "/innreach/v2/circ/recall/$trackingId/$centralCode",
                    centralCode => $centralCode,
                    data        => {
                        dueDateTime => $recall_due_date->epoch,
                    }
                }
            );

            $req->status('O_ITEM_RECALLED')->store;

            return {
                error   => 0,
                status  => '',
                message => '',
                method  => 'item_recalled',
                stage   => 'commit',
                next    => 'illview',
                value   => '',
            };
        }
        catch {
            return {
                error   => 1,
                status  => 'error_on_recall',
                message => "$_",
                method  => 'item_recalled',
                stage   => 'commit',
                value   => q{},
            };
        };
    }
}

=head3 item_checkin

Method triggered by the UI, to notify the requesting site that the final
item check-in has taken place.

=cut

sub item_checkin {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $trackingId  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'trackingId' })->value;
    my $centralCode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'centralCode' })->value;

    my $response = $self->oauth2( $centralCode )->post_request(
        {   endpoint    => "/innreach/v2/circ/finalcheckin/$trackingId/$centralCode",
            centralCode => $centralCode,
        }
    );

    $req->status('O_ITEM_CHECKED_IN')->store;

    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'item_checkin',
        stage   => 'commit',
        next    => 'illview',
        value   => '',
    };
}

=head3 cancel_request

Method triggered by the UI, to cancel the request. Can only happen when the request
is on O_ITEM_REQUESTED status.

=cut

sub cancel_request {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $trackingId  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'trackingId'  })->value;
    my $centralCode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'centralCode' })->value;
    my $patronName  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'patronName'  })->value;

    my $response = $self->oauth2( $centralCode )->post_request(
        {   endpoint    => "/innreach/v2/circ/owningsitecancel/$trackingId/$centralCode",
            centralCode => $centralCode,
            data        => {
                localBibId => $req->biblio_id,
                reason     => '',
                reasonCode => '7',
                patronName => $patronName
            }
        }
    );

    my $item_id = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'itemId' })->value;
    my $patron_id = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'patronId' })->value;

    my $holds = Koha::Holds->search({
        borrowernumber => $patron_id,
        itemnumber     => $item_id
    });

    while ( my $hold = $holds->next ) {
        $hold->cancel;
    }

    # Make sure we notify the item status
    $self->{plugin}->schedule_task(
        {
            action         => 'modify',
            central_server => $centralCode,
            object_type    => 'item',
            object_id      => $item_id,
        }
    );

    $req->status('O_ITEM_CANCELLED_BY_US')->store;

    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'cancel_request',
        stage   => 'commit',
        next    => 'illview',
        value   => '',
    };
}

=head2 Requesting site methods

=head3 item_received

Method triggered by the UI, to notify the owning site that the item has been
received.

=cut

sub item_received {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $trackingId  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'trackingId'  })->value;
    my $centralCode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'centralCode' })->value;

    my $response = $self->oauth2( $centralCode )->post_request(
        {   endpoint    => "/innreach/v2/circ/itemreceived/$trackingId/$centralCode",
            centralCode => $centralCode,
        }
    );

    $req->status('B_ITEM_RECEIVED')->store;

    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'item_received',
        stage   => 'commit',
        next    => 'illview',
        value   => '',
    };
}

=head3 item_in_transit

Method triggered by the UI, to notify the owning site the item has been
sent back to them and is in transit.

=cut

sub item_in_transit {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $trackingId  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'trackingId'  })->value;
    my $centralCode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'centralCode' })->value;

    my $response = $self->oauth2( $centralCode )->post_request(
        {   endpoint    => "/innreach/v2/circ/intransit/$trackingId/$centralCode",
            centralCode => $centralCode,
        }
    );

    Koha::Database->new->schema->txn_do(
        sub {
            # Return the item first
            my $barcode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'itemBarcode' })->value;

            AddReturn( $barcode );
            # Is there a hold still?
            # Should we? There's no ON DELETE NULL...
            # $req->biblio_id(undef)->store;
            my $biblio = Koha::Biblios->find( $req->biblio_id );
            # Remove the virtual item
            $biblio->items->delete;
            $biblio->delete;
        }
    );

    $req->status('B_ITEM_IN_TRANSIT')->store;

    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'item_in_transit',
        stage   => 'commit',
        next    => 'illview',
        value   => '',
    };
}

=head3 return_uncirculated

Method triggered by the UI, to notify the owning site the item has been
sent back to them and is in transit.

=cut

sub return_uncirculated {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $trackingId  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'trackingId'  })->value;
    my $centralCode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'centralCode' })->value;

    my $response = $self->oauth2( $centralCode )->post_request(
        {   endpoint    => "/innreach/v2/circ/returnuncirculated/$trackingId/$centralCode",
            centralCode => $centralCode,
        }
    );

    Koha::Database->new->schema->txn_do(
        sub {
            # Cleanup!
            my $biblio = Koha::Biblios->find( $req->biblio_id );
            my $holds  = $biblio->holds;

            # Remove hold(s)
            while ( my $hold = $holds->next ) {
                $hold->cancel;
            }

            # Remove item(s)
            my $items  = $biblio->items;
            while ( my $item = $items->next ) {
                $item->safe_delete;
            }

            DelBiblio( $req->biblio_id );
        }
    );

    $req->status('B_ITEM_RETURN_UNCIRCULATED')->store;

    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'return_uncirculated',
        stage   => 'commit',
        next    => 'illview',
        value   => '',
    };
}

=head3 cancel_request_by_us

Method triggered by the UI, to cancel the request. Can only happen when the request
is on B_ITEM_REQUESTED status.

=cut

sub cancel_request_by_us {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $trackingId  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'trackingId'  })->value;
    my $centralCode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'centralCode' })->value;

    my $response = $self->oauth2( $centralCode )->post_request(
        {   endpoint    => "/innreach/v2/circ/cancelitemhold/$trackingId/$centralCode",
            centralCode => $centralCode,
        }
    );

    $req->status('B_ITEM_CANCELLED_BY_US')->store;

    my $item_id = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'itemId' })->value;
    my $patron_id = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'patronId' })->value;

    my $holds = Koha::Holds->search({
        borrowernumber => $patron_id,
        itemnumber     => $item_id
    });

    while ( my $hold = $holds->next ) {
        $hold->cancel;
    }

    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'cancel_request_by_us',
        stage   => 'commit',
        next    => 'illview',
        value   => '',
    };
}

=head3 claims_returned

Method triggered by the UI, to notify the owning site that the item has been
claimed returned.

=cut

sub claims_returned {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $trackingId  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'trackingId'  })->value;
    my $centralCode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'centralCode' })->value;

    my $response = $self->oauth2( $centralCode )->post_request(
        {   endpoint    => "/innreach/v2/circ/claimsreturned/$trackingId/$centralCode",
            centralCode => $centralCode,
            data        => {
                claimsReturnedDate => dt_from_string->epoch
            }
        }
    );

    $req->status('B_ITEM_CLAIMED_RETURNED')->store;

    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'claims_returned',
        stage   => 'commit',
        next    => 'illview',
        value   => '',
    };
}

=head3 capabilities

    $capability = $backend->capabilities($name);

Return the sub implementing a capability selected by I<$name>, or 0 if that
capability is not implemented.

=cut

sub capabilities {
    my ( $self, $name ) = @_;
    my ($query) = @_;

    my $capabilities = {
        item_recalled => sub { $self->item_recalled(@_); }
    };

    return $capabilities->{$name};
}

=head2 Helper methods

=head3 create

=cut

sub create {
    return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'create',
        stage   => '',
        next    => 'illview',
        value   => '',
    };
}

=head3 _get_core_fields

Return a hashref of core fields

=cut

sub _get_core_fields {
    return {
        type            => 'Type',
        title           => 'Title',
        container_title => 'Container Title',
        author          => 'Author',
        isbn            => 'ISBN',
        issn            => 'ISSN',
        part_edition    => 'Part / Edition',
        volume          => 'Volume',
        year            => 'Year',
        article_title   => 'Part Title',
        article_author  => 'Part Author',
        article_pages   => 'Part Pages',
    };
}

=head3 oauth2

Return the initialized OAuth2 object

=cut

sub oauth2 {
    my ( $self, $centralServer ) = @_;

    return $self->{_oauth2}->{$centralServer};
}

=head1 AUTHORS

Tomás Cohen Arazi <tomascohen@theke.io>

=cut

1;
