#!/usr/bin/perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Getopt::Long;
use JSON qw(decode_json);
use Pod::Usage;
use Try::Tiny;

use C4::Context;

use Koha::Plugin::Com::Theke::INNReach;
use Koha::Plugin::Com::Theke::INNReach::Contribution;

my $daemon_sleep    = 5;
my $verbose_logging = 0;
my $help       = 0;

my $result = GetOptions(
    'help|?'  => \$help,
    'v'       => \$verbose_logging,
    'sleep=s' => \$daemon_sleep,
);

if (not $result or $help) {
    pod2usage(1);
}

my $dbh;

while (1) {
    try {

        my $contribution = Koha::Plugin::Com::Theke::INNReach::Contribution->new;
        run_queued_tasks({ contribution => $contribution });

    }
    catch {
        if ($@ && $verbose_logging) {
            warn "Warning : $@\n";
        }
    };

    sleep $daemon_sleep;
}

=head3 run_queued_tasks

=cut

sub run_queued_tasks {
    my ($args) = @_;

    my $contribution = $args->{contribution};

    my $dbh = C4::Context->dbh;

    my $plugin = Koha::Plugin::Com::Theke::INNReach->new;
    my $table  = $plugin->get_qualified_table_name('task_queue');

    my $query = $dbh->prepare(qq{
        SELECT
            id,
            object_type,
            object_id,
            payload,
            action,
            attempts,
            timestamp,
            central_server
        FROM
            $table
        WHERE
            status='queued' OR
            status='retry'
    });

    $query->execute;
    while ( my $task = $query->fetchrow_hashref ) {
        do_task({ task => $task, contribution => $contribution });
    }
}

=head3 do_task

=cut

sub do_task {
    my ($args) = @_;

    my $contribution = $args->{contribution};
    my $task         = $args->{task};
    die unless $task;

    my $object_type = $task->{object_type};
    my $object_id   = $task->{object_id};
    my $action      = $task->{action};

    if ( $object_type eq 'biblio' ) {
        if ( $action eq 'create' ) {
            do_biblio_contribute({ biblio_id => $object_id, contribution => $contribution, task => $task });
        }
        elsif ( $action eq 'modify' ) {
            do_biblio_contribute({ biblio_id => $object_id, contribution => $contribution, task => $task });
        }
        elsif ( $action eq 'delete' ) {
            do_biblio_decontribute({ biblio_id => $object_id, contribution => $contribution, task => $task });
        }
    }
    elsif ( $object_type eq 'item' ) {
        if ( $action eq 'create' ) {
            do_item_contribute({ item_id => $object_id, contribution => $contribution, task => $task });
        }
        elsif ( $action eq 'modify' ) {
            do_item_contribute({ item_id => $object_id, contribution => $contribution, task => $task });
        }
        elsif ( $action eq 'delete' ) {
            do_item_decontribute({ item_id => $object_id, contribution => $contribution, task => $task });
        }
        elsif ( $action eq 'renewal' ) {
            handle_item_renewal({ item_id => $object_id, contribution => $contribution, task => $task });
        }
    }
    else {
        warn "Unhandled object_type: $object_type";
    }
}

=head3 do_biblio_contribute

=cut

sub do_biblio_contribute {
    my ($args) = @_;

    my $biblio_id    = $args->{biblio_id};
    my $contribution = $args->{contribution};
    my $task         = $args->{task};

    try {
        my $result = $contribution->contribute_bib({ bibId => $biblio_id, centralServer => $task->{central_server} });
        if ( $result ) {
            if ( $task->{attempts} <= $contribution->config->{contribution}->{max_retries} // 10 ) {
                mark_task({ task => $task, status => 'retry' });
            }
            else {
                mark_task({ task => $task, status => 'error' });
            }
        }
        else {
            mark_task({ task => $task, status => 'success' });
        }
    }
    catch {
        if ( ref($_) eq 'INNReach::Ill::UnknownBiblioId' ) {
            warn "do_biblio_contribute: biblio not found ($biblio_id) [skipped]";
            mark_task( { task => $task, status => 'skipped', error => 'Biblio not found' } );
            return 1;
        }
        else {
            warn "do_biblio_contribute: $_";
            mark_task({ task => $task, status => 'error', error => "$_" });
        }
    };

    return 1;
}

=head3 do_biblio_decontribute

=cut

sub do_biblio_decontribute {
    my ($args) = @_;

    my $biblio_id    = $args->{biblio_id};
    my $contribution = $args->{contribution};
    my $task         = $args->{task};

    try {
        my $result = $contribution->decontribute_bib({ bibId => $biblio_id, centralServer => $task->{central_server} });
        if ( $result ) {
            if ( $task->{attempts} <= $contribution->config->{contribution}->{max_retries} // 10 ) {
                mark_task({ task => $task, status => 'retry' });
            }
            else {
                mark_task({ task => $task, status => 'error' });
            }
        }
        else {
            mark_task({ task => $task, status => 'success' });
        }
    }
    catch {
        warn "do_biblio_decontribute: $_";
        mark_task({ task => $task, status => 'error', error => "$_" });
    };

    return 1;
}

=head3 do_item_contribute

=cut

sub do_item_contribute {
    my ($args) = @_;

    my $item_id      = $args->{item_id};
    my $contribution = $args->{contribution};
    my $task         = $args->{task};

    my $item = Koha::Items->find( $item_id );

    unless ( $item ) {
        warn "do_item_contribute: item not found ($item_id) [skipped]";
        mark_task( { task => $task, status => 'skipped', error => 'Item not found' } );
    }

    my $biblio_id = $item->biblionumber;

    try {
        my $result = $contribution->contribute_batch_items({ item => $item, bibId => $biblio_id, centralServer => $task->{central_server} });
        if ( $result ) {
            if ( $task->{attempts} <= $contribution->config->{contribution}->{max_retries} // 10 ) {
                mark_task({ task => $task, status => 'retry' });
            }
            else {
                mark_task({ task => $task, status => 'error' });
            }
        }
        else {
            mark_task({ task => $task, status => 'success' });
        }
    }
    catch {
        warn "do_item_decontribute: $_";
        mark_task({ task => $task, status => 'error', error => "$_" });
    };

    return 1;
}

=head3 do_item_decontribute

=cut

sub do_item_decontribute {
    my ($args) = @_;

    my $item_id      = $args->{item_id};
    my $contribution = $args->{contribution};
    my $task         = $args->{task};

    try {
        my $result = $contribution->decontribute_item({ itemId => $item_id, centralServer => $task->{central_server} });
        if ( $result ) {
            if ( $task->{attempts} <= $contribution->config->{contribution}->{max_retries} // 10 ) {
                mark_task({ task => $task, status => 'retry' });
            }
            else {
                mark_task({ task => $task, status => 'error' });
            }
        }
        else {
            mark_task({ task => $task, status => 'success' });
        }
    }
    catch {
        warn "do_item_decontribute: $_";
        mark_task({ task => $task, status => 'error', error => "$_" });
    };

    return 1;
}

sub handle_item_renewal {
    my ($args) = @_;

    my $item_id      = $args->{item_id};
    my $contribution = $args->{contribution};
    my $task         = $args->{task};
    my $payload      = decode_json($task->{payload});

    try {
        my $result = $contribution->notify_borrower_renew(
            {
                item_id  => $item_id,
                date_due => $payload->{date_due}
            }
        );
        if ( $result ) {
            if ( $task->{attempts} <= $contribution->config->{contribution}->{max_retries} // 10 ) {
                mark_task({ task => $task, status => 'retry' });
            }
            else {
                mark_task({ task => $task, status => 'error' });
            }
        }
        else {
            mark_task({ task => $task, status => 'success' });
        }
    }
    catch {
        mark_task({ task => $task, status => 'error', error => "$_" });
    };
}

sub mark_task {
    my ($args)   = @_;
    my $task     = $args->{task};
    my $status   = $args->{status};
    my $task_id  = $task->{id};
    my $attempts = $task->{attempts} // 0;
    my $error    = $task->{error};

    my $dbh = C4::Context->dbh;

    my $plugin = Koha::Plugin::Com::Theke::INNReach->new;
    my $table  = $plugin->get_qualified_table_name('task_queue');

    $attempts++ if $status eq 'retry';

    my $query;
    if ( defined $error ) {
        $query = $dbh->prepare(qq{
            UPDATE
                $table
            SET
                status='$status',
                attempts=$attempts,
                last_error='$error'
            WHERE
                id=$task_id
        });
    }
    else {
        $query = $dbh->prepare(qq{
            UPDATE
                $table
            SET
                status='$status',
                attempts=$attempts,
                last_error=NULL
            WHERE
                id=$task_id
        });
    }

    $query->execute;
}

=head1 NAME

task_queue_daemon.pl

=head1 SYNOPSIS

task_queue_daemon.pl -s 5

 Options:
   -?|--help        brief help message
   -v               Be verbose
   --sleep N        Polling frecquency

=head1 OPTIONS

=over 8

=item B<--help|-?>

Print a brief help message and exits

=item B<-v>

Be verbose

=item B<--sleep N>

Use I<N> as the database polling frecquency.

=back

=head1 DESCRIPTION

A task queue processor daemon that takes care of updating INN-Reach central's server information
on catalog changes (both bibliographic records and holdings information) as well as relevant circulation
events.

=cut
