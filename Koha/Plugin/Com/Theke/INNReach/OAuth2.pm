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
use HTTP::Request::Common qw{ DELETE GET POST PUT };
use JSON;
use LWP::UserAgent;
use MIME::Base64 qw{ decode_base64url encode_base64url };

use Exception::Class (
  'INNReach::OAuth2Error',
  'INNReach::OAuth2Error::MissingClientID'  => { isa => 'INNReach::OAuth2Error' },
  'INNReach::OAuth2Error::MissingClientCredentials'  => { isa => 'INNReach::OAuth2Error' },
  'INNReach::OAuth2Error::MissingLocalServerCode' => { isa => 'INNReach::OAuth2Error' },
  'INNReach::OAuth2Error::AuthError' => { isa => 'INNReach::OAuth2Error' },
);

=head1 Koha::Plugin::Com::Theke::INNReach::OAuth2

A class implementing the OAuth2 authentication with INN-Reach central servers.

=head2 Class methods

=head3 new

    my $oauth = Koha::Plugin::Com::Theke::INNReach::OAuth2->new(
        {
            client_id     => 'a_client_id',
            client_secret => 'a_client_secret',
            api_base_url  => 'https://api.base.url',
            localServerCode => 'localServerCode'
        }
    );

Constructor for the OAuth2 class implementing the interaction with INN-Reach
central servers

=cut

sub new {
    my ($class, $args) = @_;

    my $local_server_code = $args->{local_server_code};
    unless ($local_server_code) {
        INNReach::OAuth2Error::MissingLocalServerCode->throw("Missing local_server_code");
    }

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
    $self->{localServerCode}    = $local_server_code;
    $self->{api_base_url}       = $api_base_url;
    $self->{api_token_base_url} = $args->{api_token_base_url} // $api_base_url;
    $self->{token_endpoint}     = $self->{api_token_base_url} . "/auth/v1/oauth2/token";
    $self->{ua}                 = LWP::UserAgent->new();
    $self->{scope}              = "innreach_tp";
    $self->{grant_type}         = 'client_credentials';
    $self->{credentials}        = $credentials;
    $self->{request}            = POST(
        $self->{token_endpoint},
        Authorization => "Basic $credentials",
        Accept        => "application/json",
        ,
        ContentType => "application/x-www-form-urlencoded",
        Content     => [
            grant_type => 'client_credentials',
            scope      => $self->{scope},
            undefined  => undef,
        ]
    );
    $self->{debug_mode} = ( $args->{debug_mode} ) ? 1 : 0;

    bless $self, $class;

    # Get the first token we will use
    $self->refresh_token;

    return $self;
}

=head3 post_request

Generic request for POST

=cut

sub post_request {
    my ( $self, $args ) = @_;

    my $request = POST(
        $self->{api_base_url} . '/' . $args->{endpoint},
        'Authorization' => "Bearer " . $self->get_token,
        'X-From-Code'   => $self->{local_server_code},
        'X-To-Code'     => $args->{centralCode},
        'Accept'        => "application/json",
        'Content-Type'  => "application/json",
        'Content'       => ( exists $args->{data} )
        ? encode_json( $args->{data} )
        : undef
    );

    if ( $self->{debug_mode} ) {
        warn p($request);
    }

    return $self->ua->request($request);
}

=head3 put_request

Generic request for PUT

=cut

sub put_request {
    my ( $self, $args ) = @_;

    my $request = PUT(
        $self->{api_base_url} . '/' . $args->{endpoint},
        'Authorization' => "Bearer " . $self->get_token,
        'X-From-Code'   => $self->{local_server_code},
        'X-To-Code'     => $args->{centralCode},
        'Accept'        => "application/json",
        'Content-Type'  => "application/json",
        'Content'       => encode_json( $args->{data} )
    );

    if ( $self->{debug_mode} ) {
        warn p($request);
    }

    return $self->ua->request($request);
}

=head3 get_request

Generic request for GET

=cut

sub get_request {
    my ( $self, $args ) = @_;

    my $request = GET(
        $self->{api_base_url} . '/' . $args->{endpoint},
        'Authorization' => "Bearer " . $self->get_token,
        'X-From-Code'   => $self->{local_server_code},
        'X-To-Code'     => $args->{centralCode},
        'Accept'        => "application/json",
        'Content-Type'  => "application/json"
    );

    if ( $self->{debug_mode} ) {
        warn p($request);
    }

    return $self->ua->request($request);
}

=head3 delete_request

Generic request for DELETE

=cut

sub delete_request {
    my ( $self, $args ) = @_;

    my $request = DELETE(
        $self->{api_base_url} . '/' . $args->{endpoint},
        'Authorization' => "Bearer " . $self->get_token,
        'X-From-Code'   => $self->{local_server_code},
        'X-To-Code'     => $args->{centralCode},
        'Accept'        => "application/json",
    );

    if ( $self->{debug_mode} ) {
        warn p($request);
    }

    return $self->ua->request($request);
}

=head2 Internal methods


=head3 get_token

    my $token = $oauth->get_token;

This method takes care of fetching an access token from INN-Reach.
It is cached, along with the calculated expiration date. I<refresh_token>
is I<is_token_expired> returns true.

In general, this method shouldn't be used when using this library. The
I<request_*> methods should be used directly, and they would request the
access token as needed.

=cut

sub get_token {
    my ($self) = @_;

    $self->refresh_token
      if $self->is_token_expired;

    return $self->{access_token};
}

=head3 refresh_token

    $oauth->refresh_token;

Method that takes care of retrieving a new token. This method is
B<not intended> to be used on its own. I<get_token> should be used
instead.

=cut

sub refresh_token {
    my ($self) = @_;

    my $ua      = $self->{ua};
    my $request = $self->{request};

    my $response         = $ua->request($request);
    my $response_content = decode_json( $response->decoded_content );

    unless ( $response->code eq '200' ) {
        INNReach::OAuth2Error::AuthError->throw(
            "Authentication error: " . $response_content->{error_description} );
    }

    $self->{access_token} = $response_content->{access_token};
    $self->{expiration} =
      DateTime->now()->add( seconds => $response_content->{expires_in} );

    return $self;
}

=head3 is_token_expired

    if ( $oauth->is_token_expired ) { ... }

This helper method tests if the current token is expired.

=cut

sub is_token_expired {
    my ($self) = @_;

    return $self->{expiration} < DateTime->now();
}

1;
