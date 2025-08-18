package INNReach::BackgroundJobs::OwningSite::CancelRequest;

# This is free software; you can redistribute it and/or modify it
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

use Try::Tiny qw(catch try);

use Koha::Plugin::Com::Theke::INNReach::Exceptions;

=head1 NAME

INNReach::BackgroundJobs::OwningSite::CancelRequest - Background task for notifying
request cancellation.

This is a subclass of Koha::BackgroundJob.

=head1 API

=head2 Class methods

=head3 job_type

Define the job type of this job: greeter

=cut

sub job_type {
    return 'plugin_innreach_o_cancel_request';
}

=head3 process

Process the modification.

=cut

sub process {
    my ( $self, $args ) = @_;

    $self->start;

    my @messages;

    require Koha::Plugin::Com::Theke::INNReach;
    my $plugin   = Koha::Plugin::Com::Theke::INNReach->new;
    my $commands = $plugin->owning_commands;

    # ill_request_id param required by ->enqueue()
    my $req = $plugin->get_ill_rs()->find( $args->{ill_request_id} );

    try {
        $commands->cancel_request($req);
        $self->step;
    } catch {
        if ( ref($_) eq 'INNReach::Ill::RequestFailed' ) {
            push @messages, {
                type     => 'error',
                code     => 'request_failed',
                response => $_->response->decoded_content,
                method   => $_->method,
            };
        } else {
            push @messages, {
                type  => 'error',
                code  => 'unhandled_error',
                error => "$_",
            };
        }

        $self->set( { progress => 0, status => 'failed' } );
    };

    my $data = $self->decoded_data;
    $data->{messages} = \@messages;

    return $self->finish($data);
}

=head3 enqueue

Enqueue the new job.

=cut

sub enqueue {
    my ( $self, $args ) = @_;

    INNReach::Ill::MissingParameter->throw( param => 'ill_request_id' )
        unless $args->{ill_request_id};

    return $self->SUPER::enqueue(
        {
            job_args => $args,
            job_size => 1,
        }
    );
}

1;
