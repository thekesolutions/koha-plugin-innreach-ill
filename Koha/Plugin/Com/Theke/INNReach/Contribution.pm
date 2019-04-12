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

use HTTP::Request::Common qw{ POST DELETE };
use MARC::Record;
use MARC::File::XML;
use MIME::Base64 qw{ encode_base64url };
use Try::Tiny;

use Koha::Biblios;
use Koha::Biblio::Metadatas;

use Koha::Plugin::Com::Theke::INNReach;
use Koha::Plugin::Com::Theke::INNReach::OAuth2;

use Data::Printer colored => 1;

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

    $args->{config} = Koha::Plugin::Com::Theke::INNReach->new()->configuration;
    $args->{oauth}  = Koha::Plugin::Com::Theke::INNReach::OAuth2->new(
        {   client_id     => $args->{config}->{client_id},
            client_secret => $args->{config}->{client_secret}
        }
    );

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

    # delete all local fields ("Omit 9XX fields" rule)
    my @local = $record->field('9..');
    $record->delete_fields(@local);
    # Encode ISO2709 record
    my $encoded_record = encode_base64url( $record->as_usmarc );

    my $data = {
        marc21BibFormat => 'ISO2709', # Only supported value
        marc21BibData   => $encoded_record,
        titleHoldCount  => $biblio->holds->count,
        itemCount       => $biblio->items->count,
        suppress        => $suppress
    };

    my @central_servers;
    if ( $args->{centralServer} ) {
        push @central_servers, $args->{centralServer};
    }
    else {
        @central_servers = @{ $self->config->{centralServers} };
    }

    for my $central_server (@central_servers) {
        my $request = $self->post_request(
            {   endpoint    => '/innreach/v2/contribution/bib/' . $bibId,
                centralCode => $central_server,
                data        => $data
            }
        );
    }
}

=head2 Internal methods

=head3 token

Method for retrieving a valid access token

=cut

sub token {
    my ($self) = @_;

    return $self->oauth2->get_token;
}

=head3 post_request

Generic request for POST

=cut

sub post_request {
    my ($self, $args) = @_;

    return POST(
        $self->config->{api_base_url} . '/' . $args->{endpoint},
        Authorization => "Bearer " . $self->token,
        'X-From-Code' => $self->config->{localServerCode},
        'X-To-Code'   => $args->{centralCode},
        Accept        => "application/json",,
        ContentType   => "application/x-www-form-urlencoded",
        Content       => $args->{data}
    );
}

1;
