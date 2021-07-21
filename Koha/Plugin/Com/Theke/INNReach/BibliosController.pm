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

use Encode qw{ encode decode };
use List::MoreUtils qw(any);
use MARC::Record;
use MARC::File::XML;
use MIME::Base64 qw{ encode_base64 };
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

    return try {

        my $biblio   = Koha::Biblios->find( $bibId );

        unless ( $biblio ) {
            my $reason = ( $biblio ) ? 'Problem retrieving object' : 'Object not found';
            return $c->render(
                status  => 404,
                openapi => {
                    status => 'error',
                    reason => $reason,
                    errors => []
                }
            );
        }

        my $record = $biblio->metadata->record;

        unless ( $record ) {
            my $reason = ( $record ) ? 'Problem retrieving object' : 'Object not found';
            return $c->render(
                status  => 404,
                openapi => {
                    status => 'error',
                    reason => $reason,
                    errors => []
                }
            );
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

        return $c->render(
            status  => 200,
            openapi => {
                status => 'ok',
                reason => '',
                errors => [],
                bibInfo => {
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
            status => 500,
            openapi => {
                status => 'error',
                reason => "Internal unhandled error: $_",
                errors => []
            }
        );
    };
}

1;
