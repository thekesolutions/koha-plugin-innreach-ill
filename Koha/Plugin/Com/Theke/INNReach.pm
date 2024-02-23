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

use Encode;
use List::MoreUtils qw(any);
use Mojo::JSON qw(decode_json encode_json);
use YAML::XS;

use C4::Circulation;

use Koha::Biblioitems;
use Koha::Illrequestattributes;
use Koha::Illrequests;
use Koha::Items;

use Koha::Plugin::Com::Theke::INNReach::Contribution;
use Koha::Plugin::Com::Theke::INNReach::OAuth2;
use Koha::Plugin::Com::Theke::INNReach::Utils qw(innreach_warn);

BEGIN {
    my $path = Module::Metadata->find_module_by_name(__PACKAGE__);
    $path =~ s!\.pm$!/lib!;
    unshift @INC, $path;

    require INNReach::BackgroundJobs::BorrowingSite::ItemInTransit;
    require INNReach::BackgroundJobs::BorrowingSite::ItemReceived;
    require INNReach::BackgroundJobs::OwningSite::CancelRequest;
    require INNReach::BackgroundJobs::OwningSite::FinalCheckin;
    require INNReach::BackgroundJobs::OwningSite::ItemShipped;
}

our $VERSION = "{VERSION}";

our $metadata = {
    name            => 'INN-Reach connector plugin for Koha',
    author          => 'Theke Solutions',
    date_authored   => '2018-09-10',
    date_updated    => "1980-06-18",
    minimum_version => '22.1100000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'INN-Reach ILL integration module.',
    namespace       => 'innreach',
};

=head1 Koha::Plugin::Com::Theke::INNReach

INN-Reach connector plugin for Koha

=head2 Plugin methods

=head3 new

Constructor:

    my $plugin = Koha::Plugin::Com::Theke::INNReach->new;

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

    my $errors = $self->check_configuration;

    $template->param( errors => $errors );

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
    eval {
        $configuration = YAML::XS::Load(
            Encode::encode_utf8( $self->retrieve_data('configuration') ) );
    };
    die($@) if $@;

    my @default_item_types;

    foreach my $centralServer ( keys %{ $configuration } ) {
        # Reverse the library_to_location key
        my $library_to_location = $configuration->{$centralServer}->{library_to_location};
        $configuration->{$centralServer}->{location_to_library} =
          { map { $library_to_location->{$_}->{location} => $_ }
              keys %{$library_to_location} };

        # Reverse the local_to_central_patron_type key
        my $local_to_central_patron_type = $configuration->{$centralServer}->{local_to_central_patron_type};
        my %central_to_local_patron_type = reverse %{ $local_to_central_patron_type };
        $configuration->{$centralServer}->{central_to_local_patron_type} = \%central_to_local_patron_type;

        push @default_item_types, $configuration->{$centralServer}->{default_item_type}
            if exists $configuration->{$centralServer}->{default_item_type};

        $configuration->{$centralServer}->{debt_blocks_holds} //= 1;
        $configuration->{$centralServer}->{max_debt_blocks_holds} //= 100;
        $configuration->{$centralServer}->{expiration_blocks_holds} //= 1;
        $configuration->{$centralServer}->{restriction_blocks_holds} //= 1;
    }

    $configuration->{default_item_types} = \@default_item_types;

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
                `object_type`  ENUM('biblio', 'item', 'circulation', 'holds') NOT NULL DEFAULT 'biblio',
                `object_id`    INT(11) NOT NULL DEFAULT 0,
                `payload`      TEXT DEFAULT NULL,
                `action`       ENUM('create', 'modify', 'delete', 'renewal', 'checkin', 'checkout', 'fill', 'cancel') NOT NULL DEFAULT 'modify',
                `status`       ENUM('queued', 'retry', 'success', 'error', 'skipped') NOT NULL DEFAULT 'queued',
                `attempts`     INT(11) NOT NULL DEFAULT 0,
                `last_error`   VARCHAR(191) DEFAULT NULL,
                `timestamp`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `central_server` VARCHAR(10) NOT NULL,
                PRIMARY KEY (`id`),
                KEY `status` (`status`),
                KEY `central_server` (`central_server`)
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

    my $contributed_biblios = $self->get_qualified_table_name('contributed_biblios');

    unless ( $self->_table_exists( $contributed_biblios ) ) {
        C4::Context->dbh->do(qq{
            CREATE TABLE $contributed_biblios (
                `central_server` VARCHAR(191) NOT NULL,
                `biblio_id`      INT(11) NOT NULL,
                `timestamp`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`central_server`,`biblio_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        });
    }

    my $contributed_items = $self->get_qualified_table_name('contributed_items');

    unless ( $self->_table_exists( $contributed_items ) ) {
        C4::Context->dbh->do(qq{
            CREATE TABLE $contributed_items (
                `central_server` VARCHAR(191) NOT NULL,
                `item_id`        INT(11) NOT NULL,
                `timestamp`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`central_server`,`item_id`)
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

    my $new_version = "1.1.0";
    if (
        Koha::Plugins::Base::_version_compare(
            $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1
      )
    {

        my $task_queue = $self->get_qualified_table_name('task_queue');

        unless ( $self->_table_exists($task_queue) ) {
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

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    $new_version = "1.1.18";
    if (
        Koha::Plugins::Base::_version_compare(
            $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1
      )
    {

        my $task_queue = $self->get_qualified_table_name('task_queue');

        unless ( $self->_table_exists($task_queue) ) {
            C4::Context->dbh->do(qq{
                ALTER TABLE $task_queue
                    ADD COLUMN `last_error` VARCHAR(191) DEFAULT NULL AFTER `attempts`;
            });
        }

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    $new_version = "2.1.4";
    if (
        Koha::Plugins::Base::_version_compare(
            $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1
      )
    {

        my $agency_to_patron =
          $self->get_qualified_table_name('agency_to_patron');

        unless ( $self->_table_exists($agency_to_patron) ) {
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

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    $new_version = "2.2.6";
    if (
        Koha::Plugins::Base::_version_compare(
            $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1
      )
    {

        my $task_queue = $self->get_qualified_table_name('task_queue');

        if ( $self->_table_exists($task_queue) ) {
            C4::Context->dbh->do(qq{
                ALTER TABLE $task_queue
                    ADD COLUMN    `payload` TEXT DEFAULT NULL AFTER `object_id`,
                    MODIFY COLUMN `action`  ENUM('create', 'modify', 'delete', 'renew') NOT NULL DEFAULT 'modify';
            });
        }

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    $new_version = "2.3.0";
    if (
        Koha::Plugins::Base::_version_compare(
            $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1
      )
    {

        my $task_queue = $self->get_qualified_table_name('task_queue');

        if ( $self->_table_exists($task_queue) ) {
            C4::Context->dbh->do(qq{
                ALTER TABLE $task_queue
                    ADD COLUMN `central_server` VARCHAR(10) NOT NULL AFTER `timestamp`;
            });
            C4::Context->dbh->do(qq{
                ALTER TABLE $task_queue
                    ADD KEY `central_server` (`central_server`);
            });
        }

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    $new_version = "2.6.12";
    if (
        Koha::Plugins::Base::_version_compare(
            $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1
      )
    {

        my $task_queue = $self->get_qualified_table_name('task_queue');

        if ( $self->_table_exists($task_queue) ) {
            C4::Context->dbh->do(qq{
                ALTER TABLE $task_queue
                    MODIFY COLUMN `action` ENUM('create', 'modify', 'delete', 'renewal', 'checkin', 'checkout') NOT NULL DEFAULT 'modify';
            });
        }

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    $new_version = "3.3.14";
    if (
        Koha::Plugins::Base::_version_compare(
            $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1
      )
    {

        my $task_queue = $self->get_qualified_table_name('task_queue');

        if ( $self->_table_exists($task_queue) ) {
            C4::Context->dbh->do(qq{
                ALTER TABLE $task_queue
                    MODIFY COLUMN `status` ENUM('queued', 'retry', 'success', 'error', 'skipped') NOT NULL DEFAULT 'queued';
            });
        }

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    $new_version = "3.4.0";
    if (
        Koha::Plugins::Base::_version_compare(
            $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1
      )
    {
        my $contributed_biblios = $self->get_qualified_table_name('contributed_biblios');

        if ( !$self->_table_exists( $contributed_biblios ) ) {
            C4::Context->dbh->do(qq{
                CREATE TABLE $contributed_biblios (
                    `central_server` VARCHAR(191) NOT NULL,
                    `biblio_id`      INT(11) NOT NULL,
                    `timestamp`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (`central_server`,`biblio_id`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
            });
        }

        my $contributed_items = $self->get_qualified_table_name('contributed_items');

        if ( !$self->_table_exists( $contributed_items ) ) {
            C4::Context->dbh->do(qq{
                CREATE TABLE $contributed_items (
                    `central_server` VARCHAR(191) NOT NULL,
                    `item_id`        INT(11) NOT NULL,
                    `timestamp`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (`central_server`,`item_id`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
            });
        }

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    $new_version = "3.8.1";
    if (
        Koha::Plugins::Base::_version_compare(
            $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1
      )
    {

        my $task_queue = $self->get_qualified_table_name('task_queue');

        if ( $self->_table_exists($task_queue) ) {
            C4::Context->dbh->do(qq{
                ALTER TABLE $task_queue
                    MODIFY COLUMN `object_type` ENUM('biblio', 'item', 'circulation') NOT NULL DEFAULT 'biblio';
            });
        }

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    $new_version = "3.8.5";
    if (
        Koha::Plugins::Base::_version_compare(
            $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1
      )
    {

        my $task_queue = $self->get_qualified_table_name('task_queue');

        if ( $self->_table_exists($task_queue) ) {
            C4::Context->dbh->do(qq{
                ALTER TABLE $task_queue
                    MODIFY COLUMN `object_type` ENUM('biblio', 'item', 'circulation', 'holds') NOT NULL DEFAULT 'biblio';
            });

            C4::Context->dbh->do(qq{
                ALTER TABLE $task_queue
                    MODIFY COLUMN `action` ENUM('create', 'modify', 'delete', 'renewal', 'checkin', 'checkout', 'fill', 'cancel') NOT NULL DEFAULT 'modify';
            });
        }

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    return 1;
}

=head3 _table_exists (helper)

Method to check if a table exists in Koha.

FIXME: Should be made available to plugins in core

=cut

sub _table_exists {
    my ($self, $table) = @_;
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
    my $biblio    = $args->{biblio};

    my $task_queue    = $self->get_qualified_table_name('task_queue');
    my $configuration = $self->configuration;
    my $contribution  = Koha::Plugin::Com::Theke::INNReach::Contribution->new( { plugin => $self } );

    my @central_servers = $self->central_servers;

    foreach my $central_server ( @central_servers ) {

        if ( $action ne 'delete' ) {

            my $item_type = $biblio->itemtype;

            # We don't contribute ILL-generated records
            # or unmapped types
            next
                if $item_type eq $configuration->{$central_server}->{default_item_type}
                   or !exists $configuration->{$central_server}->{local_to_central_itype}->{$item_type};

            my $exclude_empty_biblios =
              ( !exists $configuration->{$central_server}->{contribution} )
              ? 1
              : $configuration->{$central_server}->{contribution}->{exclude_empty_biblios};

            if ( $action eq 'create' ) {
                ## We are adding, check some configurations
                # exclude_empty_biblios
                if ( $exclude_empty_biblios ) {
                    next
                      unless $contribution->filter_items_by_contributable(
                        {
                            items          => scalar $biblio->items,
                            central_server => $central_server
                        }
                    )->count > 0;
                }
            }
            elsif ( $action eq 'modify' ) {
                if (     $exclude_empty_biblios
                     and $contribution->filter_items_by_contributable(
                            {   items          => scalar $biblio->items,
                                central_server => $central_server }
                         )->count == 0
                     and $contribution->is_bib_contributed(
                            { biblio_id      => $biblio_id,
                              central_server => $central_server })
                ) {
                    # decontribute
                    $self->schedule_task(
                        {   action         => 'delete',
                            central_server => $central_server,
                            object_id      => $biblio_id,
                            object_type    => 'biblio',
                            status         => 'queued',
                        }
                    );
                    next;
                }
            }
        }
        else { # $action eq 'delete'
            next
              unless $contribution->is_bib_contributed(
                  {  biblio_id => $biblio_id,
                      central_server => $central_server, });
        }

        $self->schedule_task(
            {   action         => $action,
                central_server => $central_server,
                object_id      => $biblio_id,
                object_type    => 'biblio',
                status         => 'queued',
            }
        );
    }
}

=head3 after_item_action

Hook that is caled on item modification

=cut

sub after_item_action {
    my ( $self, $args ) = @_;

    my $action  = $args->{action};
    my $item_id = $args->{item_id};
    my $item    = $args->{item};

    my $configuration = $self->configuration;
    my $contribution  = Koha::Plugin::Com::Theke::INNReach::Contribution->new( { plugin => $self } );

    my @central_servers = $self->central_servers;

    foreach my $central_server ( @central_servers ) {

        if ( $action ne 'delete' ) {

            my $item_type = $item->itype;

            # We don't contribute ILL-generated items
            next
                if $item_type eq $configuration->{$central_server}->{default_item_type};

            # Skip if rules say so
            next
                if (
                !$contribution->should_item_be_contributed(
                    {
                        item           => $item,
                        central_server => $central_server
                    }
                )
                );

            # Skip if item type is not mapped
            if ( !exists $configuration->{$central_server}->{local_to_central_itype}->{$item_type} ) {
                innreach_warn("No 'local_to_central_itype' mapping for $item_type ($central_server)");
                next;
            }
        }

        $self->schedule_task(
            {
                action         => $action,
                central_server => $central_server,
                object_id      => $item_id,
                object_type    => 'item',
                status         => 'queued',
            }
        );

        # Do it after inserting the item de-contribution
        if ( $action eq 'delete' ) {

            my $exclude_empty_biblios =
              ( !exists $configuration->{$central_server}->{contribution} )
              ? 1
              : $configuration->{$central_server}->{contribution}->{exclude_empty_biblios};

            if ( $exclude_empty_biblios ) {

                my $biblio = Koha::Biblios->find( $item->biblionumber );

                if (    $biblio
                    and $contribution->filter_items_by_contributable(
                        {   items          => scalar $biblio->items,
                            central_server => $central_server,
                        }
                    )->count == 0
                ) {
                    $self->schedule_task(
                        {   action         => 'delete',
                            central_server => $central_server,
                            object_id      => $biblio->id,
                            object_type    => 'biblio',
                            status         => 'queued',
                        }
                    );
                }
            }
        }
    }
}

=head3 after_circ_action

Hook that is caled on circulation actions

Note: Koha updates item statuses on circulation, so circulation updates on items
are notified by the I<after_item_action> hook.

So far, only renewals of ILL-linked items are taken care of here.

=cut

sub after_circ_action {
    my ( $self, $params ) = @_;

    my $action = $params->{action};

    my $checkout = $params->{payload}->{checkout};

    my $req = Koha::Plugin::Com::Theke::INNReach::Utils::get_ill_request_from_attribute(
        {
            type  => 'checkout_id',
            value => $checkout->id,
        }
    );

    return
        unless $req;

    my $central_server = $req->extended_attributes->find( { type => 'centralCode' } )->value;

    if ( $action eq 'renewal' ) {

        $self->schedule_task(
            {
                action         => $action,
                central_server => $central_server,
                object_id      => $checkout->item->id,
                object_type    => 'item',
                payload        => encode_json( $params->{payload} ),
                status         => 'queued',
            }
        );
    } elsif ( $action eq 'checkin' ) {

        if (
            any { $req->status eq $_ }
            qw(O_ITEM_CANCELLED
            O_ITEM_CANCELLED_BY_US
            O_ITEM_CLAIMED_RETURNED
            O_ITEM_IN_TRANSIT
            O_ITEM_RETURN_UNCIRCULATED
            O_ITEM_RECEIVED_DESTINATION)
            )
        {
            INNReach::BackgroundJobs::OwningSite::FinalCheckin->new->enqueue(
                {
                    ill_request_id => $req->id,
                }
            ) if $self->configuration->{$central_server}->{lending}->{automatic_final_checkin};
        } elsif ( any { $req->status eq $_ } qw{B_ITEM_RECEIVED B_ITEM_RECALLED} ) {
            INNReach::BackgroundJobs::BorrowingSite::ItemInTransit->new->enqueue(
                {
                    ill_request_id => $req->id,
                }
            ) if $self->configuration->{$central_server}->{borrowing}->{automatic_item_in_transit};
        }
    }
}

=head3 after_hold_action

Hook that is caled on holds-related actions

=cut

sub after_hold_action {
    my ( $self, $params ) = @_;

    my $action = $params->{action};

    my $payload = $params->{payload};
    my $hold    = $payload->{hold};

    my $req = Koha::Plugin::Com::Theke::INNReach::Utils::get_ill_request_from_attribute(
        {
            type  => 'hold_id',
            value => $hold->id,
        }
    );

    # skip actions if this is not an ILL request
    return
        unless $req;

    if ( $req->status =~ /^O_/ ) {
        if ( $action eq 'fill' || $action eq 'waiting' || $action eq 'transfer' ) {

            if ( $req->status eq 'O_ITEM_REQUESTED' ) {

                my $central_server = $self->get_req_central_server($req);

                INNReach::BackgroundJobs::OwningSite::ItemShipped->new->enqueue(
                    {
                        ill_request_id => $req->id,
                    }
                ) if $self->configuration->{$central_server}->{lending}->{automatic_item_shipped};
            }
        } elsif ( $action eq 'cancel' ) {

            if ( $req->status eq 'O_ITEM_REQUESTED' ) {

                INNReach::BackgroundJobs::OwningSite::CancelRequest->new->enqueue(
                    {
                        ill_request_id => $req->id,
                    }
                );
            }
        }
    }
    elsif ( $req->status =~ /^B_/ ) {
        if ( $action eq 'fill' || $action eq 'waiting' || $action eq 'transfer' ) {
            if ( $req->status eq 'B_ITEM_SHIPPED' ) {

                my $central_server = $self->get_req_central_server($req);

                INNReach::BackgroundJobs::BorrowingSite::ItemReceived->new->enqueue(
                    {
                        ill_request_id => $req->id,
                    }
                ) if $self->configuration->{$central_server}->{borrowing}->{automatic_item_receive};
            }
        }
    }
}

=head3 schedule_task

    $plugin->schedule_task(
        {
            action         => $action,
            central_server => $central_server,
            object_type    => $object_type,
            object_id      => $object->id
        }
    );

Method for adding tasks to the queue

=cut

sub schedule_task {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(action central_server object_type object_id);
    foreach my $param (@mandatory_params) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    my $action         = $params->{action};
    my $central_server = $params->{central_server};
    my $object_type    = $params->{object_type};
    my $object_id      = $params->{object_id};
    my $payload        = $params->{payload};

    $payload = ""
        unless $payload;

    my $task_queue = $self->get_qualified_table_name('task_queue');

    C4::Context->dbh->do(
        qq{
        INSERT INTO $task_queue
            (  central_server,     object_type,   object_id,   action,   status,  attempts,  payload )
        VALUES
            ( '$central_server', '$object_type', $object_id, '$action', 'queued',        0, '$payload' );
    }
    );

    return $self;
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

=head3 background_tasks

Plugin hook used to register new background_job types

=cut

sub background_tasks {
    return {
        b_item_in_transit => 'INNReach::BackgroundJobs::BorrowingSite::ItemInTransit',
        b_item_received   => 'INNReach::BackgroundJobs::BorrowingSite::ItemReceived',
        o_cancel_request  => 'INNReach::BackgroundJobs::OwningSite::CancelRequest',
        o_final_checkin   => 'INNReach::BackgroundJobs::OwningSite::FinalCheckin',
        o_item_shipped    => 'INNReach::BackgroundJobs::OwningSite::ItemShipped',
    };
}

=head3 template_include_paths

Plugin hook used to register paths to find templates

=cut

sub template_include_paths {
    my ($self) = @_;

    return [
        $self->mbf_path('templates'),
    ];
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

    my @mandatory_params = qw(central_server local_server description agency_id);
    foreach my $param ( @mandatory_params ) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $args->{$param};
    }

    my $central_server = $args->{central_server};
    my $local_server   = $args->{local_server};
    my $description    = $args->{description};
    my $agency_id      = $args->{agency_id};

    my $agency_to_patron = $self->get_qualified_table_name('agency_to_patron');

    my $library_id    = $self->configuration->{$central_server}->{partners_library_id};
    my $category_code = $self->configuration->{$central_server}->{partners_category}
        // C4::Context->config("interlibrary_loans")->{partner_code};

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

    my $library_id    = $self->configuration->{$central_server}->{partners_library_id};
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

=head3 central_servers

    my @central_servers = $self->central_servers;

=cut

sub central_servers {
    my ( $self ) = @_;

    my $configuration = $self->configuration;

    if ( defined $configuration ) {
        return grep { $_ ne 'default_item_types' } keys %{ $configuration };
    }

    return ();
}

=head3 get_ill_request_from_biblio_id

This method retrieves the Koha::ILLRequest using a biblio_id.

=cut

sub get_ill_request_from_biblio_id {
    my ( $self, $args ) = @_;

    my $biblio_id = $args->{biblio_id};

    unless ( $biblio_id ) {
        INNReach::Ill::UnknownBiblioId->throw( biblio_id => $biblio_id );
    }

    my $reqs = Koha::Illrequests->search({ biblio_id => $biblio_id });

    if ( $reqs->count > 1 ) {
        innreach_warn( "More than one ILL request for biblio_id ($biblio_id). Beware!");
    }

    return unless $reqs->count > 0;

    my $req = $reqs->next;

    return $req;
}

=head3 get_ua

This method retrieves a user agent to contact a central server.

=cut

sub get_ua {
    my ( $self, $central_server ) = @_;

    my $configuration = $self->configuration->{$central_server};

    unless ( $self->{_oauth2}->{$central_server} ) {
        $self->{_oauth2}->{$central_server} = Koha::Plugin::Com::Theke::INNReach::OAuth2->new({
            client_id          => $configuration->{client_id},
            client_secret      => $configuration->{client_secret},
            api_base_url       => $configuration->{api_base_url},
            api_token_base_url => $configuration->{api_token_base_url},
            local_server_code  => $configuration->{localServerCode},
            debug_requests     => $configuration->{debug_requests},
        });
    }

    return $self->{_oauth2}->{$central_server};
}


=head3 contribution

This method retrieves a I<Koha::Plugin::Com::Theke::INNReach::Contribution> object.

=cut

sub contribution {
    my ($self) = @_;

    return Koha::Plugin::Com::Theke::INNReach::Contribution->new( { plugin => $self } );
}

=head3 get_req_central_server

This method returns the central server code a Koha::Illrequest is linked to.

=cut

sub get_req_central_server {
    my ( $self, $req ) = @_;

    my $attr = $req->extended_attributes->find( { type => 'centralCode' } );

    return $attr->value
        if $attr;
}


=head2 Wrappers for Koha functions

This methods deal with changes to the ABI of the underlying methods
across different Koha versions.

=head3 add_issue

    my $checkout = $plugin->add_issue(
        {
            patron  => $patron,
            barcode => $barcode
        }
    );

Wrapper for I<C4::Circulation::AddIssue>.

Parameters:

=over

=item B<patron>: a I<Koha::Patron> object.

=item B<barcode>: a I<string> containing an item barcode.

=back

=cut

sub add_issue {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(barcode patron);
    foreach my $param (@mandatory_params) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    return ( C4::Context->preference('Version') ge '23.110000' )
        ? C4::Circulation::AddIssue( $params->{patron},            $params->{barcode} )
        : C4::Circulation::AddIssue( $params->{patron}->unblessed, $params->{barcode} );
}

=head3 add_return

    $plugin->add_return( { barcode => $barcode } );

Wrapper for I<C4::Circulation::AddReturn>. The return value is the
same as C4::Circulation::AddReturn.

Parameters:

=over

=item B<barcode>: a I<string> containing an item barcode.

=back

=cut

sub add_return {
    my ( $self, $params ) = @_;

    my @mandatory_params = qw(barcode);
    foreach my $param (@mandatory_params) {
        INNReach::Ill::MissingParameter->throw( param => $param )
            unless exists $params->{$param};
    }

    return C4::Circulation::AddReturn( $params->{barcode} );
}

=head3 check_configuration

    my $errors = $self->check_configuration;

Returns a reference to a list of errors found in configuration.

=cut

sub check_configuration {
    my ($self) = @_;

    my @errors;

    my $configuration   = $self->configuration;
    my @central_servers = grep { $_ ne 'default_item_types' } keys %{$configuration};

    foreach my $central_server (@central_servers) {
        push @errors,
            {
            code  => 'undefined_partners_library_id',
            value => $configuration->{$central_server}->{partners_library_id}, central_server => $central_server
            }
            unless Koha::Libraries->find( $configuration->{$central_server}->{partners_library_id} );
    }

    foreach my $central_server (@central_servers) {
        push @errors,
            {
            code  => 'undefined_partners_category',
            value => $configuration->{$central_server}->{partners_category}, central_server => $central_server
            }
            unless Koha::Patron::Categories->find( $configuration->{$central_server}->{partners_category} );
    }

    push @errors, { code => 'ILLModule_disabled' }
        unless C4::Context->preference('ILLModule');

    push @errors, { code => 'CirculateILL_enabled' }
        if C4::Context->preference('CirculateILL');

    return \@errors;
}

1;
