package INNReach::Commands::Base;

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

use Try::Tiny;

use Koha::Plugin::Com::Theke::INNReach::Exceptions;

=head1 INNReach::Commands::Base

A base class implementing classes of methods for sending messages to INN-Reach central servers

=head1 Class methods

=head2 General methods

=head3 new

Class constructor

=cut

sub new {
    my ( $class, $params ) = @_;

    my $plugin = $params->{plugin};

    INNReach::Ill::MissingParameter->throw( param => 'plugin' )
        unless $plugin and ref($plugin) eq 'Koha::Plugin::Com::Theke::INNReach';

    my $self = {
        configuration => $plugin->configuration, # calculated hash, put here to reuse
        plugin        => $plugin,
    };

    bless $self, $class;
    return $self;
}

1;
