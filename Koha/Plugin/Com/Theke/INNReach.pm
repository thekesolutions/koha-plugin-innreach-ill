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
    name            => 'INN-Reach connector plugin for Koha',
    author          => 'Theke Solutions',
    date_authored   => '2018-09-10',
    date_updated    => "2019-02-20",
    minimum_version => '18.05',
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

    # Reverse the library_to_location key
    my $library_to_location = $configuration->{library_to_location};
    my %location_to_library = reverse %{ $library_to_location };
    $configuration->{location_to_library} = \%location_to_library;

    # Reverse the local_to_central_itype key
    my $local_to_central_itype = $configuration->{local_to_central_itype};
    my %central_to_local_itype = reverse %{ $local_to_central_itype };
    $configuration->{central_to_local_itype} = \%central_to_local_itype;

    # Reverse the local_to_central_patron_type key
    my $local_to_central_patron_type = $configuration->{local_to_central_patron_type};
    my %central_to_local_patron_type = reverse %{ $local_to_central_patron_type };
    $configuration->{central_to_local_patron_type} = \%central_to_local_patron_type;

    return $configuration;
}

sub install {
    my ( $self, $args ) = @_;

    my $task_queue = $self->get_qualified_table_name('task_queue');

    unless ( $self->_table_exists( $task_queue ) ) {
        C4::Context->dbh->do(qq{
            CREATE TABLE $task_queue (
                `id`           INT(11) NOT NULL AUTO_INCREMENT,
                `object_type`  ENUM('biblio', 'item') NOT NULL DEFAULT 'biblio',
                `object_id`    INT(11) NOT NULL DEFAULT 0,
                `action`       ENUM('create', 'modify', 'delete') NOT NULL DEFAULT 'modify',
                `status`       ENUM('queued', 'retry', 'success', 'error') NOT NULL DEFAULT 'queued',
                `attempts`     INT(11) NOT NULL DEFAULT 0,
                `last_error`   VARCHAR(191) DEFAULT NULL,
                `timestamp`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `status` (`status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        });
    }

    return 1;
}


sub upgrade {
    my ( $self, $args ) = @_;

    my $database_version = $self->retrieve_data('__INSTALLED_VERSION__') || 0;

    if ( Koha::Plugins::Base::_version_compare( $database_version, "1.0.2" ) == -1 ) {

        my $task_queue = $self->get_qualified_table_name('task_queue');

        unless ($self->_table_exists( $task_queue )) {
            C4::Context->dbh->do(qq{
                CREATE TABLE $task_queue (
                    `id`           INT(11) NOT NULL AUTO_INCREMENT,
                    `object_type`  ENUM('biblio', 'item') NOT NULL DEFAULT 'biblio',
                    `object_id`    INT(11) NOT NULL DEFAULT 0,
                    `action`       ENUM('create', 'modify', 'delete') NOT NULL DEFAULT 'modify',
                    `status`       ENUM('queued', 'retry', 'success', 'error') NOT NULL DEFAULT 'queued',
                    `attempts`     INT(11) NOT NULL DEFAULT 0,
                    `timestamp`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (`id`),
                    KEY `status` (`status`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
            });
        }

        $self->store_data({ '__INSTALLED_VERSION__' => "1.1.0" });
    }

    if ( Koha::Plugins::Base::_version_compare( $database_version, "1.1.17" ) == -1 ) {

        my $task_queue = $self->get_qualified_table_name('task_queue');

        unless ($self->_table_exists( $task_queue )) {
            C4::Context->dbh->do(qq{
                ALTER TABLE $task_queue
                    ADD COLUMN `last_error` VARCHAR(191) DEFAULT NULL AFTER `attempts`;
            });
        }

        $self->store_data({ '__INSTALLED_VERSION__' => "1.1.18" });
    }

    return 1;
}

sub _table_exists {
    my $table = shift;
    eval {
        C4::Context->dbh->{PrintError} = 0;
        C4::Context->dbh->{RaiseError} = 1;
        C4::Context->dbh->do(qq{SELECT * FROM $table WHERE 1 = 0 });
    };
    return 1 unless $@;
    return 0;
}

sub after_biblio_action {
    my ( $self, $args ) = @_;

    my $action    = $args->{action};
    my $biblio_id = $args->{biblio_id};

    my $task_queue = $self->get_qualified_table_name('task_queue');

    return C4::Context->dbh->do(qq{
        INSERT INTO $task_queue
            ( object_type, object_id, action, status, attempts )
        VALUES
            ( 'biblio', $biblio_id, '$action', 'queued', 0 )
    });
}

sub after_item_action {
    my ( $self, $args ) = @_;

    my $action  = $args->{action};
    my $item_id = $args->{item_id};

    my $task_queue = $self->get_qualified_table_name('task_queue');

    return C4::Context->dbh->do(qq{
        INSERT INTO $task_queue
            ( object_type, object_id, action, status, attempts )
        VALUES
            ( 'item', $item_id, '$action', 'queued', 0 )
    });
}

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
