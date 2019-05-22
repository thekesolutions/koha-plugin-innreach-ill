package Koha::Plugin::Com::Theke::INNReach;

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

use base qw(Koha::Plugins::Base);

use Mojo::JSON qw(decode_json);
use YAML;

our $VERSION = "{VERSION}";

our $metadata = {
    name            => 'INNReach connector plugin for Koha',
    author          => 'Theke Solutions',
    date_authored   => '2018-09-10',
    date_updated    => "2019-02-20",
    minimum_version => '18.05.00.000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'INN-Reach ILL integration module.'
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template({ file => 'configure.tt' });

    unless ( scalar $cgi->param('save') ) {

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            configuration => $self->retrieve_data('configuration'),
        );

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                configuration => scalar $cgi->param('configuration'),
            }
        );
        $template->param(
            configuration => $self->retrieve_data('configuration'),
        );
        $self->output_html( $template->output() );
    }
}

sub configuration {
    my ($self) = @_;

    my $configuration;
    eval { $configuration = YAML::Load( $self->retrieve_data('configuration') . "\n\n" ); };
    die($@) if $@;

    return $configuration;
}

# sub install {
#     my ( $self, $args ) = @_;

#     my $central_servers = $self->get_qualified_table_name('central_servers');

#     return C4::Context->dbh->do(qq{
#         CREATE TABLE  $central_servers (
#             `code` VARCHAR(5) NOT NULL DEFAULT '',
#             `description` VARCHAR(191) DEFAULT '',
#             PRIMARY KEY (`code`)
#         ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
#     });

#     my $library_to_central = $self->get_qualified_table_name('library_to_central');

#     return C4::Context->dbh->do(qq{
#         CREATE TABLE  $library_to_central (
#             `library_id` VARCHAR(10) DEFAULT NULL,
#             `code` VARCHAR(5) NOT NULL DEFAULT '',
#             `description` VARCHAR(191),
#             PRIMARY KEY (`code`),
#             CONSTRAINT `branches_innreach_ibfk_1`
#                 FOREIGN KEY (`library_id`)
#                 REFERENCES `branches` (`branchcode`)
#                 ON DELETE CASCADE ON UPDATE CASCADE
#         ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
#     });
# }

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub api_namespace {
    my ( $self ) = @_;
    
    return 'innreach';
}

1;
