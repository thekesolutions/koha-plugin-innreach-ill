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

use DDP;
use Encode          qw{ encode decode };
use List::MoreUtils qw(any);
use Mojo::JSON      qw(decode_json encode_json);
use MARC::Record;
use MARC::File::XML;
use MIME::Base64 qw( encode_base64 );
use Try::Tiny    qw(catch try);

use C4::Context;

use Koha::Biblios;
use Koha::Biblio::Metadatas;
use Koha::DateUtils qw(dt_from_string);
use Koha::Items;
use Koha::Libraries;

use Koha::Plugin::Com::Theke::INNReach::Exceptions;

binmode STDOUT, ':encoding(UTF-8)';

=head1 Koha::Plugin::Com::Theke::INNReach::Contribution

A class implementing required methods for data contribution to the 
configured D2IR Central server.

=head2 Class methods

=head3 new

Class constructor

=cut

sub new {
    my ( $class, $params ) = @_;

    my $plugin = $params->{plugin};
    INNReach::Ill::MissingParameter->throw( param => "plugin" )
        unless $plugin && ref($plugin) eq 'Koha::Plugin::Com::Theke::INNReach';

    INNReach::Ill::MissingParameter->throw( param => "central_server" )
        unless $params->{central_server};

    my $self = {
        central_server  => $params->{central_server},
        central_servers => [ $plugin->central_servers ],
        config          => $plugin->configuration,
        plugin          => $plugin,
    };

    bless $self, $class;
    return $self;
}

=head3 contribute_bib

    my $res = $contribution->contribute_bib( { biblio_id => $biblio_id } );

It sends the MARC record and the required metadata to the Central Server. It performs a

    POST /innreach/v2/contribution/bib/<bibId>

=cut

sub contribute_bib {
    my ( $self, $args ) = @_;

    my $biblio_id = $args->{biblio_id};
    INNReach::Ill::MissingParameter->throw( param => "biblio_id" )
        unless $biblio_id;

    my $biblio = Koha::Biblios->find($biblio_id);

    unless ($biblio) {
        INNReach::Ill::UnknownBiblioId->throw( biblio_id => $biblio_id );
    }

    my $record = $biblio->metadata->record;

    unless ($record) {
        INNReach::Ill::UnknownBiblioId->throw("Cannot retrieve record metadata");
    }

    # Got the biblio, POST it
    my $suppress          = 'n';                               # expected default
    my $suppress_subfield = $record->subfield( '942', 'n' );
    if ($suppress_subfield) {
        $suppress = 'y';
    }

    # delete all local fields ("Omit 9XX fields" rule)
    my @local = $record->field('9..');
    $record->delete_fields(@local);

    # Encode ISO2709 record
    my $encoded_record = encode_base64( encode( "UTF-8", $record->as_usmarc ), "" );

    my $data = {
        bibId           => "$biblio_id",
        marc21BibFormat => 'ISO2709',                   # Only supported value
        marc21BibData   => $encoded_record,
        titleHoldCount  => $biblio->holds->count + 0,
        itemCount       => $biblio->items->count + 0,
        suppress        => $suppress
    };

    my $errors;

    my $response = $self->{plugin}->get_ua( $self->{central_server} )->post_request(
        {
            endpoint    => '/innreach/v2/contribution/bib/' . $biblio_id,
            centralCode => $self->{central_server},
            data        => $data
        }
    );

    if ( !$response->is_success ) {    # HTTP code is not 2xx
        $errors = $response->status_line;
    } else {                           # III encoding errors in the response body of a 2xx
        my $response_content = decode_json( $response->decoded_content );
        if ( $response_content->{status} eq 'failed' ) {
            my @iii_errors = $response_content->{errors};

            # we pick the first one
            my $THE_error = $iii_errors[0][0];
            $errors = $THE_error->{reason} . q{: } . join( q{ | }, @{ $THE_error->{messages} } );
        } else {
            $self->mark_biblio_as_contributed( { biblio_id => $biblio_id } );
        }
    }

    return $errors;
}

=head3 contribute_batch_items

    my $res = $contribution->contribute_batch_items(
        {
            biblio_id => $biblio->id,
            items     => $items
        }
    );

Sends item information (for adding or modifying) to the central server(s). the
I<biblio_id> param is mandatory. I<items> is mandatory and needs to be a
I<Koha::Items> iterator. All items need to belong to the biblio, otherwise 
an exception is thrown.

    POST /innreach/v2/contribution/items/<bibId>

=cut

sub contribute_batch_items {
    my ( $self, $args ) = @_;

    my $biblio_id = $args->{biblio_id};
    INNReach::Ill::MissingParameter->throw( param => "biblio_id" )
        unless $biblio_id;

    my $biblio = Koha::Biblios->find($biblio_id);
    unless ($biblio) {
        INNReach::Ill::UnknownBiblioId->throw( biblio_id => $biblio_id );
    }

    INNReach::Ill::MissingParameter->throw( param => "items" )
        unless $args->{items} && ref( $args->{items} ) eq 'Koha::Items';

    my @items = $args->{items}->as_list;

    # Error check before anything else
    foreach my $item (@items) {
        INNReach::Ill::BadParameter->throw(
            "Item (" . $item->itemnumber . ") doesn't belong to bib record ($biblio_id)" )
            unless $item->biblionumber == $biblio_id;
    }

    my $errors;

    my $central_server = $self->{central_server};
    my $configuration  = $self->{config}->{$central_server};

    unless ( $self->is_bib_contributed( { biblio_id => $biblio_id } ) ) {
        $self->contribute_bib( { biblio_id => $biblio_id } );
    }

    my $use_holding_library = exists $configuration->{contribution}->{use_holding_library}
        && $configuration->{contribution}->{use_holding_library};

    my @itemInfo;

    foreach my $item (@items) {
        my $itemInfo = $self->item_to_iteminfo( { item => $item, use_holding_library => $use_holding_library } );
        push @itemInfo, $itemInfo;
    }

    my $response = $self->{plugin}->get_ua($central_server)->post_request(
        {
            endpoint    => '/innreach/v2/contribution/items/' . $biblio_id,
            centralCode => $central_server,
            data        => { itemInfo => \@itemInfo }
        }
    );

    if ( !$response->is_success ) {    # HTTP code is not 2xx
        $errors = $response->status_line;
    } else {                           # III encoding errors in the response body of a 2xx
        my $response_content = decode_json( $response->decoded_content );

        if ( $response_content->{status} eq 'failed' ) {
            my @iii_errors = $response_content->{errors};

            # we pick the first one
            my $THE_error = $iii_errors[0]->[0];
            $errors =
                  $THE_error->{reason} . q{: }
                . join( ' | ', map { $_->{messages} } @{ $THE_error->{errors} } ) . " "
                . p(@itemInfo);
        } else {
            foreach my $item (@items) {
                $self->mark_item_as_contributed( { item_id => $item->id } );
            }
        }
    }

    return $errors;
}

=head3 contribute_all_bib_items_in_batch

    my $res = $contribution->contribute_all_bib_items_in_batch( { biblio => $biblio } );

Sends item information from all (contributable) items on a bib to the central server(s).
The I<biblio> param is mandatory.

    POST /innreach/v2/contribution/items/<bibId>

=cut

sub contribute_all_bib_items_in_batch {
    my ( $self, $args ) = @_;

    my $biblio = $args->{biblio};

    INNReach::Ill::MissingParameter->throw( param => "biblio" )
        unless $biblio and ref($biblio) eq 'Koha::Biblio';

    return $self->contribute_batch_items(
        {
            biblio_id => $biblio->id,
            items     => $self->filter_items_by_contributable( { items => $biblio->items } ),
        }
    );
}

=head3 update_item_status

    my $res = $contribution->update_item_status( { item_id => $item->id } );

It sends updated item status to the Central Server. It performs a:

    POST /innreach/v2/contribution/bibstatus/<itemId>

=cut

sub update_item_status {
    my ( $self, $args ) = @_;

    INNReach::Ill::MissingParameter->throw( param => "item_id" )
        unless $args->{item_id};

    my $item_id = $args->{item_id};

    my $errors;

    try {
        my $item = Koha::Items->find($item_id);

        my $data = {
            itemCircStatus => $self->item_circ_status( { item => $item } ),
            holdCount      => 0,
            dueDateTime    => ( $item->onloan )
            ? dt_from_string( $item->onloan )->epoch
            : undef,
        };

        my $response = $self->{plugin}->get_ua( $self->{central_server} )->post_request(
            {
                endpoint    => '/innreach/v2/contribution/itemstatus/' . $item_id,
                centralCode => $self->{central_server},
                data        => $data
            }
        );

        if ( !$response->is_success ) {    # HTTP code is not 2xx
            $errors = $response->status_line;
        } else {                           # III encoding errors in the response body of a 2xx
            my $response_content = decode_json( $response->decoded_content );
            if ( $response_content->{status} eq 'failed' ) {
                my @iii_errors = $response_content->{errors};

                # we pick the first one
                my $THE_error = $iii_errors[0][0];
                $errors = $THE_error->{reason} . q{: } . join( q{ | }, @{ $THE_error->{messages} } );
            }
        }
    } catch {
        die "Problem updating requested item ($item_id)";
    };

    return $errors;
}

=head3 decontribute_bib

    my $res = $contribution->decontribute_bib( { biblio_id => $biblio->id } );

Makes an API request to the Central Server to decontribute the specified record.
It performs a:

    DELETE /innreach/v2/contribution/bib/<bibId>

=cut

sub decontribute_bib {
    my ( $self, $args ) = @_;

    INNReach::Ill::MissingParameter->throw( param => "biblio_id" )
        unless $args->{biblio_id};

    my $biblio_id = $args->{biblio_id};

    my $errors;

    my $response = $self->{plugin}->get_ua( $self->{central_server} )->delete_request(
        {
            endpoint    => '/innreach/v2/contribution/bib/' . $biblio_id,
            centralCode => $self->{central_server}
        }
    );

    if ( !$response->is_success ) {    # HTTP code is not 2xx
        $errors = $response->status_line;
    } else {                           # III encoding errors in the response body of a 2xx
        my $response_content = decode_json( $response->decoded_content );
        if ( $response_content->{status} eq 'failed' ) {
            my @iii_errors = $response_content->{errors};

            # we pick the first one
            my $THE_error = $iii_errors[0][0];
            $errors = $THE_error->{reason} . q{: } . join( q{ | }, @{ $THE_error->{messages} } );
            if ( any { $_ =~ m/No bib record found with specified recid/ } @{ $THE_error->{messages} } ) {
                warn "Record $biblio_id not contributed but decontribution requested (leak)";
                $self->unmark_biblio_as_contributed( { biblio_id => $biblio_id } );
            }
        } else {
            $self->unmark_biblio_as_contributed( { biblio_id => $biblio_id } );
        }
    }

    return $errors;
}

=head3 decontribute_item

    my $res = $contribution->decontribute_item( { item_id => $item->id } );

Makes an API request to decontribute the specified item.

It performs a:

    DELETE /innreach/v2/contribution/item/<itemId>

=cut

sub decontribute_item {
    my ( $self, $args ) = @_;

    INNReach::Ill::MissingParameter->throw( param => "item_id" )
        unless $args->{item_id};

    my $item_id = $args->{item_id};

    my $errors;

    my $response = $self->{plugin}->get_ua( $self->{central_server} )->delete_request(
        {
            endpoint    => '/innreach/v2/contribution/item/' . $item_id,
            centralCode => $self->{central_server}
        }
    );

    if ( !$response->is_success ) {    # HTTP code is not 2xx
        $errors = $response->status_line;
    } else {                           # III encoding errors in the response body of a 2xx
        my $response_content = decode_json( $response->decoded_content );
        if ( $response_content->{status} eq 'failed' ) {
            my @iii_errors = $response_content->{errors};

            # we pick the first one
            my $THE_error = $iii_errors[0][0];
            $errors = $THE_error->{reason} . q{: } . join( q{ | }, @{ $THE_error->{messages} } );
            if ( any { $_ =~ m/No item record found with specified recid/ } @{ $THE_error->{messages} } ) {
                $self->unmark_item_as_contributed( { item_id => $item_id } );
            }
        } else {
            $self->unmark_item_as_contributed( { item_id => $item_id } );
        }
    }

    return $errors;
}

=head3 update_bib_status

    my $res = $contribution->update_bib_status( { biblio_id => $biblio_id } );

It sends updated bib status to the central server. It performs a:

    POST /innreach/v2/contribution/bibstatus/<bibId>

=cut

sub update_bib_status {
    my ( $self, $args ) = @_;

    INNReach::Ill::MissingParameter->throw( param => "biblio_id" )
        unless $args->{biblio_id};

    my $biblio_id      = $args->{biblio_id};
    my $central_server = $self->{central_server};

    my ( $biblio, $metadata, $record );

    my $errors;

    try {
        $biblio = Koha::Biblios->find($biblio_id);
        my $data = {
            titleHoldCount => $biblio->holds->count,
            itemCount      => $biblio->items->count,
        };

        my $response = $self->{plugin}->get_ua($central_server)->post_request(
            {
                endpoint    => '/innreach/v2/contribution/bibstatus/' . $biblio_id,
                centralCode => $central_server,
                data        => $data
            }
        );

        if ( !$response->is_success ) {    # HTTP code is not 2xx
            $errors = $response->status_line;
        } else {                           # III encoding errors in the response body of a 2xx
            my $response_content = decode_json( $response->decoded_content );
            if ( $response_content->{status} eq 'failed' ) {
                my @iii_errors = $response_content->{errors};

                # we pick the first one
                my $THE_error = $iii_errors[0][0];
                $errors = $THE_error->{reason} . q{: } . join( q{ | }, @{ $THE_error->{messages} } );
            }
        }
    } catch {
        die "Problem updating requested biblio ($biblio_id)";
    };

    return $errors;
}

=head3 upload_locations_list

    my $res = $contribution->upload_locations_list({ [ centralServer => $central_server ] });

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
        } else {
            @central_servers = @{ $self->{central_servers} };
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

            my $response = $self->{plugin}->get_ua($central_server)->post_request(
                {
                    endpoint    => '/innreach/v2/contribution/locations',
                    centralCode => $central_server,
                    data        => { locationList => \@locationList }
                }
            );
            warn p($response)
                if $response->is_error or $ENV{DEBUG};
        }
    } catch {
        die "Problem uploading locations list";
    };

    return $self;
}

=head3 upload_single_location

    my $res = $contribution->upload_single_location(
        { library_id => $library_id,
          [ centralServer => $central_server ]
        }
    );

Sends a single library/branch to the central server(s).

POST /innreach/v2/contribution/locations/<locationKey>

=cut

sub upload_single_location {
    my ( $self, $args ) = @_;

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
        } else {
            @central_servers = @{ $self->{central_servers} };
        }

        for my $central_server (@central_servers) {

            if ( exists $self->{config}->{$central_server}->{library_to_location}->{$library_id} ) {

                my $locationKey = $self->{config}->{$central_server}->{library_to_location}->{$library_id}->{location};
                my $description =
                    $self->{config}->{$central_server}->{library_to_location}->{$library_id}->{description};

                unless ($description) {
                    $description = $library->branchname;
                    warn "Mapped library lacks description ($library_id).";
                }

                my $response = $self->{plugin}->get_ua($central_server)->post_request(
                    {
                        endpoint    => '/innreach/v2/location/' . $locationKey,
                        centralCode => $central_server,
                        data        => { description => $description }
                    }
                );
                warn p($response)
                    if $response->is_error or $ENV{DEBUG};
            }
        }
    } catch {
        die "Problem uploading the required location";
    };

    return;
}

=head3 update_single_location

    my $res = $contribution->update_single_location(
        { library_id => $library_id,
          [ centralServer => $central_server ]
        }
    );

Sends a single library/branch to the central server(s).

PUT /innreach/v2/contribution/locations/<locationKey>

=cut

sub update_single_location {
    my ( $self, $args ) = @_;

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
        } else {
            @central_servers = @{ $self->{central_servers} };
        }

        for my $central_server (@central_servers) {

            if ( exists $self->{config}->{$central_server}->{library_to_location}->{$library_id} ) {

                my $locationKey = $self->{config}->{$central_server}->{library_to_location}->{$library_id}->{location};
                my $description =
                    $self->{config}->{$central_server}->{library_to_location}->{$library_id}->{description};

                unless ($description) {
                    $description = $library->branchname;
                    warn "Mapped library lacks description ($library_id).";
                }

                my $response = $self->{plugin}->get_ua($central_server)->put_request(
                    {
                        endpoint    => '/innreach/v2/location/' . $locationKey,
                        centralCode => $central_server,
                        data        => { description => $description }
                    }
                );
                warn p($response)
                    if $response->is_error or $ENV{DEBUG};
            }
        }
    } catch {
        die "Problem updating the required location";
    };

    return;
}

=head3 delete_single_location

    my $res = $contribution->delete_single_location(
        { library_id => $library_id,
          [ centralServer => $central_server ]
        }
    );

Sends a single library/branch to the central server(s).

DELETE /innreach/v2/location/<locationKey>

=cut

sub delete_single_location {
    my ( $self, $args ) = @_;

    my $library_id = $args->{library_id};
    die 'Mandatory parameter is missing: library_id'
        unless $library_id;

    try {

        my @central_servers;
        if ( $args->{centralServer} ) {
            push @central_servers, $args->{centralServer};
        } else {
            @central_servers = @{ $self->{central_servers} };
        }

        for my $central_server (@central_servers) {

            if ( exists $self->{config}->{$central_server}->{library_to_location}->{$library_id} ) {
                my $locationKey = $self->{config}->{$central_server}->{library_to_location}->{$library_id}->{location};

                my $response = $self->{plugin}->get_ua($central_server)->delete_request(
                    {
                        endpoint    => '/innreach/v2/location/' . $locationKey,
                        centralCode => $central_server
                    }
                );
                warn p($response)
                    if $response->is_error or $ENV{DEBUG};
            }
        }
    } catch {
        die "Problem deleting the required location";
    };

    return;
}

=head3 get_central_item_types

    my $res = $contribution->get_central_item_types();

Sends a a request for defined item types to a central server. It performs a:

    GET /innreach/v2/contribution/itemtypes

=cut

sub get_central_item_types {
    my ($self) = @_;

    my $response;

    try {
        $response = $self->{plugin}->get_ua( $self->{central_server} )->get_request(
            {
                endpoint    => '/innreach/v2/contribution/itemtypes',
                centralCode => $self->{central_server}
            }
        );
        warn p($response)
            if $response->is_error or $ENV{DEBUG};
    } catch {
        die "Problem fetching the item types list";
    };

    return decode_json( $response->decoded_content )->{itemTypeList};
}

=head3 get_locations_list

    my $res = $contribution->get_locations_list();

Sends a a request for defined locations to a central server. It performs a:

    GET /innreach/v2/contribution/locations

=cut

sub get_locations_list {
    my ($self) = @_;

    my $response;

    try {
        $response = $self->{plugin}->get_ua( $self->{central_server} )->get_request(
            {
                endpoint    => '/innreach/v2/contribution/locations',
                centralCode => $self->{central_server}
            }
        );
        warn p($response)
            if $response->is_error or $ENV{DEBUG};
    } catch {
        die "Problem fetching the locations list";
    };

    return decode_json( encode( 'UTF-8', $response->content ) )->{locationList};
}

=head3 get_agencies_list

    my $res = $contribution->get_agencies_list();

Sends a a request for defined agencies to a central server. It performs a:

    GET /innreach/v2/contribution/agencies

=cut

sub get_agencies_list {
    my ($self) = @_;

    my $response;

    try {
        $response = $self->{plugin}->get_ua( $self->{central_server} )->get_request(
            {
                endpoint    => '/innreach/v2/contribution/localservers',
                centralCode => $self->{central_server}
            }
        );
        warn p($response)
            if $response->is_error or $ENV{DEBUG};
    } catch {
        die "Problem fetching the agencies list";
    };

    return decode_json( encode( 'UTF-8', $response->content ) )->{localServerList};
}

=head3 get_central_patron_types_list

    my $res = $contribution->get_central_patron_types_list();

Sends a a request for defined locations to a central server. It performs a:

    GET /innreach/v2/circ/patrontypes

=cut

sub get_central_patron_types_list {
    my ($self) = @_;

    my $response;

    try {
        $response = $self->{plugin}->get_ua( $self->{central_server} )->get_request(
            {
                endpoint    => '/innreach/v2/circ/patrontypes',
                centralCode => $self->{central_server}
            }
        );
        warn p($response)
            if $response->is_error or $ENV{DEBUG};
    } catch {
        die "Problem fetching the central patron types list";
    };

    return decode_json( encode( 'UTF-8', $response->content ) )->{patronTypeList};
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
    my ( $self, $args ) = @_;

    my $item_id  = $args->{item_id};
    my $date_due = $args->{date_due};

    my $req = $self->get_ill_request_from_item_id(
        {
            item_id => $item_id,
            status  => 'B_ITEM_RECEIVED',
        }
    );

    INNReach::Ill::InconsistentStatus->throw( expected_status => 'B_ITEM_RECEIVED' )
        unless $req;

    my $response;

    return try {

        my $trackingId  = $req->extended_attributes->search( { type => 'trackingId' } )->next->value;
        my $centralCode = $req->extended_attributes->search( { type => 'centralCode' } )->next->value;

        $response = $self->{plugin}->get_ua($centralCode)->post_request(
            {
                endpoint    => "/innreach/v2/circ/borrowerrenew/$trackingId/$centralCode",
                centralCode => $centralCode,
                data        => { dueDateTime => dt_from_string($date_due)->epoch }
            }
        );

        if ( $response->is_error ) {

            warn p($response)
                if $ENV{DEBUG};

            return ($response);
        }

        return;
    } catch {
        INNReach::Ill->throw("Unhandled exception: $_");
    };
}

=head2 Internal methods

=head3 item_circ_status

Calculates the value for itemCircStatus

=cut

sub item_circ_status {
    my ( $self, $args ) = @_;

    die "Mandatory parameter missing: item"
        unless exists $args->{item};

    my $item = $args->{item};
    die "Parameter type incorrect for item"
        unless ref($item) eq 'Koha::Item';

    my $status = 'Available';
    if ( $item->onloan ) {
        $status = 'On Loan';
    } elsif ( $item->withdrawn && $item->withdrawn > 0 ) {
        $status = 'Not Available';
    } elsif ( $item->notforloan ) {
        $status = 'Non-Lendable';
    } elsif ( !C4::Context->preference('AllowHoldsOnDamagedItems')
        && $item->damaged )
    {
        $status = 'Non-Lendable';
    } elsif ( $item->itemlost ) {
        $status = 'Not Available';
    } elsif ( $item->holds->filter_by_found->count > 0 ) {
        $status = 'Not Available';
    }

    return $status;
}

=head3 get_ill_request_from_item_id

This method retrieves the Koha::ILLRequest using a item_id.

=cut

sub get_ill_request_from_item_id {
    my ( $self, $args ) = @_;

    my $item_id = $args->{item_id};
    my $status  = $args->{status} // 'B_ITEM_SHIPPED';    # borrowing site, item shipped, receiving

    my $item = Koha::Items->find($item_id);

    unless ($item) {
        INNReach::Ill::UnknownItemId->throw( item_id => $item_id );
    }

    my $biblio_id = $item->biblionumber;

    my $reqs = $self->{plugin}->get_ill_rs->search(
        {
            biblio_id => $biblio_id,
            status    => [$status]
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

    if ( $contribution->should_item_be_contributed( { item => $item } ) )
       { ... }

Returns a I<boolean> telling if the B<$item> should be contributed to the specified
B<$central_server>

=cut

sub should_item_be_contributed {
    my ( $self, $params ) = @_;

    my $item = $params->{item};

    INNReach::Ill::MissingParameter->throw( param => 'item' )
        unless $item;

    my $items_rs = Koha::Items->search( { itemnumber => $item->itemnumber } );

    return $self->filter_items_by_contributable( { items => $items_rs } )->count > 0;
}

=head3 should_biblio_be_contributed

    if ( $contribution->should_biblio_be_contributed( { biblio => $biblio } ) )
       { ... }

Returns a I<boolean> telling if the B<$biblio> should be contributed to the specified
B<$central_server>.

=cut

sub should_biblio_be_contributed {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(biblio);
    foreach my $param (@mandatory_params) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    my $biblio         = $params->{biblio};
    my $central_server = $self->{central_server};

    my $configuration = $self->{config}->{$central_server};

    # FIXME: Should there be rules on biblio records?
    return ( $configuration->{contribution}->{exclude_empty_biblios} // 1 )
        ? $self->filter_items_by_contributable( { items => $biblio->items } )->count > 0
        : 1;
}

=head3 filter_items_by_contributable

    my $items = $contribution->filter_items_by_contributable(
        {
            items         => $biblio->items,
          [ force_enabled => 1, ]
        }
    );

Given a I<Koha::Items> iterator, it returns a new resultset, filtered by the configured
rules for the central server.

The optional parameter I<force_enabled> can be used to override the check on the
I<contribution: enabled> flag in the configuration.

=cut

sub filter_items_by_contributable {
    my ( $self, $params ) = @_;

    my $items = $params->{items};

    INNReach::Ill::MissingParameter->throw( param => 'items' )
        unless $items;

    my $force_enabled = $params->{force_enabled};

    my $central_server = $self->{central_server};
    my $configuration  = $self->{config}->{$central_server};

    return $items->empty
        unless $configuration->{contribution}->{enabled}
        || $force_enabled;

    if ( exists $configuration->{contribution}->{included_items}
        && $configuration->{contribution}->{included_items} )
    {
        # there are rules!
        $items =
            $items->search( $configuration->{contribution}->{included_items} );
    }

    if ( exists $configuration->{contribution}->{excluded_items}
        && $configuration->{contribution}->{excluded_items} )
    {
        # there are rules!
        $items = $items->search( { '-not' => $configuration->{contribution}->{excluded_items} } );
    }

    return $items;
}

=head3 filter_items_by_contributed

    my $items = $contribution->filter_items_by_contributed(
        {
            items => $biblio->items,
            central_server => $central_server
        }
    );

Given a I<Koha::Items> iterator and a I<central server code>, it returns a new resultset,
filtered by items that have been contributed to the specified central server.

=cut

sub filter_items_by_contributed {
    my ( $self, $params ) = @_;

    my $items = $params->{items};

    INNReach::Ill::MissingParameter->throw( param => 'items' )
        unless $items;

    my $central_server = $self->{central_server};

    my $dbh               = C4::Context->dbh;
    my $contributed_items = $self->{plugin}->get_qualified_table_name('contributed_items');

    my @item_ids = map { $_->[0] } $dbh->selectall_array(
        qq{
        SELECT item_id FROM $contributed_items
        WHERE central_server = ?;
    }, undef, $central_server
    );

    return $items->search( { itemnumber => \@item_ids } );
}

=head3 filter_items_by_to_be_decontributed

    my $items = $contribution->filter_items_by_to_be_decontributed(
        {
            items => $biblio->items,
        }
    );

Given a I<Koha::Items> iterator, it returns a new resultset,
filtered by items that have been contributed and should be decontributed from the
central server.

=cut

sub filter_items_by_to_be_decontributed {
    my ( $self, $params ) = @_;

    my $items = $params->{items};

    INNReach::Ill::MissingParameter->throw( param => 'items' )
        unless $items;

    $items = $self->filter_items_by_contributed( { items => $items } );

    my $configuration = $self->{config}->{ $self->{central_server} };

    if ( exists $configuration->{contribution}->{included_items}
        && $configuration->{contribution}->{included_items} )
    {
        # there are rules!
        $items = $items->search( { '-not' => $configuration->{contribution}->{included_items} } );
    }

    if ( exists $configuration->{contribution}->{excluded_items}
        && $configuration->{contribution}->{excluded_items} )
    {
        # there are rules!
        $items =
            $items->search( $configuration->{contribution}->{excluded_items} );
    }

    return $items->search;
}

=head3 get_deleted_contributed_items

    my $item_ids = $contribution->get_deleted_contributed_items(
        {
            central_server => $central_server,
        }
    );

Given a I<central server code>, it returns a list of item ids,
filtered by items that have been contributed to the specified central server
and are no longer present on the database.

=cut

sub get_deleted_contributed_items {
    my ( $self, $params ) = @_;

    my $central_server = $params->{central_server};

    INNReach::Ill::MissingParameter->throw( param => 'central_server' )
        unless $central_server;

    INNReach::Ill::InvalidCentralserver->throw( central_server => $central_server )
        unless any { $_ eq $central_server } @{ $self->{central_servers} };

    my $dbh               = C4::Context->dbh;
    my $contributed_items = $self->{plugin}->get_qualified_table_name('contributed_items');

    my @item_ids = map { $_->[0] } $dbh->selectall_array(
        qq{
        SELECT item_id FROM
        (
          (SELECT item_id
           FROM $contributed_items
           WHERE central_server=?) b
          LEFT JOIN items
          ON (items.itemnumber=b.item_id)
        ) WHERE items.itemnumber IS NULL;
    }, undef, $central_server
    );

    return \@item_ids;
}

=head3 mark_biblio_as_contributed

    $contribution->mark_biblio_as_contributed( { biblio_id => $biblio_id } );

Method for marking an biblio as contributed.

=cut

sub mark_biblio_as_contributed {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(biblio_id);
    foreach my $param (@mandatory_params) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    my $central_server = $self->{central_server};
    my $biblio_id      = $params->{biblio_id};

    my $dbh = C4::Context->dbh;

    my $contributed_biblios = $self->{plugin}->get_qualified_table_name('contributed_biblios');

    my $sth = $dbh->prepare(
        qq{
        SELECT COUNT(*) FROM $contributed_biblios
        WHERE central_server = ?
          AND biblio_id = ?;
    }
    );

    $sth->execute( $central_server, $biblio_id );
    my ($count) = $sth->fetchrow_array;

    if ($count) {    # update
        $dbh->do(
            qq{
            UPDATE $contributed_biblios
            SET timestamp=NOW()
            WHERE central_server='$central_server'
              AND biblio_id='$biblio_id';
        }
        );
    } else {         # insert
        $dbh->do(
            qq{
            INSERT INTO $contributed_biblios
                (  central_server,     biblio_id )
            VALUES
                ( '$central_server', '$biblio_id' );
        }
        );
    }

    return $self;
}

=head3 mark_item_as_contributed

    $contribution->mark_item_as_contributed( { item_id => $item_id } );

Method for marking an item as contributed.

=cut

sub mark_item_as_contributed {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(item_id);
    foreach my $param (@mandatory_params) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    my $central_server = $self->{central_server};
    my $item_id        = $params->{item_id};

    my $dbh = C4::Context->dbh;

    my $contributed_items = $self->{plugin}->get_qualified_table_name('contributed_items');

    my $sth = $dbh->prepare(
        qq{
        SELECT COUNT(*) FROM $contributed_items
        WHERE central_server = ?
          AND item_id = ?;
    }
    );

    $sth->execute( $central_server, $item_id );
    my ($count) = $sth->fetchrow_array;

    if ($count) {    # update
        $dbh->do(
            qq{
            UPDATE $contributed_items
            SET timestamp=NOW()
            WHERE central_server='$central_server'
              AND item_id='$item_id';
        }
        );
    } else {         # insert
        $dbh->do(
            qq{
            INSERT INTO $contributed_items
                (  central_server,     item_id )
            VALUES
                ( '$central_server', '$item_id' );
        }
        );
    }

    return $self;
}

=head3 unmark_biblio_as_contributed

    $contribution->unmark_biblio_as_contributed(
        {
            biblio_id      => $biblio_id,
          [ skip_items     => 1/0,             ]
        }
    );

Method for marking a biblio as contributed.

=cut

sub unmark_biblio_as_contributed {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(biblio_id);
    foreach my $param (@mandatory_params) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    my $central_server = $self->{central_server};
    my $biblio_id      = $params->{biblio_id};

    my $dbh = C4::Context->dbh;

    my $contributed_biblios = $self->{plugin}->get_qualified_table_name('contributed_biblios');

    $dbh->do(
        qq{
        DELETE FROM $contributed_biblios
        WHERE central_server='$central_server'
          AND      biblio_id='$biblio_id';
    }
    );

    unless ( $params->{skip_items} ) {
        my $biblio = Koha::Biblios->find($biblio_id);
        if ($biblio) {
            my $items = $biblio->items;
            while ( my $item = $items->next ) {
                $self->unmark_item_as_contributed( { item_id => $item->id } );
            }
        }
    }

    return $self;
}

=head3 unmark_item_as_contributed

    $contribution->unmark_item_as_contributed( { item_id => $item_id } );

Method for marking an item as contributed.

=cut

sub unmark_item_as_contributed {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(item_id);
    foreach my $param (@mandatory_params) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    my $central_server = $self->{central_server};
    my $item_id        = $params->{item_id};

    my $dbh = C4::Context->dbh;

    my $contributed_items = $self->{plugin}->get_qualified_table_name('contributed_items');

    $dbh->do(
        qq{
        DELETE FROM $contributed_items
        WHERE central_server='$central_server'
          AND        item_id='$item_id';
    }
    );

    return $self;
}

=head3 is_bib_contributed

    if ( $self->is_bib_contributed( { biblio_id => $biblio_id } ) )
    { ... }

=cut

sub is_bib_contributed {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(biblio_id);
    foreach my $param (@mandatory_params) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    my $biblio_id = $params->{biblio_id};
    my $dbh       = C4::Context->dbh;

    my $contributed_biblios = $self->{plugin}->get_qualified_table_name('contributed_biblios');

    my $sth = $dbh->prepare(
        qq{
        SELECT COUNT(*) FROM $contributed_biblios
        WHERE central_server = ?
          AND biblio_id = ?;
    }
    );

    $sth->execute( $self->{central_server}, $biblio_id );
    my ($count) = $sth->fetchrow_array;

    return ($count) ? 1 : 0;
}

=head3 is_item_contributed

    if ( $self->is_item_contributed( { item_id => $item_id } ) )
    { ... }

=cut

sub is_item_contributed {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(item_id);
    foreach my $param (@mandatory_params) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    my $item_id = $params->{item_id};
    my $dbh     = C4::Context->dbh;

    my $contributed_items = $self->{plugin}->get_qualified_table_name('contributed_items');

    my $sth = $dbh->prepare(
        qq{
        SELECT COUNT(*) FROM $contributed_items
        WHERE central_server = ?
          AND item_id = ?;
    }
    );

    $sth->execute( $self->{central_server}, $item_id );
    my ($count) = $sth->fetchrow_array;

    return ($count) ? 1 : 0;
}

=head3 item_to_iteminfo

    my $iteminfo = $contribution->item_to_iteminfo( { item => $item, use_holding_library => 0 / 1 } );

Takes a I<Koha::Item> object, and returns a suitable data structure for the
central server.

=cut

sub item_to_iteminfo {
    my ( $self, $params ) = @_;

    INNReach::Ill::MissingParameter->throw( param => 'item' )
        unless $params->{item} && ref( $params->{item} ) eq 'Koha::Item';

    my $item                = $params->{item};
    my $use_holding_library = $params->{use_holding_library} ? 1 : 0;

    my $central_server = $self->{central_server};
    my $configuration  = $self->{config}->{$central_server};

    my $branch_to_use = $use_holding_library ? $item->holdingbranch : $item->homebranch;

    my $centralItemType = $configuration->{local_to_central_itype}->{ $item->effective_itemtype };
    my $locationKey =
        $configuration->{library_to_location}->{$branch_to_use}->{location};

    # Skip the item if has unmapped values (that are relevant)
    unless ( $centralItemType && $locationKey ) {
        unless ($centralItemType) {
            INNReach::Ill::MissingMapping->throw(
                $self->{central_server} . ": missing mapping for item type (" . $item->effective_itemtype
                    // 'null' . ")" );
        }
        unless ($locationKey) {
            INNReach::Ill::MissingMapping->throw(
                $self->{central_server}
                    . ": missing mapping for branch ("
                    . $branch_to_use . "). "
                    . ($use_holding_library)
                ? 'NOTE: using holding library'
                : 'NOTE: using home library'
            );
        }
    }

    return {
        itemId          => $item->itemnumber,
        agencyCode      => $configuration->{mainAgency},
        centralItemType => $centralItemType,
        locationKey     => $locationKey,
        itemCircStatus  => $self->item_circ_status( { item => $item } ),
        holdCount       => 0,
        dueDateTime     => ( $item->onloan )
        ? dt_from_string( $item->onloan )->epoch
        : undef,
        callNumber        => $item->itemcallnumber,
        volumeDesignation => $item->enumchron,
        copyNumber        => $item->copynumber,
        itemNote          => substr( $item->itemnotes // '', 0, 256 ),
        suppress          => 'n',                                        # TODO: revisit
    };
}

1;
