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

use Koha::Illrequests;
use Koha::Illrequestattributes;

use Koha::Plugin::Com::Theke::INNReach::Contribution;

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
    my $self = {};
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
            next_actions   => [ 'O_ITEM_SHIPPED' ],
            ui_method_icon => '',
        },
        O_ITEM_CANCELLED => {
            prev_actions => [ 'O_ITEM_REQUESTED' ],
            id             => 'O_ITEM_CANCELLED',
            name           => 'Item request cancelled by requestor',
            ui_method_name => 'Item request cancelled by requestor',
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
            ui_method_icon => '',
        },
        O_ITEM_SHIPPED => {
            prev_actions => [ 'O_ITEM_REQUESTED' ],
            id             => 'O_ITEM_SHIPPED',
            name           => 'Item shipped to borrowing site',
            ui_method_name => 'Ship item',
            method         => 'item_shipped',
            next_actions   => [ ],
            ui_method_icon => 'fa-send-o',
        },
        O_ITEM_RECEIVED_DESTINATION => {
            prev_actions => [ 'O_ITEM_SHIPPED' ],
            id             => 'O_ITEM_RECEIVED_DESTINATION',
            name           => 'Item received on borrowing site',
            ui_method_name => 'Receive item',
            method         => '',
            next_actions   => [ ],
            ui_method_icon => '',
        },
        O_ITEM_IN_TRANSIT => {
            prev_actions => [ 'O_ITEM_RECEIVED_DESTINATION' ],
            id             => 'O_ITEM_IN_TRANSIT',
            name           => 'Item in transit from borrowing site',
            ui_method_name => 'Return item',
            method         => '',
            next_actions   => [ ],
            ui_method_icon => '',
        },
        O_ITEM_CHECKED_IN => {
            prev_actions => [ 'O_ITEM_IN_TRANSIT' ],
            id             => 'O_ITEM_CHECKED_IN',
            name           => 'Item checked-in at owning site',
            ui_method_name => 'Check-in',
            method         => 'item_checkin',
            next_actions   => [ 'COMP' ],
            ui_method_icon => 'fa-inbox',
        },

        # Common statuses
        DONE => {
            prev_actions => [ 'O_ITEM_IN_TRANSIT' ],
            id             => 'DONE',
            name           => 'Transaction completed',
            ui_method_name => 'Done',
            method         => '',
            next_actions   => [],
            ui_method_icon => 'fa-inbox',
        },
    };
}

sub item_shipped {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $trackingId  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'trackingId' })->value;
    my $centralCode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'centralCode' })->value;
    my $itemId      = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'itemId' })->value;
    my $item = Koha::Items->find( $itemId );

    # my $innreach = Koha::Plugin::Com::Theke::INNReach::Contribution->new;
    # my $response = $innreach->post_request(
    #     {   endpoint    => "/innreach/v2/circ/itemshipped/$trackingId/$centralCode",
    #         centralCode => $centralCode,
    #         data        => {
    #             callNumber  => $item->itemcallnumber // q{},
    #             itemBarcode => $item->barcode // q{},
    #         }
    #     }
    # );

    $req->status('O_ITEM_SHIPPED')->store;

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

sub item_checkin {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $trackingId  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'trackingId' })->value;
    my $centralCode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'centralCode' })->value;

    # my $innreach = Koha::Plugin::Com::Theke::INNReach::Contribution->new;
    # my $response = $innreach->post_request(
    #     {   endpoint    => "/innreach/v2/circ/finalcheckin/$trackingId/$centralCode",
    #         centralCode => $centralCode,
    #         data        => undef
    #     }
    # );

    $req->status('O_ITEM_CHECKED_IN')->store;

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

sub cancel_request {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $trackingId  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'trackingId'  })->value;
    my $centralCode = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'centralCode' })->value;
    my $patronName  = Koha::Illrequestattributes->find({ illrequest_id => $req->id, type => 'patronName'  })->value;

    # my $innreach = Koha::Plugin::Com::Theke::INNReach::Contribution->new;
    # my $response = $innreach->post_request(
    #     {   endpoint    => "/innreach/v2/circ/owningsitecancel/$trackingId/$centralCode",
    #         centralCode => $centralCode,
    #         data        => {
    #             localBibId => undef,
    #             reason     => '',
    #             reasonCode => '7',
    #             patronName => $patronName
    #         }
    #     }
    # );

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

## Helpers

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

=head1 AUTHORS

Tomás Cohen Arazi <tomascohen@theke.io>

=cut

1;
