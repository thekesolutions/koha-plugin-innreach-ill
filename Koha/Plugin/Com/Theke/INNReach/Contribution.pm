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
use List::MoreUtils qw(any);
use Mojo::JSON qw(decode_json encode_json);
use MARC::Record;
use MARC::File::XML;
use MIME::Base64 qw{ encode_base64 };
use Try::Tiny;

use Koha::Biblios;
use Koha::Biblio::Metadatas;
use Koha::DateUtils qw(dt_from_string);
use Koha::Items;
use Koha::Libraries;

use Koha::Plugin::Com::Theke::INNReach;
use Koha::Plugin::Com::Theke::INNReach::Exceptions;
use Koha::Plugin::Com::Theke::INNReach::OAuth2;

use Data::Printer colored => 1;
binmode STDOUT, ':encoding(UTF-8)';

use base qw(Class::Accessor);

__PACKAGE__->mk_accessors(qw( oauth2 config centralServers plugin ));

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
        my $plugin = Koha::Plugin::Com::Theke::INNReach->new;
        $args->{plugin} = $plugin;
        $args->{config} = $plugin->configuration;
        my @centralServers = $plugin->central_servers;
        $args->{centralServers} = \@centralServers;
        foreach my $centralCode ( @centralServers ) {
            $args->{oauth2}->{$centralCode} = Koha::Plugin::Com::Theke::INNReach::OAuth2->new(
                {   client_id          => $args->{config}->{$centralCode}->{client_id},
                    client_secret      => $args->{config}->{$centralCode}->{client_secret},
                    api_base_url       => $args->{config}->{$centralCode}->{api_base_url},
                    api_token_base_url => $args->{config}->{$centralCode}->{api_token_base_url},
                    local_server_code  => $args->{config}->{$centralCode}->{localServerCode}
                }
            );
        }
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
    INNReach::Ill::MissingParameter->throw( param =>  "bibId" )
        unless $bibId;

    my $biblio = Koha::Biblios->find({ biblionumber => $bibId });

    unless ( $biblio ) {
        INNReach::Ill::UnknownBiblioId->throw( biblio_id => $bibId );
    }

    my $record = $biblio->metadata->record;

    unless ( $record ) {
        INNReach::Ill::UnknownBiblioId->throw( "Cannot retrieve record metadata" );
    }

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
        @central_servers = @{ $self->{centralServers} };
    }

    my $errors;

    for my $central_server (@central_servers) {
        my $response = $self->oauth2->{$central_server}->post_request(
            {   endpoint    => '/innreach/v2/contribution/bib/' . $bibId,
                centralCode => $central_server,
                data        => $data
            }
        );

        if ( !$response->is_success ) {    # HTTP code is not 2xx
            $errors->{$central_server} = $response->status_line;
        } else {                           # III encoding errors in the response body of a 2xx
            my $response_content = decode_json( $response->decoded_content );
            if ( $response_content->{status} eq 'failed' ) {
                my @iii_errors = $response_content->{errors};

                # we pick the first one
                my $THE_error = $iii_errors[0][0];
                $errors->{$central_server} = $THE_error->{reason} . q{: } . join( q{ | }, @{ $THE_error->{messages} } );
            }
            else {
                $self->mark_biblio_as_contributed(
                    {
                        biblio_id      => $bibId,
                        central_server => $central_server,
                    }
                );
            }
        }
    }

    return $errors if $errors;
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
    INNReach::Ill::MissingParameter->throw( param =>  "bibId" )
        unless $bibId;

    my $biblio = Koha::Biblios->find( $bibId );
    unless ( $biblio ) {
        INNReach::Ill::UnknownBiblioId->throw( biblio_id => $bibId );
    }

    my @items;

    my $THE_item = $args->{item};
    if ( $THE_item and ref($THE_item) eq 'Koha::Item' ) {
        push @items, $THE_item;
    }
    else {
        @items = $biblio->items->as_list;
    }

    my @central_servers;
    if ( $args->{centralServer} ) {
        push @central_servers, $args->{centralServer};
    }
    else {
        @central_servers = @{ $self->{centralServers} };
    }

    my $errors;

    for my $central_server (@central_servers) {

        my @itemInfo;

        foreach my $item ( @items ) {
            unless ( $item->biblionumber == $bibId ) {
                die "Item (" . $item->itemnumber . ") doesn't belong to bib record ($bibId)";
            }

            my $centralItemType = $self->config->{$central_server}->{local_to_central_itype}->{$item->effective_itemtype};
            my $locationKey = $self->config->{$central_server}->{library_to_location}->{$item->homebranch}->{location};

            # Skip the item if has unmapped values (that are relevant)
            unless ( $centralItemType && $locationKey ) {
                next;
            }

            my $itemInfo = {
                itemId            => $item->itemnumber,
                agencyCode        => $self->config->{$central_server}->{mainAgency},
                centralItemType   => $centralItemType,
                locationKey       => $locationKey,
                itemCircStatus    => $self->item_circ_status({ item => $item }),
                holdCount         => 0,
                dueDateTime       => ($item->onloan) ? dt_from_string( $item->onloan )->epoch : undef,
                callNumber        => $item->itemcallnumber,
                volumeDesignation => $item->enumchron,
                copyNumber        => $item->copynumber,
            # marc856URI        => undef, # We really don't have this concept in Koha
            # marc856PublicNote => undef, # We really don't have this concept in Koha
                itemNote          => $item->itemnotes,
                suppress          => 'n' # TODO: revisit
            };

            push @itemInfo, $itemInfo;
        }

        my $response = $self->oauth2->{$central_server}->post_request(
            {   endpoint    => '/innreach/v2/contribution/items/' . $bibId,
                centralCode => $central_server,
                data        => { itemInfo => \@itemInfo }
            }
        );

        if ( !$response->is_success ) {    # HTTP code is not 2xx
            $errors->{$central_server} = $response->status_line;
        } else {                           # III encoding errors in the response body of a 2xx
            my $response_content = decode_json( $response->decoded_content );
            if ( $response_content->{status} eq 'failed' ) {
                my @iii_errors = $response_content->{errors};

                # we pick the first one
                my $THE_error = $iii_errors[0][0];
                $errors->{$central_server} = $THE_error->{reason} . q{: } . join( q{ | }, @{ $THE_error->{messages} } );
            }
            else {
                foreach my $item (@items) {
                    $self->mark_item_as_contributed(
                        {
                            central_server => $central_server,
                            item_id        => $item->id,
                        }
                    );
                }
            }
        }
    }

    return $errors if $errors;
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

    my $errors;

    try {
        $item = Koha::Items->find( $itemId );

        my @central_servers;
        if ( $args->{centralServer} ) {
            push @central_servers, $args->{centralServer};
        }
        else {
            @central_servers = @{ $self->{centralServers} };
        }

        for my $central_server (@central_servers) {
            my $data = {
                itemCircStatus => $self->item_circ_status({ item => $item }),
                holdCount      => 0,
                dueDateTime    => ($item->onloan) ? dt_from_string( $item->onloan )->epoch : undef,
            };

            my $response = $self->oauth2->{$central_server}->post_request(
                {   endpoint    => '/innreach/v2/contribution/itemstatus/' . $itemId,
                    centralCode => $central_server,
                    data        => $data
                }
            );

            if ( !$response->is_success ) {    # HTTP code is not 2xx
                $errors->{$central_server} = $response->status_line;
            } else {                           # III encoding errors in the response body of a 2xx
                my $response_content = decode_json( $response->decoded_content );
                if ( $response_content->{status} eq 'failed' ) {
                    my @iii_errors = $response_content->{errors};

                    # we pick the first one
                    my $THE_error = $iii_errors[0][0];
                    $errors->{$central_server} = $THE_error->{reason} . q{: } . join( q{ | }, @{ $THE_error->{messages} } );
                }
            }
        }
    }
    catch {
        die "Problem updating requested item ($itemId)";
    };

    return $errors if $errors;
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
    INNReach::Ill::MissingParameter->throw( param =>  "bibId" )
        unless $bibId;

    my @central_servers;
    if ( $args->{centralServer} ) {
        push @central_servers, $args->{centralServer};
    }
    else {
        @central_servers = @{ $self->{centralServers} };
    }

    my $errors;

    for my $central_server (@central_servers) {
        my $response = $self->oauth2->{$central_server}->delete_request(
            {   endpoint    => '/innreach/v2/contribution/bib/' . $bibId,
                centralCode => $central_server
            }
        );

        if ( !$response->is_success ) {    # HTTP code is not 2xx
            $errors->{$central_server} = $response->status_line;
        } else {                           # III encoding errors in the response body of a 2xx
            my $response_content = decode_json( $response->decoded_content );
            if ( $response_content->{status} eq 'failed' ) {
                my @iii_errors = $response_content->{errors};

                # we pick the first one
                my $THE_error = $iii_errors[0][0];
                $errors->{$central_server} = $THE_error->{reason} . q{: } . join( q{ | }, @{ $THE_error->{messages} } );
            }
            else {
                $self->unmark_biblio_as_contributed(
                    {
                        biblio_id      => $bibId,
                        central_server => $central_server,
                    }
                );
            }
        }
    }
    return $errors if $errors;
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
        @central_servers = @{ $self->{centralServers} };
    }

    my $errors;

    for my $central_server (@central_servers) {
        my $response = $self->oauth2->{$central_server}->delete_request(
            {   endpoint    => '/innreach/v2/contribution/item/' . $itemId,
                centralCode => $central_server
            }
        );

        if ( !$response->is_success ) {    # HTTP code is not 2xx
            $errors->{$central_server} = $response->status_line;
        } else {                           # III encoding errors in the response body of a 2xx
            my $response_content = decode_json( $response->decoded_content );
            if ( $response_content->{status} eq 'failed' ) {
                my @iii_errors = $response_content->{errors};

                # we pick the first one
                my $THE_error = $iii_errors[0][0];
                $errors->{$central_server} = $THE_error->{reason} . q{: } . join( q{ | }, @{ $THE_error->{messages} } );
            }
            else {
                $self->unmark_item_as_contributed(
                    {
                        central_server => $central_server,
                        item_id        => $itemId,
                    }
                );
            }
        }
    }

    return $errors if $errors;
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

    my $errors;

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
            @central_servers = @{ $self->{centralServers} };
        }

        for my $central_server (@central_servers) {
            my $response = $self->oauth2->{$central_server}->post_request(
                {   endpoint    => '/innreach/v2/contribution/bibstatus/' . $bibId,
                    centralCode => $central_server,
                    data        => $data
                }
            );

            if ( !$response->is_success ) {    # HTTP code is not 2xx
                $errors->{$central_server} = $response->status_line;
            } else {                           # III encoding errors in the response body of a 2xx
                my $response_content = decode_json( $response->decoded_content );
                if ( $response_content->{status} eq 'failed' ) {
                    my @iii_errors = $response_content->{errors};

                    # we pick the first one
                    my $THE_error = $iii_errors[0][0];
                    $errors->{$central_server} = $THE_error->{reason} . q{: } . join( q{ | }, @{ $THE_error->{messages} } );
                }
            }
        }
    }
    catch {
        die "Problem updating requested biblio ($bibId)";
    };

    return $errors if $errors;
}

=head3 upload_locations_list

    my $res = $contribution->upload_locations_list({ [ centralServer => $centralServer ] });

Sends an updated list of libraries/branches to the central server(s).

POST /innreach/v2/contribution/locations

=cut

sub upload_locations_list {
    my ( $self, $args ) = @_;

    try {
        my @locationList;

        # Get the branch codes
        my @libraries = Koha::Libraries->search->get_column('branchcode');

        my @central_servers;
        if ( $args->{centralServer} ) {
            push @central_servers, $args->{centralServer};
        }
        else {
            @central_servers = @{ $self->{centralServers} };
        }

        for my $central_server (@central_servers) {

            # The locationList is built for each central server as the mapping
            # is specific to that central server
            my @locationList;
            foreach my $library (@libraries) {
                push @locationList,
                  {
                    locationKey => $self->{config}->{$central_server}->{library_to_location}->{$library}->{location},
                    description => $self->{config}->{$central_server}->{library_to_location}->{$library}->{description}
                  }
                  if exists $self->{config}->{$central_server}->{library_to_location}->{$library};
            }

            my $response = $self->oauth2->{$central_server}->post_request(
                {
                    endpoint    => '/innreach/v2/contribution/locations',
                    centralCode => $central_server,
                    data        => { locationList => \@locationList }
                }
            );
            warn p($response)
              if $response->is_error or $ENV{DEBUG};
        }
    }
    catch {
        die "Problem uploading locations list";
    };
}

=head3 upload_single_location

    my $res = $contribution->upload_single_location(
        { library_id => $library_id,
          [ centralServer => $centralServer ]
        }
    );

Sends a single library/branch to the central server(s).

POST /innreach/v2/contribution/locations/<locationKey>

=cut

sub upload_single_location {
    my ($self, $args) = @_;

    my $library_id = $args->{library_id};
    die 'Mandatory parameter is missing: library'
        unless $library_id;

    my $library = Koha::Libraries->find($library_id);
    die "Invalid library_id: $library_id"
        unless $library;

    try {

        my @central_servers;
        if ( $args->{centralServer} ) {
            push @central_servers, $args->{centralServer};
        }
        else {
            @central_servers = @{ $self->{centralServers} };
        }

        for my $central_server (@central_servers) {

            if ( exists $self->{config}->{$central_server}->{library_to_location}->{$library_id} ) {

                my $locationKey = $self->{config}->{$central_server}->{library_to_location}->{$library_id}->{location};
                my $description = $self->{config}->{$central_server}->{library_to_location}->{$library_id}->{description};

                unless ($description) {
                    $description = $library->branchname;
                    warn "Mapped library lacks description ($library_id).";
                }

                my $response = $self->oauth2->{$central_server}->post_request(
                    {   endpoint    => '/innreach/v2/location/' . $locationKey,
                        centralCode => $central_server,
                        data        => { description => $description }
                    }
                );
                warn p( $response )
                    if $response->is_error or $ENV{DEBUG};
            }
        }
    }
    catch {
        die "Problem uploading the required location";
    };
}

=head3 update_single_location

    my $res = $contribution->update_single_location(
        { library_id => $library_id,
          [ centralServer => $centralServer ]
        }
    );

Sends a single library/branch to the central server(s).

PUT /innreach/v2/contribution/locations/<locationKey>

=cut

sub update_single_location {
    my ($self, $args) = @_;

    my $library_id = $args->{library_id};
    die 'Mandatory parameter is missing: library'
        unless $library_id;

    my $library = Koha::Libraries->find($library_id);
    die "Invalid library_id: $library_id"
        unless $library;

    try {

        my @central_servers;
        if ( $args->{centralServer} ) {
            push @central_servers, $args->{centralServer};
        }
        else {
            @central_servers = @{ $self->{centralServers} };
        }

        for my $central_server (@central_servers) {

            if ( exists $self->{config}->{$central_server}->{library_to_location}->{$library_id} ) {

                my $locationKey = $self->{config}->{$central_server}->{library_to_location}->{$library_id}->{location};
                my $description = $self->{config}->{$central_server}->{library_to_location}->{$library_id}->{description};

                unless ($description) {
                    $description = $library->branchname;
                    warn "Mapped library lacks description ($library_id).";
                }

                my $response = $self->oauth2->{$central_server}->put_request(
                    {   endpoint    => '/innreach/v2/location/' . $locationKey,
                        centralCode => $central_server,
                        data        => { description => $description }
                    }
                );
                warn p( $response )
                    if $response->is_error or $ENV{DEBUG};
            }
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

        my @central_servers;
        if ( $args->{centralServer} ) {
            push @central_servers, $args->{centralServer};
        }
        else {
            @central_servers = @{ $self->{centralServers} };
        }

        for my $central_server (@central_servers) {

            if ( exists $self->{config}->{$central_server}->{library_to_location}->{$library_id} ) {
                my $locationKey = $self->{config}->{$central_server}->{library_to_location}->{$library_id}->{location};

                my $response = $self->oauth2->{$central_server}->delete_request(
                    {   endpoint    => '/innreach/v2/location/' . $locationKey,
                        centralCode => $central_server
                    }
                );
                warn p( $response )
                    if $response->is_error or $ENV{DEBUG};
            }
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
        $response = $self->oauth2->{$centralServer}->get_request(
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
        $response = $self->oauth2->{$centralServer}->get_request(
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

=head3 get_agencies_list

    my $res = $contribution->get_agencies_list(
        { centralServer => $centralServer }
    );

Sends a a request for defined agencies to a central server.

GET /innreach/v2/contribution/agencies

=cut

sub get_agencies_list {
    my ($self, $args) = @_;

    my $response;

    try {
        my $centralServer = $args->{centralServer};
        $response = $self->oauth2->{$centralServer}->get_request(
            {   endpoint    => '/innreach/v2/contribution/localservers',
                centralCode => $centralServer
            }
        );
        warn p($response)
          if $response->is_error or $ENV{DEBUG};
    }
    catch {
        die "Problem fetching the agencies list";
    };

    return decode_json(encode('UTF-8',$response->content))->{localServerList};
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
        $response = $self->oauth2->{$centralServer}->get_request(
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

=head3 notify_borrower_renew

    my $res = $contribution->notify_borrower_renew(
        {
            item_id => $item_id,
            payload => $payload,
        }
    );

Notifies the relevant central server that a renewal took place.

POST /innreach/v2/circ/borrowerrenew/$trackingId/$centralCode"
{
    "dueDateTime": "2020-06-26 18:03:20+00:00"
}

=cut

sub notify_borrower_renew {
    my ($self, $args) = @_;

    my $item_id  = $args->{item_id};
    my $date_due = $args->{date_due};

    my $req = $self->get_ill_request_from_item_id(
        {
            item_id => $item_id,
            status  => 'B_ITEM_RECEIVED',
        }
    );

    INNReach::Ill::InconsistentStatus->throw(
        expected_status => 'B_ITEM_RECEIVED'
    ) unless $req;

    my $response;

    return try {

        my $trackingId  = $req->illrequestattributes->search({ type => 'trackingId'  })->next->value;
        my $centralCode = $req->illrequestattributes->search({ type => 'centralCode' })->next->value;

        $response = $self->oauth2->{$centralCode}->post_request(
            {
                endpoint    => "/innreach/v2/circ/borrowerrenew/$trackingId/$centralCode",
                centralCode => $centralCode,
                data        => {
                    dueDateTime => dt_from_string( $date_due )->epoch
                }
            }
        );

        if ( $response->is_error ) {

            warn p( $response )
                if $ENV{DEBUG};

            return ($response);
        }

        return;
    }
    catch {
        INNReach::Ill->throw( "Unhandled exception: $_" );
    };
}

=head2 Internal methods

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

=head3 get_ill_request_from_item_id

This method retrieves the Koha::ILLRequest using a item_id.

=cut

sub get_ill_request_from_item_id {
    my ( $self, $args ) = @_;

    my $item_id = $args->{item_id};
    my $status  = $args->{status} // 'B_ITEM_SHIPPED'; # borrowing site, item shipped, receiving

    my $item = Koha::Items->find( $item_id );

    unless ( $item ) {
        INNReach::Ill::UnknownItemId->throw( item_id => $item_id );
    }

    my $biblio_id = $item->biblionumber;

    my $reqs = Koha::Illrequests->search(
        {
            biblio_id => $biblio_id,
            status    => [
                $status
            ]
        }
    );

    if ( $reqs->count > 1 ) {
        warn "More than one ILL request for item_id ($item_id). Beware!";
    }

    return unless $reqs->count > 0;

    my $req = $reqs->next;
    # TODO: what about other stages? testing valid statuses?
    # TODO: Owning site use case?

    return $req;
}

=head3 should_item_be_contributed

    if ( $contribution->should_item_be_contributed({
                 item           => $item,
                 central_server => $central_server }})
       )
       { ... }

Returns a I<boolean> telling if the item should be contributed to the specified

=cut

sub should_item_be_contributed {
    my ( $self, $params ) = @_;

    my $item = $params->{item};

    INNReach::Ill::MissingParameter->throw( param => 'item' )
        unless $item;

    my $central_server = $params->{central_server};

    INNReach::Ill::MissingParameter->throw( param => 'central_server' )
        unless $central_server;

    INNReach::Ill::InvalidCentralserver->throw( central_server => $central_server )
        unless any { $_ eq $central_server } @{$self->{centralServers}};

    my $items_rs = Koha::Items->search({ itemnumber => $item->itemnumber });

    return $self->filter_items_by_contributable(
        {
            items          => $items_rs,
            central_server => $central_server
        }
    )->count > 0;
}

=head3 filter_items_by_contributable

    my $items = $contribution->filter_items_by_contributable(
        {
            items => $biblio->items,
            central_server => $central_server
        }
    );

Given a I<Koha::Items> iterator and a I<central server code>, it returns a new resultset,
filtered by the configured rules for the specified central server.

=cut

sub filter_items_by_contributable {
    my ( $self, $params ) = @_;

    my $items = $params->{items};

    INNReach::Ill::MissingParameter->throw( param => 'items' )
        unless $items;

    my $central_server = $params->{central_server};

    INNReach::Ill::MissingParameter->throw( param => 'central_server' )
        unless $central_server;

    INNReach::Ill::InvalidCentralserver->throw( central_server => $central_server )
        unless any { $_ eq $central_server } @{$self->{centralServers}};

    my $configuration = $self->config->{$central_server};

    if ( exists $configuration->{contribution}->{included_items} ) {
        # Allow-list case, overrides any deny-list setup
        if ( $configuration->{contribution}->{included_items} ) {
            # there are rules!
            $items = $items->search($configuration->{contribution}->{included_items});
        }
        else {
            $items = $items->empty # No items if the rules exist but are empty
        }
    }
    else {
        # Deny-list case
        if ( $configuration->{contribution}->{excluded_items} ) {
            # there are rules!
            $items = $items->search({ '-not' => $configuration->{contribution}->{excluded_items} });
        }
        # else {  } # no filter
    }

    return $items;
}

=head3 mark_biblio_as_contributed

    $plugin->mark_biblio_as_contributed(
        {
            central_server => $central_server,
            biblio_id      => $biblio_id
        }
    );

Method for marking an biblio as contributed.

=cut

sub mark_biblio_as_contributed {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(central_server biblio_id);
    foreach my $param ( @mandatory_params ) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    my $central_server = $params->{central_server};
    my $biblio_id      = $params->{biblio_id};

    my $dbh = C4::Context->dbh;
    my $contributed_biblios = $self->plugin->get_qualified_table_name('contributed_biblios');

    my $sth = $dbh->prepare(qq{
        SELECT COUNT(*) FROM $contributed_biblios
        WHERE central_server = ?
          AND biblio_id = ?;
    });

    $sth->execute($central_server, $biblio_id);
    my ($count) = $sth->fetchrow_array;

    if ($count) { # update
        $dbh->do(qq{
            UPDATE $contributed_biblios
            SET timestamp=NOW()
            WHERE central_server='$central_server'
              AND biblio_id='$biblio_id';
        });
    }
    else { # insert
        $dbh->do(qq{
            INSERT INTO $contributed_biblios
                (  central_server,     biblio_id )
            VALUES
                ( '$central_server', '$biblio_id' );
        });
    }

    return $self;
}

=head3 mark_item_as_contributed

    $plugin->mark_item_as_contributed(
        {
            central_server => $central_server,
            item_id        => $item_id
        }
    );

Method for marking an item as contributed.

=cut

sub mark_item_as_contributed {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(central_server item_id);
    foreach my $param ( @mandatory_params ) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    my $central_server = $params->{central_server};
    my $item_id        = $params->{item_id};

    my $dbh = C4::Context->dbh;
    my $contributed_items = $self->plugin->get_qualified_table_name('contributed_items');

    my $sth = $dbh->prepare(qq{
        SELECT COUNT(*) FROM $contributed_items
        WHERE central_server = ?
          AND item_id = ?;
    });

    $sth->execute($central_server, $item_id);
    my ($count) = $sth->fetchrow_array;

    if ($count) { # update
        $dbh->do(qq{
            UPDATE $contributed_items
            SET timestamp=NOW()
            WHERE central_server='$central_server'
              AND item_id='$item_id';
        });
    }
    else { # insert
        $dbh->do(qq{
            INSERT INTO $contributed_items
                (  central_server,     item_id )
            VALUES
                ( '$central_server', '$item_id' );
        });
    }

    return $self;
}

=head3 unmark_biblio_as_contributed

    $plugin->unmark_biblio_as_contributed(
        {
            central_server => $central_server,
            biblio_id      => $biblio_id
        }
    );

Method for marking an biblio as contributed.

=cut

sub unmark_biblio_as_contributed {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(central_server biblio_id);
    foreach my $param ( @mandatory_params ) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    my $central_server = $params->{central_server};
    my $biblio_id      = $params->{biblio_id};

    my $dbh = C4::Context->dbh;
    my $contributed_biblios = $self->plugin->get_qualified_table_name('contributed_biblios');

    $dbh->do(qq{
        DELETE FROM $contributed_biblios
        WHERE central_server='$central_server'
          AND      biblio_id='$biblio_id';
    });

    return $self;
}

=head3 unmark_item_as_contributed

    $plugin->unmark_item_as_contributed(
        {
            central_server => $central_server,
            item_id        => $item_id
        }
    );

Method for marking an item as contributed.

=cut

sub unmark_item_as_contributed {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(central_server item_id);
    foreach my $param ( @mandatory_params ) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    my $central_server = $params->{central_server};
    my $item_id        = $params->{item_id};

    my $dbh = C4::Context->dbh;
    my $contributed_items = $self->plugin->get_qualified_table_name('contributed_items');

    $dbh->do(qq{
        DELETE FROM $contributed_items
        WHERE central_server='$central_server'
          AND        item_id='$item_id';
    });

    return $self;
}

1;
