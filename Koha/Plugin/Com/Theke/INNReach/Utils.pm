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

use Koha::Illrequests;
use Koha::Illrequestattributes;

use Koha::Plugin::Com::Theke::INNReach::Exceptions;

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
    my ( $args ) = @_;

    my @mandatory_params = qw(type value);
    foreach my $param ( @mandatory_params ) {
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

=head3 innreach_warn

Helper method for logging warnings for the INN-Reach plugin homogeneously.

=cut

sub innreach_warn {
    my ( $warning ) = @_;

    warn "innreach_plugin_warn: $warning";
}

1;
