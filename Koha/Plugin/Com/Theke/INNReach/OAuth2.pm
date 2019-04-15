package Koha::Plugin::Com::Theke::INNReach::OAuth2;

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

use base qw(Class::Accessor);

__PACKAGE__->mk_accessors(qw( ua access_token ));

use DateTime;
use HTTP::Request::Common qw{ POST };
use JSON;
use LWP::UserAgent;
use MIME::Base64 qw{ decode_base64url encode_base64url };

use Exception::Class (
  'INNReach::OAuth2Error',
  'INNReach::OAuth2Error::MissingClientID'  => { isa => 'INNReach::OAuth2Error' },
  'INNReach::OAuth2Error::MissingClientCredentials'  => { isa => 'INNReach::OAuth2Error' },
);

sub new {
    my ($class, $args) = @_;

    my $client_id     = $args->{client_id};
    unless ($client_id) {
        INNReach::OAuth2Error::MissingClientID->throw("Missing client_id");
    }

    my $client_secret = $args->{client_secret};
    unless ($client_secret) {
        INNReach::OAuth2Error::MissingClientCredentials->throw("Missing client_secret");
    }

    my $api_base_url = $args->{api_base_url};
    unless ( $api_base_url ) {
        INNReach::OAuth2Error->throw("Missing api_base_url in configuration");
    }

    my $credentials = encode_base64url( "$client_id:$client_secret" );

    my $self = $class->SUPER::new($args);
    $self->{token_endpoint} = "$api_base_url/auth/v1/oauth2/token";
    $self->{ua}          = LWP::UserAgent->new();
    $self->{scope}       = "innreach_tp";
    $self->{grant_type}  = 'client_credentials';
    $self->{credentials} = $credentials;
    $self->{request}     = POST(
        $self->{token_endpoint},
        Authorization => "Basic $credentials",
        Accept        => "application/json",,
        ContentType   => "application/x-www-form-urlencoded",
        Content       =>
        [
            grant_type => 'client_credentials',
            scope      => $self->{scope},
            undefined  => undef,
        ]
    );

    bless $self, $class;

    # Get the first token we will use
    $self->refresh_token;

    return $self;
}

sub refresh_token {
    my ($self) = @_;

    my $ua      = $self->{ua};
    my $request = $self->{request};

    my $response = decode_json( $ua->request($request)->decoded_content );
    $self->{access_token} = $response->{access_token};
    $self->{expiration}   = DateTime->now()->add( seconds => $response->{expires_in} );

    return $self;
}

sub is_token_expired {
    my ($self) = @_;

    return $self->{expiration} < DateTime->now();
}

sub get_token {
    my ($self) = @_;

    $self->refresh_token
        if $self->is_token_expired;

    return $self->{access_token};
}

1;
