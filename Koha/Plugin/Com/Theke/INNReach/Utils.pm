package Koha::Plugin::Com::Theke::INNReach::Utils;

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

use vars qw(@ISA @EXPORT_OK);

BEGIN {
    require Exporter;
    @ISA = qw(Exporter);

    @EXPORT_OK = qw(
        add_or_update_attributes
        add_virtual_record_and_item
        get_ill_request_from_attribute
        innreach_warn
    );
}

use List::MoreUtils qw(any);
use MARC::Field;
use MARC::Record;

use C4::Context;
use C4::Biblio qw(AddBiblio);

use Koha::Database;
use Koha::Illrequests;
use Koha::Illrequestattributes;
use Koha::Items;

use Koha::Plugin::Com::Theke::INNReach::Exceptions;
use Koha::Plugin::Com::Theke::INNReach::Normalizer;

=head1 Koha::Plugin::Com::Theke::INNReach::Utils

A class implementing the controller methods for the circulation-related endpoints

=head1 API

=head2 Class methods

=head3 get_ill_request_from_attribute

    my $req = get_ill_request_from_attribute(
        {
            type  => $type,
            value => $value
        }
    );

Retrieve an ILL request using some attribute.

=cut

sub get_ill_request_from_attribute {
    my ($args) = @_;

    my @mandatory_params = qw(type value);
    foreach my $param (@mandatory_params) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $args->{$param};
    }

    my $type  = $args->{type};
    my $value = $args->{value};

    my $requests_rs = Koha::Illrequests->search(
        {
            'illrequestattributes.type'  => $type,
            'illrequestattributes.value' => $value
        },
        { join => ['illrequestattributes'] }
    );

    my $count = $requests_rs->count;

    innreach_warn("more than one result searching requests with type='$type' value='$value'")
        if $count > 1;

    return $requests_rs->next
        if $count > 0;
}

=head3 add_virtual_record_and_item

    my $item = add_virtual_record_and_item(
        {
            barcode      => $barcode,
            call_number  => $call_number,
            central_code => $central_code,
            req          => $req,
        }
    );

This method is used for adding a virtual (hidden for end-users) MARC record
with an item, so a hold is placed for it. It returns the generated I<Koha::Item> object.

=cut

sub add_virtual_record_and_item {
    my ($args) = @_;

    my $barcode     = $args->{barcode};
    my $call_number = $args->{call_number};
    my $config      = $args->{config};
    my $req         = $args->{req};

    # values from configuration
    my $marc_flavour              = C4::Context->preference('marcflavour');      # FIXME: do we need this?
    my $framework_code            = $config->{default_marc_framework} || 'FA';
    my $ccode                     = $config->{default_item_ccode};
    my $location                  = $config->{default_location};
    my $notforloan                = $config->{default_notforloan} // -1;
    my $checkin_note              = $config->{default_checkin_note}        || 'Additional processing required (ILL)';
    my $no_barcode_central_itypes = $config->{no_barcode_central_itypes} // [];

    my $materials;

    if ( $config->{materials_specified} ) {
        $materials =
            ( defined $config->{default_materials_specified} )
            ? $config->{default_materials_specified}
            : 'Additional processing required (ILL)';
    }

    my $attributes      = $req->extended_attributes;
    my $centralItemType = $attributes->search( { type => 'centralItemType' } )->next->value;

    if ( any { $centralItemType eq $_ } @{$no_barcode_central_itypes} ) {
        $barcode = undef;
    } else {
        my $default_normalizers = $config->{default_barcode_normalizers} // [];

        if ( scalar @{$default_normalizers} ) {
            my $normalizer = Koha::Plugin::Com::Theke::INNReach::Normalizer->new( { string => $barcode } );

            foreach my $method ( @{$default_normalizers} ) {
                unless ( any { $_ eq $method } @{ $normalizer->available_normalizers } ) {

                    # not a valid normalizer
                    Koha::Plugin::Com::Theke::INNReach::Utils::innreach_warn(
                        "Invalid barcode normalizer configured: $method");
                } else {
                    $normalizer->$method;
                }
            }

            $barcode = $normalizer->get_string;
        }
    }

    # determine the right item types
    my $item_type;
    if ( exists $config->{central_to_local_itype} ) {
        $item_type =
            ( exists $config->{central_to_local_itype}->{$centralItemType}
                and $config->{central_to_local_itype}->{$centralItemType} )
            ? $config->{central_to_local_itype}->{$centralItemType}
            : $config->{default_item_type};
    } else {
        $item_type = $config->{default_item_type};
    }

    unless ($item_type) {
        INNReach::Ill->throw("'default_item_type' entry missing in configuration");
    }

    my $author_attr = $attributes->search( { type => 'author' } )->next;
    my $author      = ($author_attr) ? $author_attr->value : '';
    my $title_attr  = $attributes->search( { type => 'title' } )->next;
    my $title       = ($title_attr) ? $title_attr->value : '';

    INNReach::Ill->throw("$marc_flavour is not supported (yet)")
        unless $marc_flavour eq 'MARC21';

    my $record = MARC::Record->new();
    $record->leader('     nac a22     1u 4500');
    $record->insert_fields_ordered(
        MARC::Field->new( '100', '1', '0', 'a' => $author ),
        MARC::Field->new( '245', '1', '0', 'a' => $title ),
        MARC::Field->new(
            '942', '1', '0',
            'n' => 1,
            'c' => $item_type
        )
    );

    my $item;
    my $schema = Koha::Database->new->schema;
    $schema->txn_do(
        sub {
            my ( $biblio_id, $biblioitemnumber ) = AddBiblio( $record, $framework_code );

            my $item_data = {
                barcode             => $barcode,
                biblioitemnumber    => $biblioitemnumber,
                biblionumber        => $biblio_id,
                ccode               => $ccode,
                holdingbranch       => $req->branchcode,
                homebranch          => $req->branchcode,
                itemcallnumber      => $call_number,
                itemnotes_nonpublic => $checkin_note,
                itype               => $item_type,
                location            => $location,
                materials           => $materials,
                notforloan          => $notforloan,
            };

            $item = Koha::Item->new($item_data)->store;
        }
    );

    return $item;
}

=head3 add_or_update_attributes

    add_or_update_attributes(
        {
            request    => $request,
            attributes => {
                $type_1 => $value_1,
                $type_2 => $value_2,
                ...
            },
        }
    );

Takes care of updating or adding attributes if they don't already exist.

=cut

sub add_or_update_attributes {
    my ($params) = @_;

    my $request    = $params->{request};
    my $attributes = $params->{attributes};

    Koha::Database->new->schema->txn_do(
        sub {
            while ( my ( $type, $value ) = each %{$attributes} ) {

                my $attr = $request->extended_attributes->find( { type => $type } );

                if ($attr) {    # update
                    if ( $attr->value ne $value ) {
                        $attr->update( { value => $value, } );
                    }
                } else {        # new
                    $attr = Koha::Illrequestattribute->new(
                        {
                            illrequest_id => $request->id,
                            type          => $type,
                            value         => $value,
                        }
                    )->store;
                }
            }
        }
    );

    return;
}

=head3 innreach_warn

Helper method for logging warnings for the INN-Reach plugin homogeneously.

=cut

sub innreach_warn {
    my ($warning) = @_;

    warn "innreach_plugin_warn: $warning";
}

1;
