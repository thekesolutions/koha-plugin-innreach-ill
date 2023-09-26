package Koha::Plugin::Com::Theke::INNReach::Exceptions;

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

use Exception::Class (
    'INNReach::Ill',
    'INNReach::Ill::BadPickupLocation' => {
        isa         => 'INNReach::Ill',
        description => 'The passed pickupLocation attribute does not contain a valid structure',
        fields      => ['value']
    },
    'INNReach::Ill::InconsistentStatus' => {
        isa         => 'INNReach::Ill',
        description => 'Request status inconsistent with the requested action',
        fields      => ['expected_status']
    },
    'INNReach::Ill::InvalidCentralserver' => {
        isa         => 'INNReach::Ill',
        description => 'Passed central server is invalid',
        fields      => ['central_server']
    },
    'INNReach::Ill::MissingMapping' => {
        isa         => 'INNReach::Ill',
        description => 'Mapping returns undef',
        fields      => ['section', 'key']
    },
    'INNReach::Ill::MissingParameter' => {
        isa         => 'INNReach::Ill',
        description => 'Required parameter is invalid',
        fields      => ['param']
    },
    'INNReach::Ill::UnknownItemId' => {
        isa         => 'INNReach::Ill',
        description => 'Passed item_id is invalid',
        fields      => ['item_id']
    },
    'INNReach::Ill::UnknownBiblioId' => {
        isa         => 'INNReach::Ill',
        description => 'Passed biblio_id is invalid',
        fields      => ['biblio_id']
    },
    'INNReach::Ill::RequestFailed' => {
        isa         => 'INNReach::Ill',
        description => 'HTTP request error response',
        fields      => [ 'method', 'response' ]
    },
);

sub full_message {
    my $self = shift;

    # If a message was passed manually, use it
    return sprintf "Exception '%s' thrown '%s'\n", ref($self), $self->message
      if $self->message;

    my $field_hash = $self->field_hash;

    my $description = $self->description;
    my @fields;

    foreach my $key ( sort keys %$field_hash ) {
        push @fields, $key . " => " . $field_hash->{$key}
          if defined $field_hash->{$key};
    }

    return
      sprintf "Exception '%s' thrown '%s'" . ( @fields ? " with %s" : "" ) . "\n",
      ref($self), $description, ( @fields ? join ', ', @fields : () );
}

1;
