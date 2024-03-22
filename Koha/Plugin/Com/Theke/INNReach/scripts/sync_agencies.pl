#!/usr/bin/perl

#
# Copyright 2019 Theke Solutions
#
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

use DDP;
use Getopt::Long;
use Text::Table;

use Koha::Plugin::Com::Theke::INNReach;

use Koha::Script qw(-cron);

binmode( STDOUT, ':encoding(utf8)' );

my $verbose;
my $local_server;
my $central_server;
my $dry_run = 0;

my $result = GetOptions(
    'v|verbose'        => \$verbose,
    'local_server=s'   => \$local_server,
    'central_server=s' => \$central_server,
    'dry_run'          => \$dry_run
);

unless ($result) {
    print_usage();
    die "Not sure what wen't wrong";
}

sub print_usage {
    print <<_USAGE_;

Valid options are:

    --local_server      Only sync specified local_server
    --central_server    Only sync the specified central server agencies
    --dry_run           Don't make any changes
    -v | --verbose      Verbose output

_USAGE_
}

my $plugin = Koha::Plugin::Com::Theke::INNReach->new;

my @central_servers = $plugin->central_servers;
@central_servers = grep { $_ eq $central_server } @central_servers
    if $central_server;

unless ( scalar @central_servers > 0 ) {
    print_usage();
    print STDERR "No central servers to sync.\n";
}

my @rows;

foreach my $central_server (@central_servers) {

    my $result = $plugin->sync_agencies($central_server);

    if ($verbose) {
        foreach my $server ( keys %{$result} ) {
            foreach my $agency_id ( keys %{ $result->{$server} } ) {
                push @rows,
                    [
                    $central_server, $server, $agency_id, $result->{$server}->{$agency_id}->{description},
                    $result->{$server}->{$agency_id}->{current_status}, $result->{$server}->{$agency_id}->{status}
                    ];
            }
        }
    }
}

if ( scalar @rows && $verbose) {
    my $table = Text::Table->new(
        'central_server',
        'local_code',
        'agency_code',
        'description',
        'current_status',
        'new_status',
    );
    $table->load(@rows);
    print STDOUT $table;
}

1;
