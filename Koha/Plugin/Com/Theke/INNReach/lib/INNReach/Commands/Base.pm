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

use Koha::Plugin::Com::Theke::INNReach;
use Koha::Plugin::Com::Theke::INNReach::OAuth2;

=head1 INNReach::Commands::Base

A base class implementing classes of methods for sending messages to INN-Reach central servers

=head1 Class methods

=head2 General methods

=head3 new

Class constructor

=cut

sub new {
    my ($class) = @_;

    my $plugin          = Koha::Plugin::Com::Theke::INNReach->new;
    my $configuration   = $plugin->configuration;
    my @central_servers = $plugin->central_servers;

    my $oauth2;
    foreach my $centralServer (@central_servers) {
        $oauth2->{$centralServer} =
          Koha::Plugin::Com::Theke::INNReach::OAuth2->new(
            {
                client_id => $configuration->{$centralServer}->{client_id},
                client_secret =>
                  $configuration->{$centralServer}->{client_secret},
                api_base_url =>
                  $configuration->{$centralServer}->{api_base_url},
                api_token_base_url =>
                  $configuration->{$centralServer}->{api_token_base_url},
                local_server_code =>
                  $configuration->{$centralServer}->{localServerCode}
            }
          );
    }

    my $self = {
        configuration => $configuration,
        plugin        => $plugin,
        _oauth2       => $oauth2
    };

    bless $self, $class;
    return $self;
}

=head2 Internal methods

=head3 oauth2

Return the initialized OAuth2 object

=cut

sub oauth2 {
    my ( $self, $centralServer ) = @_;

    return $self->{_oauth2}->{$centralServer};
}

1;
