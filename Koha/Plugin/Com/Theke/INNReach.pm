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
    date_updated    => "2019-10-02",
    minimum_version => '18.05',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'INN-Reach ILL integration module.'
};

=head1 Koha::Plugin::Com::Theke::INNReach

INN-Reach connector plugin for Koha

=head2 Plugin methods

=head3 new

Constructor:

    $my $plugin = Koha::Plugin::Com::Theke::INNReach->new;

=cut

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

=head3 configure

Plugin configuration method

=cut

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

=head3 configuration

Accessor for the de-serialized plugin configuration

=cut

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

=head3 install

Install method. Takes care of table creation and initialization if required

=cut

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

    my $agency_to_patron = $self->get_qualified_table_name('agency_to_patron');

    unless ( $self->_table_exists( $agency_to_patron ) ) {
        C4::Context->dbh->do(qq{
            CREATE TABLE $agency_to_patron (
                `central_server` VARCHAR(191) NOT NULL,
                `local_server`   VARCHAR(191) NULL DEFAULT NULL,
                `agency_id`      VARCHAR(191) NOT NULL,
                `patron_id`      INT(11) NOT NULL,
                `timestamp`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`central_server`,`agency_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        });
    }

    return 1;
}

=head3 upgrade

Takes care of upgrading whatever is needed (table structure, new tables, information on those)

=cut

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

    if ( Koha::Plugins::Base::_version_compare( $database_version, "2.1.3" ) == -1 ) {

        my $agency_to_patron = $self->get_qualified_table_name('agency_to_patron');

        unless ( $self->_table_exists( $agency_to_patron ) ) {
            C4::Context->dbh->do(qq{
                CREATE TABLE $agency_to_patron (
                    `central_server` VARCHAR(191) NOT NULL,
                    `local_server`   VARCHAR(191) NULL DEFAULT NULL,
                    `agency_id`      VARCHAR(191) NOT NULL,
                    `patron_id`      INT(11) NOT NULL,
                    `timestamp`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (`central_server`,`agency_id`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
            });
        }

        $self->store_data({ '__INSTALLED_VERSION__' => "2.1.4" });
    }

    return 1;
}

=head3 _table_exists (helper)

Method to check if a table exists in Koha.

FIXME: Should be made available to plugins in core

=cut

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

=head3 after_biblio_action

Hook that is called on biblio modification

=cut

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

=head3 after_item_action

Hool that is caled on item modification

=cut

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

=head3 api_routes

Method that returns the API routes to be merged into Koha's

=cut

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

=head3 api_namespace

Method that returns the namespace for the plugin API to be put on

=cut

sub api_namespace {
    my ( $self ) = @_;
    
    return 'innreach';
}

=head2 Business methods

=head3 generate_patron_for_agency

    my $patron = $plugin->generate_patron_for_agency(
        {
            central_server => $central_server,
            local_server   => $local_server,
            agency_id      => $agency_id,
            description    => $description
        }
    );

Generates a patron representing a library in the consortia that might make
material requests (borrowing site). It is used on the circulation workflow to
place a hold on the requested items.

=cut

sub generate_patron_for_agency {
    my ( $self, $args ) = @_;

    my $central_server = $args->{central_server};
    my $local_server   = $args->{local_server};
    my $description    = $args->{description};
    my $agency_id      = $args->{agency_id};

    my $agency_to_patron = $self->get_qualified_table_name('agency_to_patron');

    my $library_id    = $self->configuration->{partners_library_id};
    my $category_code = C4::Context->config("interlibrary_loans")->{partner_code};

    my $patron;

    Koha::Database->schema->txn_do( sub {
        $patron = Koha::Patron->new(
            {
                branchcode   => $library_id,
                categorycode => $category_code,
                surname      => $self->gen_patron_description(
                    {
                        central_server => $central_server,
                        local_server   => $local_server,
                        description    => $description,
                        agency_id      => $agency_id
                    }
                ),
                cardnumber => $self->gen_cardnumber(
                    {
                        central_server => $central_server,
                        local_server   => $local_server,
                        description    => $description,
                        agency_id      => $agency_id
                    }
                )
            }
        )->store;

        my $patron_id = $patron->borrowernumber;

        my $dbh = C4::Context->dbh;
        my $sth = $dbh->prepare(qq{
            INSERT INTO $agency_to_patron
              ( central_server, local_server, agency_id, patron_id )
            VALUES
              ( '$central_server', '$local_server', '$agency_id', '$patron_id' );
        });

        $sth->execute();
    });

    return $patron;
}

=head3 update_patron_for_agency

    my $patron = $plugin->update_patron_for_agency(
        {
            central_server => $central_server,
            local_server   => $local_server,
            agency_id      => $agency_id,
            description    => $description
        }
    );

Updates a patron representing a library in the consortia that might make
material requests (borrowing site). It is used by cronjobs to keep things up
to date if there are changes on the central server info.

See: scripts/sync_agencies.pl

=cut

sub update_patron_for_agency {
    my ( $self, $args ) = @_;

    my $central_server = $args->{central_server};
    my $local_server   = $args->{local_server};
    my $description    = $args->{description};
    my $agency_id      = $args->{agency_id};

    my $agency_to_patron = $self->get_qualified_table_name('agency_to_patron');

    my $library_id    = $self->configuration->{partners_library_id};
    my $category_code = C4::Context->config("interlibrary_loans")->{partner_code};

    my $patron;

    Koha::Database->schema->txn_do( sub {

        my $patron_id = $self->get_patron_id_from_agency({
            central_server => $central_server,
            agency_id      => $agency_id
        });

        $patron = Koha::Patrons->find( $patron_id );
        $patron->set(
            {
                surname => $self->gen_patron_description(
                    {
                        central_server => $central_server,
                        local_server   => $local_server,
                        description    => $description,
                        agency_id      => $agency_id
                    }
                ),
                cardnumber => $self->gen_cardnumber(
                    {
                        central_server => $central_server,
                        local_server   => $local_server,
                        description    => $description,
                        agency_id      => $agency_id
                    }
                )
            }
        )->store;
    });

    return $patron;
}

=head3 get_patron_id_from_agency

    my $patron_id = $plugin->get_patron_id_from_agency(
        {
            central_server => $central_server,
            agency_id      => $agency_id
        }
    );

Given an agency_id (which usually comes in the patronAgencyCode attribute on the itemhold request)
and a central_server code, it returns Koha's patron id so the hold request can be correctly assigned.

=cut

sub get_patron_id_from_agency {
    my ( $self, $args ) = @_;

    my $central_server = $args->{central_server};
    my $agency_id      = $args->{agency_id};

    my $agency_to_patron = $self->get_qualified_table_name('agency_to_patron');
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare(qq{
        SELECT patron_id
        FROM   $agency_to_patron
        WHERE  agency_id='$agency_id' AND central_server='$central_server'
    });

    $sth->execute();
    my $result = $sth->fetchrow_hashref;

    unless ($result) {
        return;
    }

    return $result->{patron_id};
}

=head3 gen_patron_description

    my $patron_description = $plugin->gen_patron_description(
        {
            central_server => $central_server,
            local_server   => $local_server,
            description    => $description,
            agency_id      => $agency_id
        }
    );

This method encapsulates patron description generation based on the provided information.
The idea is that any change on this regard should happen on a single place.

=cut

sub gen_patron_description {
    my ( $self, $args ) = @_;

    my $central_server = $args->{central_server};
    my $local_server   = $args->{local_server};
    my $description    = $args->{description};
    my $agency_id      = $args->{agency_id};

    return "$description ($agency_id)";
}

=head3 gen_cardnumber

    my $cardnumber = $plugin->gen_cardnumber(
        {
            central_server => $central_server,
            local_server   => $local_server,
            description    => $description,
            agency_id      => $agency_id
        }
    );

This method encapsulates patron description generation based on the provided information.
The idea is that any change on this regard should happen on a single place.

=cut

sub gen_cardnumber {
    my ( $self, $args ) = @_;

    my $central_server = $args->{central_server};
    my $local_server   = $args->{local_server};
    my $description    = $args->{description};
    my $agency_id      = $args->{agency_id};

    return 'ILL_' . $central_server . '_' . $agency_id;
}



1;
