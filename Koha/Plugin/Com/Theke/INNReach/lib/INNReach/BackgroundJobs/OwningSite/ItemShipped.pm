package INNReach::BackgroundJobs::OwningSite::ItemShipped;

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

use base 'Koha::BackgroundJob';

use Try::Tiny;

use Koha::Illrequests;
use Koha::Plugin::Com::Theke::INNReach;
use Koha::Plugin::Com::Theke::INNReach::Exceptions;

use INNReach::Commands::OwningSite;

=head1 NAME

INNReach::BackgroundJobs::OwningSite::ItemShipped - Background task for notifying
an item has been shipped.

This is a subclass of Koha::BackgroundJob.

=head1 API

=head2 Class methods

=head3 job_type

Define the job type of this job: greeter

=cut

sub job_type {
    return 'plugin_innreach_itemshipped';
}

=head3 process

Process the modification.

=cut

sub process {
    my ( $self, $args ) = @_;

    $self->start;

    my @messages;

    my $report   = { total_success => 0, };
    my $commands = INNReach::Commands::OwningSite->new( { plugin => Koha::Plugin::Com::Theke::INNReach->new } );

    # ill_request_id param required by ->enqueue()
    my $req = Koha::Illrequests->find( $args->{ill_request_id} );

    try {
        $commands->item_shipped( $req );
        $report->{ total_success }++;
    }
    catch {
        push @messages, "Error: $_";
    };

    $self->step;

    my $data = $self->decoded_data;
    $data->{messages} = \@messages;
    $data->{report}   = $report;

    $self->finish($data);
}

=head3 enqueue

Enqueue the new job.

=cut

sub enqueue {
    my ( $self, $args ) = @_;

    INNReach::Ill::MissingParameter->throw( param => 'ill_request_id' )
        unless $args->{ill_request_id};

    $self->SUPER::enqueue(
        {
            job_args => $args,
            job_size => 1,
        }
    );
}

1;
