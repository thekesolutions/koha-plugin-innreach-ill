package Koha::Plugin::Com::Theke::INNReach::Contribution;

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

use Encode qw{ encode decode };
use HTTP::Request::Common qw{ DELETE GET POST PUT };
use JSON qw{ encode_json decode_json };
use MARC::Record;
use MARC::File::XML;
use MIME::Base64 qw{ encode_base64 };
use Try::Tiny;

use Koha::Biblios;
use Koha::Biblio::Metadatas;
use Koha::Libraries;

use Koha::Plugin::Com::Theke::INNReach;
use Koha::Plugin::Com::Theke::INNReach::OAuth2;

use Data::Printer colored => 1;
binmode STDOUT, ':encoding(UTF-8)';

use base qw(Class::Accessor);

__PACKAGE__->mk_accessors(qw( oauth2 config ));

=head1 Koha::Plugin::Com::Theke::INNReach::Contribution

A class implementing required methods for data contribution to the 
configured D2IR Central server.

=head2 Class methods

=head3 new

Class constructor

=cut

sub new {
    my ($class) = @_;

    my $args;

    try {
        $args->{config} = Koha::Plugin::Com::Theke::INNReach->new()->configuration;
        $args->{oauth2} = Koha::Plugin::Com::Theke::INNReach::OAuth2->new(
            {   client_id     => $args->{config}->{client_id},
                client_secret => $args->{config}->{client_secret},
                api_base_url  => $args->{config}->{api_base_url}
            }
        );
    }
    catch {
        die "$_";
    };

    my $self = $class->SUPER::new($args);

    bless $self, $class;
    return $self;
}

=head3 contribute_bib

    my $res = $contribution->contribute_bib({ bibId => $bibId, [ centralServer => $centralServer ] });

By default it sends the MARC record and the required metadata
to all Central servers. If a centralServer parameter is passed,
then data is sent only to the specified one.

POST /innreach/v2/contribution/bib/<bibId>

=cut

sub contribute_bib {
    my ($self, $args) = @_;

    my $bibId = $args->{bibId};
    die "bibId is mandatory" unless $bibId;

    my ( $biblio, $metadata, $record );

    try {
        $biblio   = Koha::Biblios->find( $bibId );
        $metadata = Koha::Biblio::Metadatas->find(
            { biblionumber => $bibId,
              format       => 'marcxml',
              marcflavour  => 'marc21'
            }
        );
        $record = eval {
            MARC::Record::new_from_xml( $metadata->metadata, 'utf-8', $metadata->marcflavour );
        };
    }
    catch {
        die "Problem with requested biblio ($bibId)";
    };

    # Got the biblio, POST it
    my $suppress = 'n'; # expected default
    my $suppress_subfield = $record->subfield('942','n');
    if ( $suppress_subfield ) {
        $suppress = 'y';
    }

    # delete all local fields ("Omit 9XX fields" rule)
    my @local = $record->field('9..');
    $record->delete_fields(@local);
    # Encode ISO2709 record
    my $encoded_record = encode_base64( encode("UTF-8",$record->as_usmarc), "" );

    my $data = {
        bibId           => "$bibId",
        marc21BibFormat => 'ISO2709', # Only supported value
        marc21BibData   => $encoded_record,
        titleHoldCount  => $biblio->holds->count + 0,
        itemCount       => $biblio->items->count + 0,
        suppress        => $suppress
    };

    my @central_servers;
    if ( $args->{centralServer} ) {
        push @central_servers, $args->{centralServer};
    }
    else {
        @central_servers = @{ $self->config->{centralServers} };
    }

    my @errors;

    for my $central_server (@central_servers) {
        my $response = $self->post_request(
            {   endpoint    => '/innreach/v2/contribution/bib/' . $bibId,
                centralCode => $central_server,
                data        => $data
            }
        );
        warn p( $response )
            if $response->is_error or $ENV{DEBUG};
        warn p( $data )
            if $response->is_error or $ENV{DEBUG};

        unless ( $response->is_success ) {
            push @errors, $response->status_line;
        }
    }

    return @errors if scalar @errors;
}

=head3 contribute_batch_items

    my $res = $contribution->contribute_batch_items(
        {   bibId => $bibId,
            item  => $item,
            [ centralServer => $centralServer ]
        }
    );

Sends item information (for adding or modifying) to the central server(s). the
I<bibId> param is mandatory. I<item> is optional, and needs to be a Koha::Item
object, belonging to the biblio identified by bibId.

POST /innreach/v2/contribution/items/<bibId>

=cut

sub contribute_batch_items {
    my ($self, $args) = @_;

    my $bibId = $args->{bibId};
    die "bibId is mandatory" unless $bibId;

    my $biblio = Koha::Biblios->find( $bibId );
    unless ( $biblio ) {
        die "Biblio not found ($bibId)";
    }

    my @items;

    my $THE_item = $args->{item};
    if ( $THE_item and ref($THE_item) eq 'Koha::Item' ) {
        push @items, $THE_item;
    }
    else {
        @items = $biblio->items->as_list;
    }

    my @itemInfo;

    foreach my $item ( @items ) {
        unless ( $item->biblionumber == $bibId ) {
            die "Item (" . $item->itemnumber . ") doesn't belong to bib record ($bibId)";
        }

        my $itemInfo = {
            itemId            => $item->itemnumber,
            agencyCode        => $self->config->{mainAgency},
            centralItemType   => $self->config->{local_to_central_itype}->{$item->effective_itemtype},
            locationKey       => lc( $item->homebranch ),
            itemCircStatus    => $self->item_circ_status({ item => $item }),
            holdCount         => $item->current_holds->count + 0,
            dueDateTime       => ($item->onloan) ? dt_from_string( $item->onloan )->epoch : undef,
            callNumber        => $item->itemcallnumber,
            volumeDesignation => undef, # TODO
            copyNumber        => $item->copynumber, # TODO
          # marc856URI        => undef, # We really don't have this concept in Koha
          # marc856PublicNote => undef, # We really don't have this concept in Koha
            itemNote          => $item->itemnotes,
            suppress          => 'n' # TODO: revisit
        };

        push @itemInfo, $itemInfo;
    }

    my @central_servers;
    if ( $args->{centralServer} ) {
        push @central_servers, $args->{centralServer};
    }
    else {
        @central_servers = @{ $self->config->{centralServers} };
    }

    my @errors;

    for my $central_server (@central_servers) {
        my $response = $self->post_request(
            {   endpoint    => '/innreach/v2/contribution/items/' . $bibId,
                centralCode => $central_server,
                data        => { itemInfo => \@itemInfo }
            }
        );
        warn p( $response )
            if $response->is_error or $ENV{DEBUG};

        unless ( $response->is_success ) {
            push @errors, $response->status_line;
        }
    }

    return @errors if scalar @errors;
}

=head3 update_item_status

    my $res = $contribution->update_item_status({ itemId => $itemId, [ centralServer => $centralServer ] });

It sends updated item status to the central server(s).

POST /innreach/v2/contribution/bibstatus/<itemId>

=cut

sub update_item_status {
    my ($self, $args) = @_;

    my $itemId = $args->{itemId};

    die "itemId is mandatory"
        unless $itemId;

    my $item;

    my @errors;

    try {
        $item = Koha::Items->find( $itemId );
        my $data = {
            itemCircStatus => $self->item_circ_status({ item => $item }),
            holdCount      => $item->current_holds->count,
            dueDateTime    => ($item->onloan) ? dt_from_string( $item->onloan )->epoch : undef,
        };

        my @central_servers;
        if ( $args->{centralServer} ) {
            push @central_servers, $args->{centralServer};
        }
        else {
            @central_servers = @{ $self->config->{centralServers} };
        }

        for my $central_server (@central_servers) {
            my $response = $self->post_request(
                {   endpoint    => '/innreach/v2/contribution/itemstatus/' . $itemId,
                    centralCode => $central_server,
                    data        => $data
                }
            );
            warn p( $response )
                if $response->is_error or $ENV{DEBUG};

            unless ( $response->is_success ) {
                push @errors, $response->status_line;
            }
        }
    }
    catch {
        die "Problem updating requested item ($itemId)";
    };

    return @errors if scalar @errors;
}

=head3 decontribute_bib

    my $res = $contribution->decontribute_bib(
        {   bibId => $bibId,
            [ centralServer => $centralServer ]
        }
    );

Makes an API request to INN-Reach central server(s) to decontribute the specified record.

DELETE /innreach/v2/contribution/bib/<bibId>

=cut

sub decontribute_bib {
    my ($self, $args) = @_;

    my $bibId = $args->{bibId};
    die "bibId is mandatory" unless $bibId;

    my @central_servers;
    if ( $args->{centralServer} ) {
        push @central_servers, $args->{centralServer};
    }
    else {
        @central_servers = @{ $self->config->{centralServers} };
    }

    my @errors;

    for my $central_server (@central_servers) {
        my $response = $self->delete_request(
            {   endpoint    => '/innreach/v2/contribution/bib/' . $bibId,
                centralCode => $central_server
            }
        );
        warn p( $response )
            if $response->is_error or $ENV{DEBUG};

        unless ( $response->is_success ) {
            push @errors, $response->status_line;
        }
    }

    return @errors if scalar @errors;
}

=head3 decontribute_item

    my $res = $contribution->decontribute_item(
        {   itemId => $itemId,
            [ centralServer => $centralServer ]
        }
    );

Makes an API request to INN-Reach central server(s) to decontribute the specified item.

DELETE /innreach/v2/contribution/item/<itemId>

=cut

sub decontribute_item {
    my ($self, $args) = @_;

    my $itemId = $args->{itemId};
    die "itemId is mandatory" unless $itemId;

    my @central_servers;
    if ( $args->{centralServer} ) {
        push @central_servers, $args->{centralServer};
    }
    else {
        @central_servers = @{ $self->config->{centralServers} };
    }

    my @errors;

    for my $central_server (@central_servers) {
        my $response = $self->delete_request(
            {   endpoint    => '/innreach/v2/contribution/item/' . $itemId,
                centralCode => $central_server
            }
        );
        warn p( $response )
            if $response->is_error or $ENV{DEBUG};

        unless ( $response->is_success ) {
            push @errors, $response->status_line;
        }
    }

    return @errors if scalar @errors;
}

=head3 update_bib_status

    my $res = $contribution->update_bib_status({ bibId => $bibId, [ centralServer => $centralServer ] });

It sends updated bib status to the central server(s).

POST /innreach/v2/contribution/bibstatus/<bibId>

=cut

sub update_bib_status {
    my ($self, $args) = @_;

    my $bibId = $args->{bibId};
    die "bibId is mandatory" unless $bibId;

    my ( $biblio, $metadata, $record );

    my @errors;

    try {
        $biblio   = Koha::Biblios->find( $bibId );
        my $data = {
            titleHoldCount  => $biblio->holds->count,
            itemCount       => $biblio->items->count,
        };

        my @central_servers;
        if ( $args->{centralServer} ) {
            push @central_servers, $args->{centralServer};
        }
        else {
            @central_servers = @{ $self->config->{centralServers} };
        }

        for my $central_server (@central_servers) {
            my $response = $self->post_request(
                {   endpoint    => '/innreach/v2/contribution/bibstatus/' . $bibId,
                    centralCode => $central_server,
                    data        => $data
                }
            );
            warn p( $response )
                if $response->is_error or $ENV{DEBUG};

            unless ( $response->is_success ) {
                push @errors, $response->status_line;
            }
        }
    }
    catch {
        die "Problem updating requested biblio ($bibId)";
    };

    return @errors if scalar @errors;
}

=head3 upload_locations_list

    my $res = $contribution->upload_locations_list({ [ centralServer => $centralServer ] });

Sends an updated list of libraries/branches to the central server(s).

POST /innreach/v2/contribution/locations

=cut

sub upload_locations_list {
    my ($self, $args) = @_;

    try {
        my @locationList;

        my $libraries = Koha::Libraries->search;

        while ( my $library = $libraries->next ) {
            push @locationList, {
                locationKey => lc($library->branchcode),
                description => $library->branchname
            }
        }

        my @central_servers;
        if ( $args->{centralServer} ) {
            push @central_servers, $args->{centralServer};
        }
        else {
            @central_servers = @{ $self->config->{centralServers} };
        }

        for my $central_server (@central_servers) {
            my $response = $self->post_request(
                {   endpoint    => '/innreach/v2/contribution/locations',
                    centralCode => $central_server,
                    data        => { locationList => \@locationList }
                }
            );
            warn p( $response )
                if $response->is_error or $ENV{DEBUG};
        }
    }
    catch {
        die "Problem uploading locations list";
    };
}

=head3 upload_single_location

    my $res = $contribution->upload_single_location(
        { library => $library,
          [ centralServer => $centralServer ]
        }
    );

Sends a single library/branch to the central server(s).

POST /innreach/v2/contribution/locations/<locationKey>

=cut

sub upload_single_location {
    my ($self, $args) = @_;

    my $library = $args->{library};
    die 'Mandatory parameter is missing: library'
        unless $library;

    try {

        my $locationKey = lc($library->branchcode);

        my @central_servers;
        if ( $args->{centralServer} ) {
            push @central_servers, $args->{centralServer};
        }
        else {
            @central_servers = @{ $self->config->{centralServers} };
        }

        for my $central_server (@central_servers) {
            my $response = $self->post_request(
                {   endpoint    => '/innreach/v2/contribution/locations/' . $locationKey,
                    centralCode => $central_server,
                    data        => { description => $library->branchname }
                }
            );
            warn p( $response )
                if $response->is_error or $ENV{DEBUG};
        }
    }
    catch {
        die "Problem uploading the required location";
    };
}

=head3 update_single_location

    my $res = $contribution->update_single_location(
        { library => $library,
          [ centralServer => $centralServer ]
        }
    );

Sends a single library/branch to the central server(s).

PUT /innreach/v2/contribution/locations/<locationKey>

=cut

sub update_single_location {
    my ($self, $args) = @_;

    my $library = $args->{library};
    die 'Mandatory parameter is missing: library'
        unless $library;

    try {

        my $locationKey = lc($library->branchcode);

        my @central_servers;
        if ( $args->{centralServer} ) {
            push @central_servers, $args->{centralServer};
        }
        else {
            @central_servers = @{ $self->config->{centralServers} };
        }

        for my $central_server (@central_servers) {
            my $response = $self->put_request(
                {   endpoint    => '/innreach/v2/contribution/locations/' . $locationKey,
                    centralCode => $central_server,
                    data        => { description => $library->branchname }
                }
            );
            warn p( $response )
                if $response->is_error or $ENV{DEBUG};
        }
    }
    catch {
        die "Problem updating the required location";
    };
}

=head3 delete_single_location

    my $res = $contribution->delete_single_location(
        { library_id => $library_id,
          [ centralServer => $centralServer ]
        }
    );

Sends a single library/branch to the central server(s).

DELETE /innreach/v2/location/<locationKey>

=cut

sub delete_single_location {
    my ($self, $args) = @_;

    my $library_id = $args->{library_id};
    die 'Mandatory parameter is missing: library_id'
        unless $library_id;

    try {

        my $locationKey = lc($library_id);

        my @central_servers;
        if ( $args->{centralServer} ) {
            push @central_servers, $args->{centralServer};
        }
        else {
            @central_servers = @{ $self->config->{centralServers} };
        }

        for my $central_server (@central_servers) {
            my $response = $self->delete_request(
                {   endpoint    => '/innreach/v2/location/' . $locationKey,
                    centralCode => $central_server
                }
            );
            warn p( $response )
                if $response->is_error or $ENV{DEBUG};
        }
    }
    catch {
        die "Problem deleting the required location";
    };
}

=head3 get_central_item_types

    my $res = $contribution->get_central_item_types(
        { centralServer => $centralServer }
    );

Sends a a request for defined item types to a central server.

GET /innreach/v2/contribution/itemtypes

=cut

sub get_central_item_types {
    my ($self, $args) = @_;

    my $response;

    try {

        my $centralServer = $args->{centralServer};
        $response = $self->get_request(
            {   endpoint    => '/innreach/v2/contribution/itemtypes',
                centralCode => $centralServer
            }
        );
        warn p( $response )
            if $response->is_error or $ENV{DEBUG};
    }
    catch {
        die "Problem fetching the item types list";
    };

    return decode_json($response->decoded_content)->{itemTypeList};
}

=head3 get_locations_list

    my $res = $contribution->get_locations_list(
        { centralServer => $centralServer }
    );

Sends a a request for defined locations to a central server.

GET /innreach/v2/contribution/locations

=cut

sub get_locations_list {
    my ($self, $args) = @_;

    my $response;

    try {
        my $centralServer = $args->{centralServer};
        $response = $self->get_request(
            {   endpoint    => '/innreach/v2/contribution/locations',
                centralCode => $centralServer
            }
        );
        warn p($response)
          if $response->is_error or $ENV{DEBUG};
    }
    catch {
        die "Problem fetching the locations list";
    };

    return decode_json(encode('UTF-8',$response->content))->{locationList};
}

=head3 get_central_patron_types_list

    my $res = $contribution->get_central_patron_types_list(
        { centralServer => $centralServer }
    );

Sends a a request for defined locations to a central server.

GET /innreach/v2/circ/patrontypes

=cut

sub get_central_patron_types_list {
    my ($self, $args) = @_;

    my $response;

    try {

        my $centralServer = $args->{centralServer};
        $response = $self->get_request(
            {   endpoint    => '/innreach/v2/circ/patrontypes',
                centralCode => $centralServer
            }
        );
        warn p( $response )
            if $response->is_error or $ENV{DEBUG};
    }
    catch {
        die "Problem fetching the central patron types list";
    };

    return decode_json(encode('UTF-8',$response->content))->{patronTypeList};
}

=head2 Internal methods

=head3 token

Method for retrieving a valid access token

=cut

sub token {
    my ($self) = @_;

    return $self->{oauth2}->get_token;
}

=head3 post_request

Generic request for POST

=cut

sub post_request {
    my ($self, $args) = @_;

    my $request =
        POST(
            $self->config->{api_base_url} . '/' . $args->{endpoint},
            'Authorization' => "Bearer " . $self->token,
            'X-From-Code'   => $self->config->{localServerCode},
            'X-To-Code'     => $args->{centralCode},
            'Accept'        => "application/json",
            'Content-Type'  => "application/json",
            'Content'       => ( exists $args->{data} ) ? encode_json( $args->{data} ) : undef
        );

    if ( $self->config->{debug_mode} ) {
        warn p( $request );
    }

    return $self->oauth2->ua->request(
        $request
    );
}

=head3 put_request

Generic request for PUT

=cut

sub put_request {
    my ($self, $args) = @_;

    my $request =
        PUT($self->config->{api_base_url} . '/' . $args->{endpoint},
            'Authorization' => "Bearer " . $self->token,
            'X-From-Code'   => $self->config->{localServerCode},
            'X-To-Code'     => $args->{centralCode},
            'Accept'        => "application/json",
            'Content-Type'  => "application/json",
            'Content'       => encode_json( $args->{data} )
        );

    if ( $self->config->{debug_mode} ) {
        warn p( $request );
    }

    return $self->oauth2->ua->request(
        $request
    );
}

=head3 get_request

Generic request for GET

=cut

sub get_request {
    my ($self, $args) = @_;

    my $request =
        GET($self->config->{api_base_url} . '/' . $args->{endpoint},
            'Authorization' => "Bearer " . $self->token,
            'X-From-Code'   => $self->config->{localServerCode},
            'X-To-Code'     => $args->{centralCode},
            'Accept'        => "application/json",
            'Content-Type'  => "application/json"
        );

    if ( $self->config->{debug_mode} ) {
        warn p( $request );
    }

    return $self->oauth2->ua->request(
        $request
    );
}

=head3 delete_request

Generic request for DELETE

=cut

sub delete_request {
    my ($self, $args) = @_;

    my $request =
        DELETE(
            $self->config->{api_base_url} . '/' . $args->{endpoint},
            'Authorization' => "Bearer " . $self->token,
            'X-From-Code'   => $self->config->{localServerCode},
            'X-To-Code'     => $args->{centralCode},
            'Accept'        => "application/json",
        );

    if ( $self->config->{debug_mode} ) {
        warn p( $request );
    }

    return $self->oauth2->ua->request(
        $request
    );
}

=head3 item_circ_status

Calculates the value for itemCircStatus

=cut

sub item_circ_status {
    my ($self, $args) = @_;

    die "Mandatory parameter missing: item"
        unless exists $args->{item};

    my $item = $args->{item};
    die "Parameter type incorrect for item"
        unless ref($item) eq 'Koha::Item';

    my $status = 'Available';
    if ( $item->onloan ) {
        $status = 'On Loan';
    }
    elsif ( $item->withdrawn && $item->withdrawn > 0 ) {
        $status = 'Not Available';
    }
    elsif ( $item->notforloan ) {
        $status = 'Non-Lendable';
    }

    return $status;
}

1;
