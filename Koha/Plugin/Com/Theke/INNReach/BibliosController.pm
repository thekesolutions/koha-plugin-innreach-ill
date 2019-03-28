package Koha::Plugin::Com::Theke::INNReach::BibliosController;

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

use MARC::Record;
use MARC::File::XML;
use MIME::Base64 qw{ encode_base64url };
use Try::Tiny;

use Koha::Biblios;
use Koha::Biblio::Metadatas;

use Koha::Plugin::Com::Theke::INNReach;

use Mojo::Base 'Mojolicious::Controller';

=head1 Koha::Plugin::Com::Theke::INNReach::BibliosController

A class implementing the controller methods for bibliographic records exchange

=head2 Class methods

=head3 getbibrecord

Return a bibliographic record by bibId (biblionumber)

=cut

sub getbibrecord {
    my $c = shift->openapi->valid_input or return;

    my $bibId       = $c->validation->param('bibId');
    my $centralCode = $c->validation->param('centralCode');

    my $biblio   = Koha::Biblios->find( $bibId );
    my $metadata = Koha::Biblio::Metadatas->find(
        { biblionumber => $bibId, format => 'marcxml', marcflavour => 'marc21' } );
    my $record = eval { MARC::Record::new_from_xml( $metadata->metadata, 'utf-8', $metadata->marcflavour ); };

    unless ( $biblio and $record ) {
        my $reason = ( $biblio ) ? 'Problem retrieving object' : 'Object not found';
        return $c->render(
            status  => 200,
            openapi => {
                status => 'error',
                reason => $reason,
                errors => []
            }
        );
    }

    my $configuration = Koha::Plugin::Com::Theke::INNReach->new()->configuration;
    my $library_to_agency = $configuration->{library_to_agency};

    return try {

        my $suppress = 'n'; # expected default
        # TODO: calculate $suppress => y, n, g
        my $encoded_record = encode_base64url( $record->as_usmarc );

        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => [],
                bibinfo => {
                    agencyCode      => $library_to_agency->{'MPL'}, # TODO: where do we get it?
                    marc21BibFormat => 'ISO2709', # Only supported value
                    marc21BibData   => $encoded_record,
                    titleHoldCount  => $biblio->holds->count,
                    itemCount       => $biblio->items->count,
                    suppress        => $suppress
                }
            }
        );
    }
    catch {
        return $c->render(
            status => 200,
            openapi => {
                status => 'error',
                reason => 'Internal unhandled error'
            }
        );
    };
}

1;
